#!/bin/bash
set -euo pipefail

transi_root="$(cd "$(dirname "$0")/.." && pwd)"
transi_test_cache="$(mktemp -d "${TMPDIR:-/tmp}/transi-trip-live-activity-check.XXXXXX")"
trap 'rm -r -- "$transi_test_cache"' EXIT

# Compile the production trip models, the trip Live Activity's step logic without ActivityKit (unavailable on
# macOS) and the trip detail's following of it, then replay the real legs of scripts/fixtures/trip-detail.json.
sed -n '/^\/\/ Swift regression checks/,/^SWIFT$/ { /^SWIFT$/!p; }' "$0" > "$transi_test_cache/main.swift"
{
    printf '%s\n' 'class TripPlannerController {}' 'protocol ActivityAttributes {}'
    grep -v '^import ActivityKit$' "$transi_root/VirtualTableActivity/TripActivityAttributes.swift"
    awk '/^extension Part \{/,/^}/' "$transi_root/Shared/Controllers/PartLiveTracker.swift"
    # The trip detail's steps and map focus, which follow the trip's progress.
    awk '/^enum JourneyStep/,/^}/
        /^enum MapFocus/,/^}/
        /^extension Journey \{/,/^}/
        /^extension Part \{/,/^}/
        /^extension TripProgress \{/,/^}/' "$transi_root/Transi/Trip Planner/TripDetailModel.swift"
} > "$transi_test_cache/stubs.swift"
shared="$transi_root/Shared"
xcrun swiftc -module-cache-path "$transi_test_cache" -target "$(uname -m)-apple-macosx14.0" \
    -o "$transi_test_cache/check" \
    "$shared/Models/Trip.swift" "$shared/Models/TripProgress.swift" "$shared/Models/StopGps.swift" \
    "$shared/Models/ApiModels.swift" "$shared/Models/AnyCodable.swift" "$shared/Models/Stops.swift" \
    "$shared/Models/Table.swift" "$shared/Util/DateTime.swift" "$shared/Extensions/Date.swift" \
    "$shared/Extensions/String.swift" "$shared/Extensions/CLLocationCoordinate2D.swift" \
    "$shared/Controllers/TripPlannerController+Mapping.swift" \
    "$transi_test_cache/stubs.swift" "$transi_test_cache/main.swift"
"$transi_test_cache/check" "$transi_root/scripts/fixtures/trip-detail.json"
exit

: <<'SWIFT'
// Swift regression checks
import Foundation

struct Fixture: Decodable {
    let raptor: RApiTrip
    let trip: BApiTrip
    let cepo: IApiTripResponse
    let stops: [Stop]
}

let apiDecoder = JSONDecoder()
apiDecoder.keyDecodingStrategy = .convertFromSnakeCase
let fixture = try apiDecoder.decode(
    Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
)
let localFormatter = DateFormatter()
localFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
localFormatter.timeZone = TimeZone(identifier: "Europe/Bratislava")
func local(_ time: String) -> Date { localFormatter.date(from: "2026-10-05 \(time.count == 5 ? time + ":00" : time)")! }
let planner = TripPlannerController()

// R-API: 72 Hronská A 08:00 → Rajská A 08:21 with its 18 stops from the B-API, a 10-minute walk, then
// 31 Kollárovo nám. D 08:31 → Zochova B 08:33, whose stops did not load (boarding and alighting only).
let rJourneys = planner.mapRApiToJourneys(fixture.raptor.journey ?? [])
var walkChange = rJourneys[0]
walkChange.parts![0].stops = fixture.trip.partStops(for: walkChange.parts![0], stops: fixture.stops)
// I-API: 72 Hronská → Autobusová stanica 08:18, 42 from the same platform at 08:21 to Kollárovo nám. B,
// 80 from there at 08:31 to Zochova; every leg with its full stop list.
let sameStopChanges = planner.mapIApiToJourneys(fixture.cepo.journeys ?? [], stops: fixture.stops)[0]

func at(
    _ time: String, _ journey: Journey = walkChange, live: [Int: Int] = [:], passedStops: [Int: Int] = [:],
    alerted: Set<String> = [], fix: TripFix? = nil, missed: TripMissed? = nil
) -> TripUpdate {
    journey.update(
        at: local(time), delays: journey.delays(live: live), passedStops: passedStops, alerted: alerted, fix: fix,
        missed: missed
    )
}

// Before boarding: the first vehicle at its boarding stop, live delay included.
let waiting = at("07:56")
assert(waiting.progress.phase == .board(0) && waiting.state.step == .board && waiting.state.line == "72", "Board 72")
assert(waiting.state.title == "Board at Hronská" && waiting.state.detail == "Platform A · in 4 min"
       && waiting.state.compact == "4 min" && waiting.state.minimal == "4m" && waiting.state.delay == nil,
       "Board text: \(waiting.state)")
let late = at("07:56", live: [0: 120])
assert(late.state.detail == "Platform A · in 6 min" && late.state.delay == 2 && late.state.time == local("08:02"),
       "A 2-minute late 72 leaves at 08:02")
assert(at("08:01", live: [0: 120]).progress.phase == .board(0), "Still waiting for the late 72 at 08:01")
// The time moves by the whole minutes the delay reads as, like the trip detail's times and change buffers.
for (seconds, minutes, time) in [(20, 0, "08:00"), (50, 1, "08:01"), (90, 2, "08:02"), (-50, -1, "07:59")] {
    let shown = at("07:56", live: [0: seconds]).state
    assert(shown.delay == minutes && shown.time == local(time), "\(seconds) s late reads \(time): \(shown)")
}
assert(at("07:59:30").state.detail == "Platform A · in <1 min" && at("06:50").state.detail == "Platform A · at "
       + timeStringFromDate(local("08:00")), "Countdown under a minute and over an hour")
assert(waiting.state.warning == .tightChange, "The 31 leaves as the walk ends: a tight change ahead")
assert(at("07:56").alert == nil, "No alert before boarding")
assert(walkChange.trackerTargets(for: waiting.progress) == [TripTrackerTarget(part: 0, stop: 0)],
       "Watch only the boarding stop")
print("PASS: before boarding, with and without a live delay")

// Riding: stops left from the stop times, corrected by the stop the vehicle left last.
let riding = at("08:10:30")
assert(riding.progress == TripProgress(phase: .ride(0), nextStop: 10, stopsLeft: 8, fraction: 0.56),
       "Pažítková is next, 8 stops to Rajská: \(riding.progress)")
assert(riding.state.title == "Get off in 8 stops" && riding.state.detail == "Rajská, platform A"
       && riding.state.compact == "8 stops" && riding.state.minimal == "8" && riding.state.time == local("08:21"),
       "Ride text: \(riding.state)")
let behind = at("08:10:30", passedStops: [0: 7])
assert(behind.progress.stopsLeft == 10 && behind.progress.nextStop == 8 && behind.progress.fraction! < 0.56,
       "The vehicle left Brodná last: 10 stops left")
assert(at("08:12", live: [0: 120]).progress.stopsLeft == 8, "A delay shifts every stop time")
assert(walkChange.trackerTargets(for: riding.progress)
       == [TripTrackerTarget(part: 0, stop: 10), TripTrackerTarget(part: 2, stop: 0)],
       "Follow the 72 at Pažítková and watch the 31 at Kollárovo nám.")
let lastStop = at("08:20:30")
assert(lastStop.progress.stopsLeft == 1 && lastStop.state.title == "Get off at the next stop", "Next stop")
assert(walkChange.trackerTargets(for: lastStop.progress)
       == [TripTrackerTarget(part: 0, stop: 16), TripTrackerTarget(part: 2, stop: 0)],
       "The 72 ends at Rajská, so keep following it at Ondrejský cintorín")
assert(at("08:20:30", passedStops: [0: 17]).state.title == "Get off now", "Left the alighting stop")
print("PASS: stops left, live position, delay shift and the followed stop")

// Changes: the walk to another stop, then two same-platform changes.
let change = at("08:25")
assert(change.progress.phase == .change(2) && change.state.title == "Walk to platform D"
       && change.state.detail == "Kollárovo nám. · 31 leaves in 6 min" && change.state.compact == "D · 6m"
       && change.state.minimal == "D" && change.state.line == "31" && change.state.warning == .tightChange,
       "Change text: \(change.state)")
assert(change.alert == TripAlert(key: "change-2", title: "Change to platform D",
                                 body: "Kollárovo nám. · 31 leaves in 6 min"), "Change alert")
assert(walkChange.trackerTargets(for: change.progress) == [TripTrackerTarget(part: 2, stop: 0)], "Watch the 31")
let missed = at("08:15", live: [0: 63])
assert(missed.state.warning == .likelyMissedChange && missed.alert?.key == "missed-2"
       && missed.alert?.title == "Change likely missed"
       && missed.alert?.body == "31 leaves Kollárovo nám. at \(timeStringFromDate(local("08:31")))",
       "A 63 s late 72 misses the 31: \(String(describing: missed.alert))")
let onTime = at("08:15", live: [0: 29])
assert(onTime.state.delay == 0 && onTime.state.warning == .tightChange && onTime.alert == nil
       && at("08:15", live: [0: 30]).state.warning == .likelyMissedChange,
       "The change is likely missed once the 72's delay shows as +1 min, not while it shows on time")
assert(at("08:15", live: [0: 63, 2: 120]).state.warning == .tightChange, "A late 31 still waits")
let atStation = at("08:19", sameStopChanges)
assert(atStation.progress.phase == .change(1) && atStation.state.title == "Wait at platform A"
       && atStation.state.detail == "42 leaves in 2 min", "Same-platform change: \(atStation.state)")
assert(at("08:28", sameStopChanges).state.title == "Wait at platform B", "Second same-platform change")
let toStation = at("08:17:30", sameStopChanges)
assert(sameStopChanges.trackerTargets(for: toStation.progress)
       == [TripTrackerTarget(part: 0, stop: 15), TripTrackerTarget(part: 1, stop: 0)],
       "The 72 continues past Autobusová stanica, so follow it there")
print("PASS: change steps, platforms, tight and likely missed changes")

// The last leg and the arrival.
let fallback = at("08:32")
assert(fallback.progress == TripProgress(phase: .ride(2), nextStop: 1, stopsLeft: nil, fraction: 0.5)
       && fallback.state.title == "Get off in 1 min" && fallback.state.detail == "Zochova, platform B"
       && fallback.state.compact == "1 min", "Without its stops the 31 counts minutes: \(fallback.state)")
assert(fallback.alert?.key == "off-2" && fallback.alert?.title == "Get off in 1 min", "Get off without stops")
assert(walkChange.trackerTargets(for: fallback.progress) == [TripTrackerTarget(part: 2, stop: 1)],
       "Follow the 31 at Zochova")
let lastLeg = at("08:32", sameStopChanges)
assert(lastLeg.progress.stopsLeft == 1 && lastLeg.state.title == "Get off at the next stop", "Two-stop leg")
let arrived = at("08:34")
assert(arrived.progress.phase == .arrived && arrived.state.title == "Arrived" && arrived.state.detail == "Zochova"
       && arrived.state.time == local("08:33") && arrived.state.warning == nil && arrived.alert == nil, "Arrived")
assert(walkChange.trackerTargets(for: arrived.progress).isEmpty, "No sockets once arrived")
assert(at("08:34", live: [2: 120]).progress.phase == .ride(2), "A late 31 is still riding")
var finalWalk = walkChange
finalWalk.parts = Array(walkChange.parts![0...1])
let walking = at("08:25", finalWalk)
assert(walking.progress.phase == .walk(1) && walking.state.title == "Walk to Kollárovo nám."
       && walking.state.detail == "Arrive in 6 min" && walking.state.line == nil, "Final walk: \(walking.state)")
assert(at("08:32", finalWalk).progress.phase == .arrived && at("08:32", finalWalk, live: [0: 120]).progress.phase
       == .walk(1), "The walk ends later after a late vehicle")
print("PASS: last leg with and without stops, final walk and arrival")

// The trip detail follows the step on its map and marks it in the steps.
let leg72 = walkChange.parts![0].legStops
func stretch(_ stops: ClosedRange<Int>, of leg: [PartStop] = leg72) -> MapFocus {
    .stretch(leg[stops].map { $0.gps! })
}
assert(waiting.progress.mapFocus(on: walkChange) == .change(to: 0) && waiting.progress.step(in: walkChange) == .ride(0),
       "Before boarding: Hronská, on the 72's step")
assert(riding.progress.mapFocus(on: walkChange) == stretch(9 ... 10) && riding.progress.step(in: walkChange) == .ride(0),
       "Riding: from the stop the 72 left to Pažítková")
assert(TripProgress(phase: .ride(0), nextStop: 15, stopsLeft: 3).mapFocus(on: walkChange) == stretch(14 ... 15)
       && TripProgress(phase: .ride(0), nextStop: 16, stopsLeft: 2).mapFocus(on: walkChange) == stretch(15 ... 17)
       && lastStop.progress.mapFocus(on: walkChange) == stretch(16 ... 17),
       "Rajská joins the stretch 2 stops before it")
assert(at("08:20:30", passedStops: [0: 17]).progress.mapFocus(on: walkChange) == stretch(16 ... 17),
       "Past Rajská: still the last stretch")
assert(change.progress.mapFocus(on: walkChange) == .change(to: 2)
       && change.progress.step(in: walkChange) == .walk([1], to: 2), "Changing: the walk to the 31")
assert(fallback.progress.mapFocus(on: walkChange) == stretch(0 ... 1, of: walkChange.parts![2].legStops),
       "The 31 without its stops: both ends")
assert(TripProgress(phase: .ride(2)).mapFocus(on: walkChange) == .part(2), "No position: the whole leg")
assert(atStation.progress.step(in: sameStopChanges) == .change(to: 1)
       && atStation.progress.mapFocus(on: sameStopChanges) == .change(to: 1), "A change at the same stop")
assert(walking.progress.mapFocus(on: finalWalk) == .part(1)
       && walking.progress.step(in: finalWalk) == .walk([1], to: nil), "The final walk")
assert(arrived.progress.mapFocus(on: walkChange) == .route && arrived.progress.step(in: walkChange) == nil,
       "Arrived: the whole route, no step")
let walkFirst = Journey(id: "walk-first", parts: Array(walkChange.parts![1...2]))
assert(TripProgress(phase: .board(1)).step(in: walkFirst) == .walk([0], to: 1)
       && TripProgress(phase: .board(1)).mapFocus(on: walkFirst) == .change(to: 1),
       "Before boarding after a walk: the walk to the stop")
print("PASS: the detail follows each step on the map and marks it")

// Alerts fire once per step: replay a 72 stuck between Autobusová stanica and Ondrejský cintorín, its
// position flapping and its delay growing every 10 s, then moving on to Rajská and the change.
var alerted = Set<String>()
var alerts = [String]()
var dueWithoutMemory = 0
var delay = 0
var previousPhase = TripProgress.Phase.board(0)
var phases = [TripProgress.Phase]()
for second in stride(from: 0, through: 15 * 60, by: 10) {
    let now = local("08:19").addingTimeInterval(TimeInterval(second))
    if second < 8 * 60 {
        delay += 10
    } else if second == 11 * 60 {
        delay += 90 // stuck again right after arriving: the ride resumes on paper
    }
    // Autobusová stanica, Ondrejský cintorín, Rajská.
    let position = second < 8 * 60 ? (second % 20 == 0 ? 15 : 16) : 17
    let update = walkChange.update(
        at: now, delays: walkChange.delays(live: [0: delay]), passedStops: [0: position], alerted: alerted
    )
    if let alert = update.alert { alerts.append(alert.key) }
    alerted = update.state.alerted
    let unremembered = walkChange.update(
        at: now, delays: walkChange.delays(live: [0: delay]), passedStops: [0: position]
    )
    if unremembered.alert != nil {
        dueWithoutMemory += 1
    }
    if update.progress.phase != previousPhase { phases.append(update.progress.phase) }
    previousPhase = update.progress.phase
}
assert(phases.contains(.change(2)) && phases.filter { $0 == .ride(0) }.count == 2, "Phases flap: \(phases)")
assert(dueWithoutMemory >= 40, "The replay keeps alerts due on most ticks (\(dueWithoutMemory))")
// The delay shows as +1 min from 30 s (08:19:20), after the 72 left Ondrejský cintorín (08:19:10) for Rajská.
assert(alerts == ["off-0", "missed-2", "change-2", "off-2"], "Each alert once: \(alerts)")
print("PASS: a stuck, flapping vehicle alerts \(alerts.count)× instead of \(dueWithoutMemory)× in 15 min: \(alerts)")

// Restoring: the alerts shown live in the content state, which survives a relaunch.
let restored = try JSONDecoder().decode(
    TripActivityAttributes.ContentState.self, from: JSONEncoder().encode(at("08:25").state)
)
assert(restored.alerted == ["change-2"] && at("08:25:30", alerted: restored.alerted).alert == nil,
       "No repeat after a relaunch")
let payload = try JSONEncoder().encode(at("08:25", sameStopChanges, live: [0: 63], alerted: alerted).state)
assert(payload.count < 1024, "Content state stays small: \(payload.count) bytes")
print("PASS: alerts survive a relaunch, \(payload.count)-byte content state")

// Delays: live only from online rows, else the B-API or search-time delay.
var online = Connection.example
online.delay = 2
var timetable = online
timetable.type = "cp"
assert(online.liveDelaySeconds == 120 && timetable.liveDelaySeconds == nil, "Only online rows are live")
let searchDelay = rJourneys[1]
assert(searchDelay.delays(live: [:]) == [0: 63] && searchDelay.delays(live: [0: 120]) == [0: 120],
       "Live delays win over the search-time delay")
assert(walkChange.delays(live: [:]).isEmpty, "No delay data")
print("PASS: delay sources")

// Live boards: a stop's board lists the followed vehicle with the stop it left last until it leaves, then drops it.
let leg = walkChange.parts![0]
func row(_ part: Part, busID: String = "1:2552", lastStop: String, leaves: Date, late: Int = 0) -> Connection {
    var row = Connection.example
    row.line = part.routeShortName ?? ""
    row.busID = busID
    row.lastStopName = lastStop
    row.departureTimeRaw = leaves.timeIntervalSince1970
    row.departureTimeCP = leaves.timeIntervalSince1970 - TimeInterval(late)
    row.delay = late / 60
    row.type = "online"
    return row
}
let prievozska = TripTrackerTarget(part: 0, stop: 11)
var boards = TripLiveData()
boards.receive(row(leg, lastStop: "Bratislava, Pažítková", leaves: local("08:13")), at: prievozska, of: walkChange,
               now: local("08:12"))
assert(boards.passedStops == [0: 10] && boards.busIDs == [0: "1:2552"] && boards.delays == [0: 0],
       "Prievozská's board lists the 72 with Pažítková, regional prefix and all: \(boards)")
assert(at("08:12", passedStops: boards.passedStops).progress.stopsLeft == 7, "7 stops from Prievozská")
let seen = boards
boards.receive(row(leg, lastStop: "Somewhere else", leaves: local("08:13")), at: prievozska, of: walkChange,
               now: local("08:12:10"))
assert(boards.passedStops == seen.passedStops, "Unknown stops are ignored")
boards.receive(nil, at: prievozska, of: walkChange, now: local("08:12:30"))
assert(boards.passedStops == seen.passedStops, "A reconnecting board before the vehicle is due is no departure")
boards.receive(nil, at: prievozska, of: walkChange, now: local("08:13:10"))
assert(boards.passedStops == [0: 11] && boards.busIDs == [0: "1:2552"] && boards.delays == [0: 0],
       "Dropped from the board once due: it passed Prievozská: \(boards)")
let miletičova = TripTrackerTarget(part: 0, stop: 12)
boards.receive(nil, at: miletičova, of: walkChange, now: local("08:16:59"))
assert(boards.passedStops == [0: 11], "A board that never listed the vehicle waits 3 minutes past its time")
boards.receive(nil, at: miletičova, of: walkChange, now: local("08:17:30"))
assert(boards.passedStops[0] == nil && at("08:17:30", passedStops: boards.passedStops).progress.stopsLeft == 3,
       "Then it counts by the timetable, which had it leave Košická at 08:17: \(boards.passedStops)")
boards.receive(nil, at: TripTrackerTarget(part: 2, stop: 0), of: walkChange, now: local("08:40"))
assert(boards.passedStops[2] == nil, "A boarding stop's board tells no position")
print("PASS: board updates set the followed vehicle's delay and the stop it left")

/// Replays the trip against live boards: a tracker's first update comes before its board loaded, then a stop's
/// board lists the vehicle `late` seconds late with the stop it left last until it leaves that stop, and the
/// line's next vehicle 2 minutes behind it. From `unlistedFrom` no board lists the vehicle any more. Trackers
/// match like PartLiveTracker: start from the vehicle followed so far, else lock onto the first one live. Starts
/// from `live` and `alerted`, as after a relaunch.
func replayBoards(
    _ journey: Journey, late: Int, from start: String, to end: String, unlistedFrom: String? = nil,
    live: TripLiveData = TripLiveData(), alerted: Set<String> = []
) -> (steps: [TripUpdate], alerts: [TripAlert], live: TripLiveData) {
    var live = live
    var alerted = alerted
    var loaded = Set<TripTrackerTarget>()
    var locked = [TripTrackerTarget: String]()
    var steps = [TripUpdate]()
    var alerts = [TripAlert]()
    var now = local(start)
    while now <= local(end) {
        let progress = journey.progress(
            at: now, delays: journey.delays(live: live.delays), passedStops: live.passedStops
        )
        for target in journey.trackerTargets(for: progress) {
            let part = journey.parts![target.part]
            let stops = part.legStops
            func leaves(_ stop: Int) -> Date { stops[stop].time + TimeInterval(late) }
            var board: Connection?
            if loaded.insert(target).inserted {
                locked[target] = live.busIDs[target.part]
            } else {
                let lastStop = stops.indices.last { leaves($0) <= now }.map { stops[$0].name } ?? "none"
                let next = row(part, busID: "1:99", lastStop: lastStop, leaves: leaves(target.stop) + 120, late: late)
                let ours = row(part, busID: "1:\(target.part)", lastStop: lastStop, leaves: leaves(target.stop),
                               late: late)
                let listsOurs = now < leaves(target.stop) && unlistedFrom.map { now < local($0) } ?? true
                board = part.liveConnection(
                    in: listsOurs ? [ours, next] : [next], platform: nil,
                    scheduled: stops[target.stop].time, busID: locked[target]
                )
                if locked[target] == nil, let board, board.type == "online" { locked[target] = board.busID }
            }
            live.receive(board, at: target, of: journey, now: now)
        }
        let update = journey.update(
            at: now, delays: journey.delays(live: live.delays), passedStops: live.passedStops, alerted: alerted
        )
        if let alert = update.alert { alerts.append(alert) }
        alerted = update.state.alerted
        steps.append(update)
        now += 10
    }
    return (steps, alerts, live)
}

func assertCountsDown(_ replay: (steps: [TripUpdate], alerts: [TripAlert], live: TripLiveData), from first: Int,
                      to alighting: Int, then next: TripProgress.Phase, _ name: String) {
    let rides = replay.steps.filter { $0.progress.phase == .ride(0) }
    let counts = rides.compactMap(\.progress.stopsLeft)
    assert(counts.first == first && counts.last == 1 && Set(counts) == Set(1...first)
           && zip(counts, counts.dropFirst()).allSatisfy { $0 >= $1 }, "\(name) counts down every stop: \(counts)")
    assert(rides.last?.progress.nextStop == alighting && replay.steps.last?.progress.phase == next,
           "\(name) ends its ride at the alighting stop: \(String(describing: rides.last?.progress))")
    let offAlerts = replay.alerts.filter { $0.key == "off-0" }
    assert(offAlerts.count == 1 && offAlerts[0].title == "Get off at the next stop",
           "\(name) alerts to get off once: \(replay.alerts.map(\.key))")
}

// The 72 ends at Rajská, so its board never lists it: follow it to Ondrejský cintorín.
let terminating = replayBoards(walkChange, late: 60, from: "07:58", to: "08:24")
assertCountsDown(terminating, from: 17, to: 17, then: .change(2), "The 72 to Rajská")
// The 72 goes on past Autobusová stanica, whose board lists it.
let continuing = replayBoards(sameStopChanges, late: 60, from: "07:58", to: "08:20")
assertCountsDown(continuing, from: 15, to: 15, then: .change(1), "The 72 to Autobusová stanica")
print("PASS: boards that list a vehicle until it leaves count down every stop and alert to get off once")

// From 08:05 no board lists the 72: once its next stop is 3 minutes overdue, it counts by the timetable, so the
// alert to get off comes when the timetable alone would give it.
for (journey, alighting, alertsAt, end, then) in [
    (walkChange, 17, "08:20", "08:24", TripProgress.Phase.change(2)),
    (sameStopChanges, 15, "08:17", "08:20", .change(1)),
] {
    let unlisted = replayBoards(journey, late: 0, from: "07:58", to: end, unlistedFrom: "08:05")
    let rides = unlisted.steps.filter { $0.progress.phase == .ride(0) }
    let counts = rides.compactMap(\.progress.stopsLeft)
    let alertTimes = unlisted.steps.indices.filter { unlisted.steps[$0].alert?.key == "off-0" }
        .map { local("07:58") + TimeInterval($0 * 10) }
    assert(counts.last == 1 && zip(counts, counts.dropFirst()).allSatisfy { $0 >= $1 }
           && rides.last?.progress.nextStop == alighting && unlisted.steps.last?.progress.phase == then,
           "The unlisted 72 counts down to the alighting stop: \(counts)")
    assert(alertTimes == [local(alertsAt)] && unlisted.alerts.first { $0.key == "off-0" }?.title
           == "Get off at the next stop", "The unlisted 72 alerts to get off at \(alertsAt): \(alertTimes)")
}
print("PASS: a vehicle the boards stop listing counts by the timetable and alerts to get off on time")

// Relaunch: the live data is saved with the journey and the trip goes on where the vehicle got to.
let beforeRelaunch = replayBoards(walkChange, late: 60, from: "07:58", to: "08:05")
let saved = try JSONDecoder().decode(TripLiveData.self, from: JSONEncoder().encode(beforeRelaunch.live))
assert(saved == beforeRelaunch.live && saved.passedStops == [0: 4] && saved.busIDs[0] == "1:0"
       && saved.delays[0] == 60, "Saved live data: \(saved)")
let relaunched = replayBoards(walkChange, late: 60, from: "08:12", to: "08:24", live: saved,
                              alerted: beforeRelaunch.steps.last!.state.alerted)
assert(relaunched.steps[0].progress.stopsLeft == 7, "Catches up at once: \(relaunched.steps[0].progress)")
assertCountsDown(relaunched, from: 7, to: 17, then: .change(2), "The relaunched 72")
let lateLastLeg = TripLiveData(delays: [2: 120])
let restoredDelays = try JSONDecoder().decode(TripLiveData.self, from: JSONEncoder().encode(lateLastLeg)).delays
assert(at("08:34").progress.phase == .arrived && at("08:34", live: restoredDelays).progress.phase == .ride(2),
       "The saved live delay keeps a late 31 riding after a relaunch")
assert(!tripCanEnd(at: local("08:34"), arrival: local("08:33"), awaitsLiveData: true)
       && tripCanEnd(at: local("08:43"), arrival: local("08:33"), awaitsLiveData: true)
       && tripCanEnd(at: local("08:34"), arrival: local("08:33"), awaitsLiveData: false),
       "After a relaunch, arrival on saved delays ends the trip only with live data or 10 minutes later")
// Saved on time, the 72 to Autobusová stanica runs 10 minutes late. At 08:25 the saved delay has it arrived, so the
// app asks the alighting stop's board, which first answers empty, then lists the 72 having left Novohradská.
var lateRide = sameStopChanges
lateRide.parts = [sameStopChanges.parts![0]]
let lateLeg = lateRide.parts![0]
var stale = TripLiveData(delays: [0: 0])
let alighting = lateRide.trackerTargets(for: TripProgress(phase: .ride(0)))
assert(lateRide.progress(at: local("08:25"), delays: lateRide.delays(live: stale.delays)).phase == .arrived
       && alighting == [TripTrackerTarget(part: 0, stop: 15)], "The relaunch asks Autobusová stanica: \(alighting)")
stale.receive(nil, at: alighting[0], of: lateRide, now: local("08:25"))
assert(stale.passedStops.isEmpty, "An empty board tells no position: \(stale.passedStops)")
stale.receive(row(lateLeg, lastStop: lateLeg.legStops[13].name, leaves: lateLeg.legStops[15].time + 600, late: 600),
              at: alighting[0], of: lateRide, now: local("08:25:05"))
let resumed = lateRide.update(
    at: local("08:25:05"), delays: lateRide.delays(live: stale.delays), passedStops: stale.passedStops
)
assert(resumed.state.title == "Get off in 2 stops" && resumed.alert == nil,
       "The late 72 resumes 2 stops before Autobusová stanica, no alert: \(resumed.state.title)")
print("PASS: live data survives a relaunch and the trip does not end early on stale delays")

// Background mode: the table's 10 s timer finds no table activity in the background and asks to stop.
assert(!backgroundModeCanStop(tableActivities: 0, followsTrip: true), "A trip keeps background mode")
assert(!backgroundModeCanStop(tableActivities: 1, followsTrip: false), "A table activity keeps background mode")
assert(backgroundModeCanStop(tableActivities: 0, followsTrip: false), "Stop once neither runs")
print("PASS: background mode stops only once no table or trip activity runs")
// The traveller's location: fixes placed from the legs' own stops, so the checks follow the fixture's coordinates.
let hronska = leg72[0].gps!
let rajska = leg72[17].gps!
let kollarovo = walkChange.parts![2].startStopGps!
/// `gps` moved `east` and `north` metres.
func moved(_ gps: StopGps, east: Double = 0, north: Double = 0) -> StopGps {
    StopGps(lon: gps.lon + east / (111_195 * cos(gps.lat * .pi / 180)), lat: gps.lat + north / 111_195)
}
/// `fraction` of the way from `leg`'s stop `stop` to the next one (past it above 1), `left` metres left of that line.
func onLine(_ stop: Int, _ fraction: Double = 0, left: Double = 0, of leg: [PartStop] = leg72) -> StopGps {
    let a = leg[stop].gps!
    let step = leg[stop + 1].gps!.meters(from: a)
    let length = hypot(step.x, step.y)
    return moved(a, east: fraction * step.x - left * step.y / length, north: fraction * step.y + left * step.x / length)
}
func fix(_ gps: StopGps, accuracy: Double = 10) -> TripFix { TripFix(gps: gps, accuracy: accuracy) }

/// One 15 s refresh of TripLiveActivityController: the location is checked against where the boards and the timetable
/// have the vehicle, then the step counts from the boards or the location, whichever got further.
func tick(
    _ journey: Journey, _ live: inout TripLiveData, _ fix: TripFix, at now: Date, alerted: Set<String> = [],
    found: [Journey]? = nil
) -> TripUpdate {
    let missed = live.locate(fix, on: journey, found: found, now: now)
    return journey.update(
        at: now, delays: journey.delays(live: live.delays), passedStops: live.positions, alerted: alerted, fix: fix,
        missed: missed
    )
}

/// Replays the traveller at `place(now)` every 15 s from `start` through `end`; `missedAt` is when the location first
/// found them off the ride.
func follow(
    _ journey: Journey = walkChange, from start: String, to end: String, live: TripLiveData = TripLiveData(),
    _ place: (Date) -> StopGps
) -> (steps: [TripUpdate], alerts: [String], live: TripLiveData, missedAt: Date?) {
    var live = live
    var alerted = Set<String>()
    var steps = [TripUpdate]()
    var alerts = [String]()
    var missedAt: Date?
    var now = local(start)
    while now <= local(end) {
        let update = tick(journey, &live, fix(place(now)), at: now, alerted: alerted)
        if let alert = update.alert { alerts.append(alert.key) }
        alerted = update.state.alerted
        if missedAt == nil, live.missed != nil { missedAt = now }
        steps.append(update)
        now += 15
    }
    return (steps, alerts, live, missedAt)
}

// Walking: the distance to the platform, the change stop or the destination while further than the location tells.
let rad = Double.pi / 180
let haversine = 2 * 6_371_008.8 * asin(sqrt(pow(sin((rajska.lat - hronska.lat) * rad / 2), 2)
    + cos(hronska.lat * rad) * cos(rajska.lat * rad) * pow(sin((rajska.lon - hronska.lon) * rad / 2), 2)))
assert(abs(hronska.distance(to: rajska) - haversine) < haversine / 500,
       "Planar metres match the great circle across the city: \(hronska.distance(to: rajska)) vs \(haversine)")
assert(at("07:56", fix: fix(hronska)).state == waiting.state, "At the platform: the board step as without a location")
assert(at("07:56", fix: fix(moved(hronska, north: 45))).state.title == "Board at Hronská"
       && at("07:56", fix: fix(moved(hronska, north: 90), accuracy: 100)).state.title == "Board at Hronská",
       "Within 50 m or the location's accuracy counts as at the platform")
let toHronska = at("07:50", fix: fix(moved(hronska, east: 354)))
assert(toHronska.state.title == "Walk to Hronská"
       && toHronska.state.detail == "350 m to platform A · leaves in 10 min"
       && toHronska.state.warning == .tightChange && toHronska.alert == nil, "Walk to the platform: \(toHronska.state)")
let leavesAt = "leaves at \(timeStringFromDate(local("08:00")))"
let distances = [(80.0, "80 m"), (346, "350 m"), (944, "940 m"), (949, "950 m"), (951, "1.0 km"), (1_234, "1.2 km")]
for (meters, text) in distances {
    let detail = at("06:50", fix: fix(moved(hronska, north: meters))).state.detail
    assert(detail == "\(text) to platform A · \(leavesAt)", "\(meters) m: \(detail)")
}
let toPlatform = at("08:25", fix: fix(moved(kollarovo, north: 200)))
assert(toPlatform.state.title == "Walk to platform D"
       && toPlatform.state.detail == "200 m to Kollárovo nám. · 31 leaves in 6 min"
       && toPlatform.state.warning == .tightChange, "Walking to the change: \(toPlatform.state)")
let atPlatform = at("08:25", fix: fix(kollarovo))
assert(atPlatform.state.title == "Wait at platform D"
       && atPlatform.state.detail == "Kollárovo nám. · 31 leaves in 6 min",
       "At the change platform: \(atPlatform.state)")
let station = sameStopChanges.parts![1].startStopGps!
let backToStation = at("08:19", sameStopChanges, fix: fix(moved(station, east: -100)))
assert(backToStation.state.title == "Walk to platform A" && backToStation.state.detail == "100 m · 42 leaves in 2 min"
       && at("08:19", sameStopChanges, fix: fix(station)).state == atStation.state,
       "A same-stop change walks only when the location is away: \(backToStation.state)")
let destination = finalWalk.parts![1].endStopGps!
let farFromDestination = at("08:25", finalWalk, fix: fix(moved(destination, north: -1_234)))
assert(farFromDestination.state.title == "Walk to Kollárovo nám."
       && farFromDestination.state.detail == "1.2 km · arrive in 6 min"
       && at("08:25", finalWalk, fix: fix(destination)).state == walking.state,
       "The final walk: \(farFromDestination.state)")
var unplacedChange = walkChange
unplacedChange.parts![2].startStopGps = nil
assert(at("08:25", unplacedChange, fix: fix(rajska)).state.title == "Walk to platform D",
       "A change stop without a position is not where the traveller waits")
print("PASS: walking guidance to the platform, the change and the destination by the location")

// May miss: the walk at 1 m/s takes longer than the vehicle has left.
let hurry = at("07:56", fix: fix(moved(hronska, east: 600)))
assert(hurry.state.warning == .mayMiss && hurry.alert == TripAlert(
    key: "hurry-0", title: "You may miss 72", body: "600 m to platform A · leaves in 4 min"
), "600 m in 4 min: \(hurry.state), \(String(describing: hurry.alert))")
let stillFar = at("07:56:15", alerted: hurry.state.alerted, fix: fix(moved(hronska, east: 590)))
assert(stillFar.state.warning == .mayMiss && stillFar.alert == nil, "The hurry alert fires once")
let near = at("07:56", fix: fix(moved(hronska, east: 100)))
assert(near.state.warning == .tightChange && near.alert == nil, "100 m in 4 min leaves time: \(near.state)")
let both = at("07:56", live: [0: 63], fix: fix(moved(hronska, east: 600)))
assert(both.state.warning == .likelyMissedChange && both.alert?.key == "missed-2",
       "A likely missed change outranks the walk: \(both.state)")
let changeHurry = at("08:25", fix: fix(rajska))
assert(changeHurry.state.title == "Walk to platform D"
       && changeHurry.state.detail == "620 m to Kollárovo nám. · 31 leaves in 6 min"
       && changeHurry.state.warning == .mayMiss && changeHurry.alert?.key == "hurry-2"
       && changeHurry.alert?.title == "You may miss 31", "Rajská to Kollárovo nám. in 6 min: \(changeHurry.state)")
assert(at("08:25:15", alerted: changeHurry.state.alerted, fix: fix(rajska)).alert?.key == "change-2",
       "Then the change alert")
// The change starts at the 72's whole-minute arrival, when it may still be a stop before Rajská: the walk counts from
// the location only a minute later, not from the moving vehicle.
let onBoard = fix(onLine(16, 1 - 300 / leg72[16].gps!.distance(to: rajska)))
let arriving = at("08:21:05", fix: onBoard)
assert(arriving.progress.phase == .change(2) && arriving.state == at("08:21:05").state
       && arriving.state.warning != .mayMiss && arriving.alert?.key == "change-2",
       "On the 72 300 m before Rajská as the change starts: as without a location: \(arriving.state)")
assert(at("08:22", fix: onBoard).state.warning == .mayMiss, "Still there a minute later, the location counts")
let lateConnection = at("08:25", live: [2: 300], fix: fix(rajska))
assert(lateConnection.state.warning == nil && lateConnection.state.detail.hasSuffix("31 leaves in 11 min")
       && lateConnection.alert?.key == "change-2", "A 31 5 minutes late leaves time: \(lateConnection.state)")
print("PASS: a walk longer than the time left warns once that the vehicle may leave first")

// Riding: the location counts the stops reached, but the vehicle it is checked against stays the boards' one.
var rideLive = TripLiveData()
let ahead = tick(walkChange, &rideLive, fix(onLine(5, 0.5)), at: local("08:04:30"))
assert(at("08:04:30").progress.nextStop == 5 && rideLive.passedStops.isEmpty && rideLive.located == [0: 5]
       && rideLive.boarded == [0] && rideLive.offRide.isEmpty, "Between Ríbezľová and Ondrejovova: \(rideLive)")
assert(ahead.progress.nextStop == 6 && ahead.progress.stopsLeft == 12 && ahead.state.title == "Get off in 12 stops",
       "The location has Ondrejovova next though the timetable and boards still have Ríbezľová: \(ahead.progress)")
let stray = tick(walkChange, &rideLive, fix(onLine(10)), at: local("08:04:45"))
assert(rideLive.located == [0: 10] && stray.progress.nextStop == 11 && stray.progress.stopsLeft == 7,
       "At Pažítková, Pažítková counts as reached: \(stray.progress)")
_ = tick(walkChange, &rideLive, fix(onLine(5, 0.5)), at: local("08:05"))
assert(rideLive.offRide.isEmpty && rideLive.located == [0: 10] && rideLive.passedStops.isEmpty,
       "Back near Ríbezľová still rides the vehicle the timetable has there, and the count does not go back")
var endLive = TripLiveData()
let getOff = tick(walkChange, &endLive, fix(rajska), at: local("08:20"))
assert(endLive.located == [0: 17] && getOff.progress.stopsLeft == 0 && getOff.state.title == "Get off now"
       && getOff.alert?.key == "off-0" && at("08:20").progress.stopsLeft == 1,
       "At Rajská before the timetable gets there: \(getOff.state)")
print("PASS: the location counts the stops reached without moving the vehicle it is checked against")

// Missed boarding: the traveller stays at Hronská while the 72 leaves.
func vehicleStop(_ time: String, live: [Int: Int]) -> Double {
    walkChange.progress(at: local(time), delays: walkChange.delays(live: live)).fraction! * 17
}
let minuteLate = TripLiveData(delays: [0: 60])
assert(vehicleStop("08:01:45", live: minuteLate.delays) < 1 && vehicleStop("08:02", live: minuteLate.delays) > 1,
       "The 72 a minute late is a stop past Hronská from 08:02")
// A minute late, the 72 also makes the change to the 31 likely missed.
// It is checked against where the 72 was a minute before, as whole-minute times may run that far ahead.
let stayed = follow(from: "08:00", to: "08:04", live: minuteLate) { _ in hronska }
// The missed alert waits for the search, which this replay does not run.
assert(stayed.missedAt == local("08:03:45") && stayed.live.boarded.isEmpty && stayed.alerts == ["missed-2"]
       && stayed.steps.last!.state.title == "Missed 72",
       "Missed 45 s after the vehicle is a stop ahead: \(String(describing: stayed.missedAt)), \(stayed.alerts)")
var afterMissed = stayed.live
afterMissed.receive(fix(onLine(10)), on: walkChange, progress: TripProgress(phase: .ride(0), fraction: 0.5),
                    now: local("08:03"))
assert(afterMissed == stayed.live, "Once missed, the location is no longer checked")
let unreported = follow(from: "08:00", to: "08:04:45") { _ in hronska }
assert(unreported.missedAt == nil && unreported.live.offRide.isEmpty, "Without a live delay the 72 may only be late")
assert(follow(from: "08:00", to: "08:06") { _ in hronska }.missedAt == local("08:05:45"),
       "Missed 45 s after 5 minutes past its departure")
let liveOnTime = TripLiveData(delays: [0: 0])
// Riding a 72 running late with no live delay: behind the timetable's vehicle, but moving along its line.
for lateness in [90.0, 120, 180] {
    let late = follow(from: "08:03:30", to: "08:15") { now in
        let stop = walkChange.progress(at: now - lateness, delays: [:]).fraction! * 17
        return onLine(Int(stop), stop - Double(Int(stop)))
    }
    assert(late.missedAt == nil && late.live.boarded == [0], "On a 72 \(Int(lateness)) s late without live data")
}
// Riding up to a minute behind the whole-minute timetable, the 72 on time on the boards: still on board.
for lag in [20.0, 45, 59] {
    let behindTimetable = follow(from: "08:01", to: "08:15", live: liveOnTime) { now in
        let stop = walkChange.progress(at: now - lag, delays: [0: 0]).fraction! * 17
        return onLine(Int(stop), stop - Double(Int(stop)))
    }
    assert(behindTimetable.missedAt == nil, "On the 72 \(Int(lag)) s behind its timetable")
}
// A leg whose stops did not load has only its boarding and alighting stops: 500 m behind counts as missed too.
var stopless = walkChange
stopless.parts![0].stops = nil
let leftAtStop = follow(stopless, from: "08:00", to: "08:06", live: liveOnTime) { _ in hronska }
assert(leftAtStop.missedAt.map { $0 < local("08:05") } == true,
       "Missed on a stopless leg: \(leftAtStop.missedAt as Any)")
print("PASS: missed boarding 45 s after the vehicle is a stop ahead, or 5 min after it was due without a live delay")

// Off the route after riding, or got off near the alighting stop.
let offRoute = follow(from: "08:01:30", to: "08:03", live: liveOnTime) { now in
    now < local("08:02") ? onLine(1, 0.5) : onLine(2, left: 1_000)
}
assert(offRoute.missedAt == local("08:02:45") && offRoute.live.boarded == [0]
       && offRoute.steps.last!.state.title == "Off the route" && offRoute.alerts.isEmpty,
       "Rode past Toryská, then 1 km off the line for 45 s: \(String(describing: offRoute.missedAt))")
let lateBoard = TripLiveData(delays: [0: 120])
let lastLength = leg72[16].gps!.distance(to: rajska)
let gotOff = follow(from: "08:20", to: "08:22:45", live: lateBoard) { _ in onLine(16, 1 + 290 / lastLength) }
assert(gotOff.missedAt == nil && gotOff.live.located == [0: 17]
       && gotOff.steps.allSatisfy { $0.state.title == "Get off now" }, "290 m past Rajská, off the line: got off")
let wandered = follow(from: "08:20", to: "08:21", live: lateBoard) { _ in onLine(16, 1 + 400 / lastLength) }
// Once at Rajská the ride is done, though the delay still has it running: walking off is no miss.
let walkedOn = follow(from: "08:20", to: "08:22:45", live: lateBoard) { now in
    now < local("08:20:30") ? rajska : moved(rajska, north: 1_000)
}
assert(walkedOn.missedAt == nil, "Walked on from Rajská")
assert(wandered.missedAt == local("08:20:45"), "400 m past Rajská is too far from it")
print("PASS: off the route after riding, but not when off the line near the alighting stop")

// The missed step: the search, then the soonest other connection; alerted once the search answered.
let lostAt = at("08:02", missed: TripMissed(part: 0, boarded: false))
assert(lostAt.state == TripActivityAttributes.ContentState(
    step: .missed, line: "72", title: "Missed 72", detail: "Finding other connections…", time: local("08:00"),
    compact: "Missed", minimal: "!"
) && lostAt.alert == nil, "Missed while searching: \(lostAt.state)")
let noneFound = at("08:02:15", alerted: lostAt.state.alerted,
                   missed: TripMissed(part: 0, boarded: false, alternatives: TripAlternatives()))
assert(noneFound.state.detail == "No other connections found"
       && noneFound.alert == TripAlert(key: "lost-0", title: "Missed 72", body: "No other connections found"),
       "Nothing found: \(String(describing: noneFound.alert))")
assert(at("08:02:30", alerted: noneFound.state.alerted,
          missed: TripMissed(part: 0, boarded: false, alternatives: TripAlternatives())).alert == nil, "No repeat")
/// This trip `minutes` later, on `line` instead of the 72, which leaves `delay` seconds late at the search.
func later(_ minutes: Double, line: String = "72", delay: Int? = nil) -> Journey {
    var journey = walkChange
    journey.id = "\(line) \(Int(minutes))\(delay.map { " +\($0) s" } ?? "")"
    journey.parts = walkChange.parts!.map { part in
        var part = part
        part.startDeparture += minutes * 60
        part.endArrival += minutes * 60
        part.stops = part.stops?.map { stop in
            var stop = stop
            stop.time += minutes * 60
            return stop
        }
        return part
    }
    journey.parts![0].routeShortName = line
    journey.parts![0].delaySeconds = delay
    return journey
}
let found = [
    later(-5), later(10), later(20), later(30), later(15, line: "83"), later(5, line: "83"), later(25, line: "83"),
    later(20, line: "83"), later(-1, line: "83", delay: 240), later(-1, line: "83", delay: 0),
]
let alternatives = walkChange.alternatives(found, missed: 0, at: local("08:02"))
assert(walkChange.lines() == ["72", "31"] && walkChange.lines(from: 1) == ["31"], "Ride lines")
assert(alternatives.sameRoute.map(\.id) == ["72 10", "72 20"]
       && alternatives.others.map(\.id) == ["83 -1 +240 s", "83 5", "83 15"]
       && alternatives.best?.id == "83 -1 +240 s",
       "Departed ones dropped, two on the 72 and 31, three others by arrival: \(alternatives.sameRoute.map(\.id)), "
       + "\(alternatives.others.map(\.id))")
var lostLive = stayed.live
let offered = tick(walkChange, &lostLive, fix(hronska), at: local("08:02:50"), alerted: ["lost-0"], found: found)
assert(offered.state.step == .missed && offered.state.line == "83" && offered.state.time == local("08:03")
       && offered.state.detail == "Take 83 at \(timeStringFromDate(local("08:03"))) from Hronská A"
       && offered.alert == nil, "The soonest arrival, its search delay included: \(offered.state)")
var firstLive = stayed.live
let firstOffer = tick(walkChange, &firstLive, fix(hronska), at: local("08:02:50"), found: found)
assert(firstOffer.alert == TripAlert(key: "lost-0", title: "Missed 72", body: offered.state.detail),
       "The alert says what to take: \(String(describing: firstOffer.alert))")
print("PASS: the missed step offers the soonest other connection and alerts once")

// Kept rides and relaunches.
let keptLive = TripLiveData(delays: [0: 60], kept: [0])
let keptRide = follow(from: "08:00", to: "08:06", live: keptLive) { _ in hronska }
assert(keptRide.missedAt == nil && keptRide.live == keptLive && keptRide.steps.last!.state.step == .ride,
       "A ride kept after a miss is no longer checked")
let locatedLive = TripLiveData(
    passedStops: [0: 7], located: [0: 5, 2: 1], boarded: [0], offRide: [2: local("08:31:30")], missed: 2, kept: [0]
)
let reloaded = try JSONDecoder().decode(TripLiveData.self, from: JSONEncoder().encode(locatedLive))
assert(reloaded == locatedLive && reloaded.positions == [0: 7, 2: 1], "Location data survives a relaunch: \(reloaded)")
print("PASS: kept rides are no longer checked and the location data survives a relaunch")
SWIFT
