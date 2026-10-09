#!/bin/bash
set -euo pipefail

transi_root="$(cd "$(dirname "$0")/.." && pwd)"
transi_test_cache="$(mktemp -d "${TMPDIR:-/tmp}/transi-trip-detail-check.XXXXXX")"
trap 'rm -r -- "$transi_test_cache"' EXIT

# Compile the production trip models, API decoding and leg helpers without the app's services, then
# replay real R-API, B-API and I-API responses (scripts/fixtures/trip-detail.json) through them.
sed -n '/^\/\/ Swift regression checks/,/^SWIFT$/ { /^SWIFT$/!p; }' "$0" > "$transi_test_cache/main.swift"
{
    printf '%s\n' 'import Foundation' 'class TripPlannerController {}'
    awk '/^extension Part \{/,/^}/' "$transi_root/Shared/Controllers/PartLiveTracker.swift"
    awk '/^enum JourneyStep/,/^}/
        /^extension Journey \{/,/^}/
        /^extension Part \{/,/^}/' "$transi_root/Transi/Trip Planner/TripDetailModel.swift"
} > "$transi_test_cache/stubs.swift"
shared="$transi_root/Shared"
xcrun swiftc -module-cache-path "$transi_test_cache" -target "$(uname -m)-apple-macosx14.0" \
    -o "$transi_test_cache/check" \
    "$shared/Models/Trip.swift" "$shared/Models/StopGps.swift" "$shared/Models/ApiModels.swift" \
    "$shared/Models/AnyCodable.swift" "$shared/Models/Stops.swift" "$shared/Models/Table.swift" \
    "$shared/Util/DateTime.swift" "$shared/Extensions/Date.swift" "$shared/Extensions/String.swift" \
    "$shared/Extensions/CLLocationCoordinate2D.swift" \
    "$shared/Controllers/TripPlannerController+Mapping.swift" \
    "$transi_test_cache/stubs.swift" "$transi_test_cache/main.swift"
"$transi_test_cache/check" "$transi_root/scripts/fixtures/trip-detail.json"
# Again on a device far from Bratislava: the API's Bratislava times must not depend on it, and day names follow it.
TZ=Asia/Tokyo "$transi_test_cache/check" "$transi_root/scripts/fixtures/trip-detail.json"
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

// Same key strategy as the app's fetch decoder.
let apiDecoder = JSONDecoder()
apiDecoder.keyDecodingStrategy = .convertFromSnakeCase
let fixture = try apiDecoder.decode(
    Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
)
let localFormatter = DateFormatter()
localFormatter.dateFormat = "yyyy-MM-dd HH:mm"
localFormatter.timeZone = TimeZone(identifier: "Europe/Bratislava")
func local(_ time: String) -> Date { localFormatter.date(from: time)! }
func utc(_ time: String) -> Date { dateFromUtc(time) }
let planner = TripPlannerController()

// R-API: ids decode under convertFromSnakeCase and survive the mapping.
let rJourneys = planner.mapRApiToJourneys(fixture.raptor.journey ?? [])
let bus72 = rJourneys[0].parts![0]
assert(rJourneys.map(\.ticketId) == [806, 804], "Journey ticket ids")
assert(bus72.tripId == 13517 && bus72.startStopId == 900 && bus72.endStopId == 945
       && bus72.startStationId == 1386 && bus72.endStationId == 1404, "R-API trip, stop and station ids")
assert(bus72.startStopGps == StopGps(lon: 17.208740234375, lat: 48.1357383728027)
       && bus72.endStopGps != nil && bus72.delaySeconds == nil && bus72.stops == nil, "R-API platform GPS")
assert(rJourneys[1].parts![0].delaySeconds == 63, "Search-time delay of a running vehicle")
assert(rJourneys[0].parts![1].routeType == 64 && rJourneys[0].parts![1].tripId == nil, "Walks have no trip")
print("PASS: R-API ticket, trip, stop, station, GPS and delay fields")

// B-API: slice line 72 (trip 13517) from Hronská to Rajská.
let leg72 = fixture.trip.partStops(for: bus72, stops: fixture.stops)!
let rajska = fixture.stops.first { $0.stationId == 1404 }!
assert(leg72.count == 18 && leg72.first?.name == "Hronská" && leg72.last?.name == "Rajská", "Leg slice")
assert(leg72.first?.time == bus72.startDeparture && leg72.last?.time == bus72.endArrival,
       "Bratislava minutes match the R-API UTC times")
assert(leg72.first?.stopId == 94 && leg72.last?.stopId == rajska.id,
       "imhd stop ids, falling back to the station when the platform letter is unknown")
assert(leg72.allSatisfy { $0.gps != nil && $0.platform != nil }, "Platform GPS and letters")
assert(leg72.zoneChanges == [ZoneChange(index: 4, from: "101", to: "100")], "Cintorín Vrakuňa enters zone 100")
assert(fixture.trip.partStops(for: Part(startDeparture: Date(), endArrival: Date()), stops: []) == nil,
       "Legs without B-API stop ids have nothing to slice")

func stopTime(_ id: Int, _ minutes: Int) -> BApiStopTime {
    BApiStopTime(stopId: id, stationId: nil, stopGps: nil, stopCode: "A", stopName: "S\(id)",
                 arrival: minutes, departure: minutes, zone: "100")
}
func leg(_ from: Int, _ to: Int, at time: String) -> Part {
    Part(startDeparture: local(time), endArrival: local(time), startStopId: from, endStopId: to)
}
// A loop line serves stop 1 twice.
let loop = BApiTrip(tripId: 1, tripDelay: nil,
                    stopTimes: [stopTime(1, 600), stopTime(2, 602), stopTime(3, 604), stopTime(1, 606), stopTime(4, 608)])
let loopCases: [(Part, [String]?)] = [
    (leg(3, 1, at: "2026-10-05 10:04"), ["S3", "S1"]),
    (leg(1, 4, at: "2026-10-05 10:00"), ["S1", "S2", "S3", "S1", "S4"]),
    (leg(1, 4, at: "2026-10-05 10:06"), ["S1", "S4"]),
    (leg(1, 2, at: "2026-10-05 10:06"), nil),
    (leg(4, 1, at: "2026-10-05 10:08"), nil),
]
for (part, expected) in loopCases {
    assert(loop.partStops(for: part, stops: [])?.map(\.name) == expected, "Loop leg \(expected ?? [])")
}
print("PASS: real leg slice, imhd ids, GPS and \(loopCases.count) loop-line slices")

// Minutes after midnight are Bratislava wall-clock times on the service day.
let calendar = Calendar.bratislava
let october5 = calendar.startOfDay(for: local("2026-10-05 12:00"))
assert(calendar.date(minutes: 480, after: october5) == utc("2026-10-05T06:00:00.000Z"), "08:00 CEST")
assert(calendar.date(minutes: 1450, after: october5) == utc("2026-10-05T22:10:00.000Z"), "1450 is 00:10 next day")
assert(calendar.date(minutes: 300, after: calendar.startOfDay(for: local("2026-10-25 12:00")))
       == utc("2026-10-25T04:00:00.000Z"), "05:00 CET on the day summer time ends")
let night = BApiTrip(tripId: 2, tripDelay: 30, stopTimes: [stopTime(7, 1430), stopTime(8, 1450), stopTime(9, 1455)])
assert(night.partStops(for: leg(7, 9, at: "2026-10-05 23:50"), stops: [])?.map(\.time)
       == [local("2026-10-05 23:50"), local("2026-10-06 00:10"), local("2026-10-06 00:15")], "Night trip from 23:50")
assert(night.partStops(for: leg(8, 9, at: "2026-10-06 00:10"), stops: [])?.map(\.time)
       == [local("2026-10-06 00:10"), local("2026-10-06 00:15")], "Boarding after midnight keeps the service day")
print("PASS: minutes to dates, past midnight and across the summer time change")

func zoned(_ zones: [String?]) -> [PartStop] { zones.map { PartStop(name: "", time: Date(), zone: $0) } }
assert(zoned(["100", "100"]).zoneChanges.isEmpty, "No border")
assert(zoned(["101", nil, "100", "100", "101"]).zoneChanges
       == [ZoneChange(index: 2, from: "101", to: "100"), ZoneChange(index: 4, from: "100", to: "101")],
       "Borders skip stops without a zone")
print("PASS: zone borders")

// I-API: full stop lists joined to the stops list.
let iJourney = planner.mapIApiToJourneys(fixture.cepo.journeys ?? [], stops: fixture.stops)[0]
let trolley72 = iJourney.parts![0]
assert(trolley72.lowFloor == true && trolley72.startStationId == 1386 && trolley72.endStationId != nil
       && trolley72.startStopGps != nil && trolley72.stops?.count == 16, "I-API part")
assert(trolley72.stops?.first == PartStop(
    name: "Hronská", platform: "A", time: local("2026-10-05 08:00"),
    gps: StopGps(lon: 17.208740234375, lat: 48.1357383728027), zone: "101", isRequestStop: true, stopId: 94
), "I-API stop")
assert(trolley72.stops?.last?.time == local("2026-10-05 08:18"), "I-API alighting time")
assert(trolley72.stops?.zoneChanges == [ZoneChange(index: 4, from: "101", to: "100")], "I-API zone border")
let kollarovo = iJourney.parts![2].stops![0]
assert(kollarovo.time == local("2026-10-05 08:31") && !kollarovo.isRequestStop, "Departure-only stop")
assert(iJourney.parts!.allSatisfy { $0.stops?.allSatisfy { $0.stopId != nil && $0.gps != nil } == true },
       "Every I-API stop resolves")
func firstStopId(_ stops: [Stop]) -> Int? {
    planner.mapIApiToJourneys(fixture.cepo.journeys ?? [], stops: stops)[0].parts![0].stops?.first?.stopId
}
assert(firstStopId(fixture.stops.map { var stop = $0; stop.name = "Renamed"; return stop }) == 94, "Stop pole join")
assert(firstStopId(fixture.stops.map { var stop = $0; stop.platformLabels = nil; return stop }) == 94, "Name fallback")
print("PASS: I-API stops with times, platforms, zones, request stops, GPS and imhd ids")

// 72 to Rajská, 10-minute walk, 31 leaves when the walk ends.
let walkChange = rJourneys[0]
assert(walkChange.transferBuffers() == [2: TransferBuffer(minutes: 0)], "Scheduled buffer after the walk")
assert(walkChange.transferBuffers()[2]!.isTight && !walkChange.transferBuffers()[2]!.isLikelyMissed, "Tight")
assert(walkChange.transferBuffers(delays: [2: 60])[2]!.isTight, "One spare minute is tight")
assert(!walkChange.transferBuffers(delays: [2: 120])[2]!.isTight, "Two spare minutes are not")
let late72 = walkChange.transferBuffers(delays: [0: 63])[2]!
assert(late72.minutes == -1 && late72.isLikelyMissed, "A 72 shown +1 min misses the 31 by 1 min")
let late31 = walkChange.transferBuffers(delays: [0: 63, 2: 120])[2]!
assert(late31.minutes == 1 && late31.isTight && !late31.isLikelyMissed, "A late 31 still waits")
// Delays count in the whole minutes the detail shows (nearest): 20 s reads "on time", 50 s "+1 min",
// 90 s "+2 min", so "on time" never sits next to "likely missed".
let shownDelayCases: [(seconds: Int, minutes: Int)] = [(20, 0), (29, 0), (30, -1), (50, -1), (90, -2), (-50, 1)]
for (seconds, minutes) in shownDelayCases {
    let buffer = walkChange.transferBuffers(delays: [0: seconds])[2]!
    assert(buffer.minutes == minutes && buffer.minutes == -delayMinutes(seconds), "\(seconds) s late 72")
    assert(buffer.isTight && buffer.isLikelyMissed == (minutes < 0), "\(seconds) s: likely missed only below 0")
}
// Same-stop changes without a walk part: 08:18 → 08:21 and 08:26:30 → 08:31.
assert(iJourney.transferBuffers() == [1: TransferBuffer(minutes: 3), 2: TransferBuffer(minutes: 4)], "No walk")
assert(iJourney.transferBuffers().values.allSatisfy { !$0.isTight }, "Roomy changes")
print("PASS: transfer buffers, tight and likely missed changes, \(shownDelayCases.count) delays as shown")

// Detail steps and summary.
assert(walkChange.steps == [.ride(0), .walk([1], to: 2), .ride(2)], "Walk between rides")
assert(walkChange.rideCount == 2 && walkChange.walkMinutes == 10 && walkChange.zoneNames.isEmpty,
       "R-API summary before the stops load")
var loaded = walkChange
loaded.parts![0].stops = leg72
assert(loaded.zoneNames == ["101", "100"], "Zone names from the loaded stops")
assert(iJourney.steps == [.ride(0), .change(to: 1), .ride(1), .change(to: 2), .ride(2)], "Same-stop changes")
assert(iJourney.rideCount == 3 && iJourney.walkMinutes == 0 && iJourney.zoneNames == ["101", "100"], "I-API summary")
// Durations count the clock minutes shown, which drop the seconds: 08:21:00 → 08:26:30 shows 08:21 – 08:26, 5 min.
assert(iJourney.parts!.map(\.minutes) == [18, 5, 2], "I-API leg minutes match their shown times")
let half = local("2026-10-05 16:30")
let minuteCases: [(from: TimeInterval, to: TimeInterval, minutes: Int)] = [
    (15, 645, 10), (45, 615, 10), (59, 60, 1), (0, 59, 0), (30, 30, 0),
]
for (from, to, minutes) in minuteCases {
    assert(minutesBetween(half + from, half + to) == minutes
           && timeDiffFromDates(half + from, half + to) == "\(minutes)",
           "16:30 +\(from) s → +\(to) s is \(minutes) min")
}
let noon = local("2026-10-05 12:00")
func walk(_ minutes: Int) -> Part {
    Part(startDeparture: noon, endArrival: noon + TimeInterval(minutes * 60), routeType: 64)
}
let ride = Part(startDeparture: noon, endArrival: noon, routeType: 3)
let stepCases: [([Part], [JourneyStep])] = [
    ([walk(4), ride, walk(2)], [.walk([0], to: 1), .ride(1), .walk([2], to: nil)]),
    ([ride, walk(1), walk(3), ride], [.ride(0), .walk([1, 2], to: 3), .ride(3)]),
    ([ride], [.ride(0)]),
    ([walk(7)], [.walk([0], to: nil)]),
    ([], []),
]
for (parts, expected) in stepCases {
    assert(Journey(id: "steps", parts: parts).steps == expected, "Steps \(expected)")
}
assert(Journey(id: "walks", parts: [walk(4), ride, walk(2)]).walkMinutes == 6, "Walk minutes add up")
print("PASS: \(stepCases.count + 2) step lists, the summary counts and \(minuteCases.count + 1) shown-minute durations")

// Persisted trips: older JSON without the new fields, and new fields round-trip (UserDefaults uses
// plain JSONEncoder/JSONDecoder).
let legacyJSON = Data("""
{"journey":[{"id":"r-legacy","zones":["1955","1953"],"parts":[
 {"startStopName":"Hronská","endStopName":"Rajská","startStopCode":"A","endStopCode":"A",
  "startDeparture":781336800,"endArrival":781338060,"routeType":50,"tripHeadsign":"Rajská","routeShortName":"72"},
 {"startStopName":"Rajská","endStopName":"Kollárovo nám.","startDeparture":781338060,"endArrival":781338660,
  "routeType":64}]}]}
""".utf8)
let legacy = try JSONDecoder().decode(Trip.self, from: legacyJSON).journey![0]
let legacyPart = legacy.parts![0]
assert(legacy.ticketId == nil && legacy.zones == ["1955", "1953"] && legacy.parts?.count == 2, "Legacy journey")
assert(legacyPart.routeShortName == "72" && legacyPart.startDeparture == Date(timeIntervalSinceReferenceDate: 781336800)
       && legacyPart.tripId == nil && legacyPart.startStopId == nil && legacyPart.startStationId == nil
       && legacyPart.startStopGps == nil && legacyPart.delaySeconds == nil && legacyPart.lowFloor == nil
       && legacyPart.stops == nil, "Legacy part")
var detailed = bus72
detailed.stops = leg72
detailed.delaySeconds = 63
let saved = Journey(id: "r-saved", parts: [detailed], zones: ["1955"], ticketId: 806)
let restored = try JSONDecoder().decode(Journey.self, from: JSONEncoder().encode(saved))
assert(restored.parts == saved.parts && restored.ticketId == 806, "New fields round-trip")
assert(Journey(id: "a", parts: [bus72], zones: nil) == saved, "Journey equality ignores stops and live data")
print("PASS: legacy saved trips decode and new fields round-trip")

// Live board matching at Hronská A (platform 240) for the 72 scheduled at 08:00.
func board(_ line: String, platform: Int = 240, at time: String, busID: String = "1:1", headsign: String = "Rajská")
    -> Connection
{
    var connection = Connection.example
    connection.id = "\(line) \(platform) \(time) \(busID) \(headsign)"
    connection.line = line
    connection.platform = platform
    connection.departureTimeCP = local("2026-10-05 \(time)").timeIntervalSince1970
    connection.busID = busID
    connection.headsign = headsign
    return connection
}
let scheduled = local("2026-10-05 08:00")
let matchCases: [(String, [Connection], Int?, String?, Connection?)] = [
    ("closest of two", [board("72", at: "08:05"), board("72", at: "08:02")], 240, nil, board("72", at: "08:02")),
    ("feeds 3 min apart", [board("72", at: "07:57")], 240, nil, board("72", at: "07:57")),
    ("over 3 min away", [board("72", at: "08:04")], 240, nil, nil),
    ("other line", [board("71", at: "08:00")], 240, nil, nil),
    ("other direction", [board("72", platform: 241, at: "08:00")], 240, nil, nil),
    ("regional row", [board("72", platform: -1, at: "08:01")], 240, nil, board("72", platform: -1, at: "08:01")),
    ("unknown platform", [board("72", platform: 241, at: "08:00")], nil, nil, board("72", platform: 241, at: "08:00")),
    ("headsign tiebreak", [board("72", at: "08:00", headsign: "Trnávka"), board("72", at: "08:00")], 240, nil,
     board("72", at: "08:00")),
    ("followed vehicle", [board("72", at: "08:00"), board("72", at: "08:02", busID: "1:7")], 240, "1:7",
     board("72", at: "08:02", busID: "1:7")),
    ("followed vehicle gone", [board("72", at: "08:00"), board("72", at: "08:01", busID: "1:9")], 240, "1:7", nil),
]
let part72 = Part(startDeparture: scheduled, endArrival: scheduled, routeType: 50, tripHeadsign: "Rajská",
                  routeShortName: "72")
for (name, connections, platform, busID, expected) in matchCases {
    let match = part72.liveConnection(in: connections, platform: platform, scheduled: scheduled, busID: busID)
    assert(match == expected, "\(name): got \(match?.id ?? "nil")")
}
print("PASS: \(matchCases.count) live board matching cases")

// Live window: from an hour before departure until the expected arrival (scheduled plus a known delay;
// running early never ends it sooner).
let liveLeg = Part(startDeparture: local("2026-10-05 08:00"), endArrival: local("2026-10-05 08:20"))
let liveCases: [(String, Int?, Bool)] = [
    ("06:59", nil, false), ("07:01", nil, true), ("08:10", nil, true), ("08:20", nil, false),
    ("06:59", 480, false), ("08:20", 480, true), ("08:25", 480, true), ("08:29", 480, false),
    ("08:19", -120, true), ("08:20", 0, false),
]
for (time, delay, expected) in liveCases {
    assert(liveLeg.isLive(at: local("2026-10-05 \(time)"), delaySeconds: delay) == expected,
           "Live at \(time), \(delay ?? 0) s late")
}
print("PASS: \(liveCases.count) live window cases")

// Train stops come with empty platform letters, which map to none, so no bare platform sign shows.
var emptyCodes = fixture.raptor.journey![0]
emptyCodes.parts![0].startStopCode = ""
emptyCodes.parts![0].endStopCode = ""
let noCodes = planner.mapRApiToJourneys([emptyCodes])[0].parts![0]
assert(noCodes.startStopCode == nil && noCodes.endStopCode == nil, "R-API empty stop codes")
let trainTrip = BApiTrip(tripId: 3, tripDelay: nil, stopTimes: [
    BApiStopTime(stopId: 1, stationId: nil, stopGps: nil, stopCode: "", stopName: "Bratislava-Nové Mesto",
                 arrival: 754, departure: 754, zone: "100"),
    BApiStopTime(stopId: 2, stationId: nil, stopGps: nil, stopCode: nil, stopName: "Svätý Jur",
                 arrival: 769, departure: 769, zone: "111"),
])
assert(trainTrip.partStops(for: leg(1, 2, at: "2026-10-05 12:34"), stops: [])?.map(\.platform) == [nil, nil],
       "B-API empty stop codes")
let fixtureJSON = try String(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]), encoding: .utf8)
let emptyLabels = try apiDecoder.decode(
    Fixture.self, from: Data(fixtureJSON.replacingOccurrences(of: #""label":"A""#, with: #""label":"""#).utf8)
)
let emptyLabelParts = planner.mapIApiToJourneys(emptyLabels.cepo.journeys ?? [], stops: fixture.stops)[0].parts!
assert(emptyLabelParts[0].startStopCode == nil && emptyLabelParts[0].stops?.first?.platform == nil
       && emptyLabelParts[0].stops?.first?.stopId == 94, "I-API empty labels, still joined to the stops list")
assert(emptyLabelParts.allSatisfy { part in
    part.startStopCode != "" && part.endStopCode != "" && (part.stops ?? []).allSatisfy { $0.platform != "" }
}, "No empty I-API platform letters")
assert(String?.none.nonEmpty == nil && String?.some("").nonEmpty == nil && String?.some("B").nonEmpty == "B",
       "Empty platforms are none")
print("PASS: empty R-API, B-API and I-API platform letters map to none")

// A known delay moves a vehicle's times as the trip Live Activity shows them.
let scheduledBoarding = local("2026-10-05 12:19")
assert(scheduledBoarding.expected(delaySeconds: nil) == scheduledBoarding, "No delay")
assert(scheduledBoarding.expected(delaySeconds: 180) == local("2026-10-05 12:22"), "3 min late")
assert(scheduledBoarding.expected(delaySeconds: -120) == local("2026-10-05 12:17"), "2 min early")
// Moved by the whole minutes the delay reads as, so a time is struck through exactly when the delay text says
// "+1 min" or more, and agrees with the change buffers.
let expectedCases: [(seconds: Int, time: String)] = [
    (20, "12:19"), (29, "12:19"), (30, "12:20"), (50, "12:20"), (90, "12:21"), (-50, "12:18"),
]
for (seconds, time) in expectedCases {
    let expected = scheduledBoarding.expected(delaySeconds: seconds)
    assert(expected == local("2026-10-05 \(time)"), "\(seconds) s late shows \(time)")
    assert(expected == scheduledBoarding + TimeInterval(delayMinutes(seconds) * 60), "\(seconds) s as its delay text")
    assert((timeStringFromDate(expected) != timeStringFromDate(scheduledBoarding)) == (delayMinutes(seconds) != 0),
           "\(seconds) s: the scheduled time is struck through only beside a delay in minutes")
}
print("PASS: expected times, \(expectedCases.count) delays in whole minutes")

// Journeys on another day than today on the device's clock say which, beside a time shown on that clock.
let device = Calendar.current
let laterToday = device.startOfDay(for: Date()).addingTimeInterval(60)
let tomorrow = device.date(byAdding: .day, value: 1, to: laterToday)!
let yesterday = device.date(byAdding: .day, value: -1, to: laterToday)!
let inThreeDays = device.date(byAdding: .day, value: 3, to: laterToday)!
assert(dayStringUnlessToday(laterToday) == nil, "Today")
for day in [tomorrow, yesterday] {
    assert(dayStringUnlessToday(day).map { $0.rangeOfCharacter(from: .decimalDigits) == nil } == true,
           "Next to today, in words: \(dayStringUnlessToday(day) ?? "nil")")
}
assert(dayStringUnlessToday(tomorrow) != dayStringUnlessToday(yesterday), "Tomorrow isn't yesterday")
assert(dayStringUnlessToday(inThreeDays).map { $0.rangeOfCharacter(from: .decimalDigits) != nil } == true,
       "In three days, a date: \(dayStringUnlessToday(inThreeDays) ?? "nil")")
assert(dayStringUnlessToday(inThreeDays)?.contains(String(device.component(.year, from: inThreeDays))) == false,
       "A short date, without the year")
// Just after and before midnight on the device, which the second run puts 7 hours ahead of Bratislava.
let afterMidnight = device.date(byAdding: .minute, value: 29, to: tomorrow)!
let beforeMidnight = device.date(byAdding: .minute, value: -31, to: tomorrow)!
assert(dayStringUnlessToday(afterMidnight) == dayStringUnlessToday(tomorrow) && dayStringUnlessToday(afterMidnight) != nil,
       "\(timeStringFromDate(afterMidnight)) is tomorrow: \(dayStringUnlessToday(afterMidnight) ?? "nil")")
assert(dayStringUnlessToday(beforeMidnight) == nil,
       "\(timeStringFromDate(beforeMidnight)) is today: \(dayStringUnlessToday(beforeMidnight) ?? "nil")")
print("PASS: day names for journeys not today, in \(TimeZone.current.identifier)")

// Ride shapes: each known segment between two stops in place of the straight line, straight where unknown.
let shapeStops = [17.1, 17.11, 17.12, 17.13].map { StopGps(lon: $0, lat: 48.1) }
func point(_ gps: StopGps) -> [Double] { [gps.lat, gps.lon] }
let bend = [48.11, 17.115], curve = [48.105, 17.125]
let nearStop1 = [48.1001, 17.1101]
let shapeJSON = Data(#"{"segments":[null,[[48.1,17.11],[48.11,17.115],[48.1,17.12]],null]}"#.utf8)
let decodedShape = try apiDecoder.decode(TimetableShape.self, from: shapeJSON)
let shapeCases: [(String, [[[Double]]?], [StopGps])] = [
    ("all unknown", [nil, nil, nil], shapeStops),
    ("too few segments", [[point(shapeStops[0]), bend, point(shapeStops[1])], nil], shapeStops),
    ("too many segments", [nil, nil, nil, nil], shapeStops),
    ("one point or malformed points", [[bend], [[48.1], [17.1, 48.1, 3]], nil], shapeStops),
    ("known between unknown, sharing the stops", decodedShape.segments,
     [shapeStops[0], shapeStops[1], StopGps(lon: 17.115, lat: 48.11), shapeStops[2], shapeStops[3]]),
    ("ending near the stops", [[point(shapeStops[0]), nearStop1], [nearStop1, curve, point(shapeStops[2])], nil],
     [shapeStops[0], StopGps(lon: 17.1101, lat: 48.1001), StopGps(lon: 17.125, lat: 48.105), shapeStops[2],
      shapeStops[3]]),
    ("unknown after a segment ending off its stop", [[point(shapeStops[0]), nearStop1], nil, nil],
     [shapeStops[0], StopGps(lon: 17.1101, lat: 48.1001), shapeStops[1], shapeStops[2], shapeStops[3]]),
]
for (name, segments, expected) in shapeCases {
    assert(TimetableShape(segments: segments).path(through: shapeStops) == expected, "Shape: \(name)")
}
assert(TimetableShape(segments: []).path(through: [shapeStops[0]]) == [shapeStops[0]], "A single stop stays")
assert(TimetableShape.endpoint(line: "N 72&", stops: [StopGps.example, StopGps(lon: 17.1, lat: -48.123456)])
       == "/timetable/shape?line=N%2072%26&stops=48.13574,17.20874;-48.12346,17.10000", "Shape request")
assert(TimetableShape.endpoint(line: "S+", stops: [StopGps.example, StopGps.example])?.contains("line=S%2B&") == true,
       "A + in the line stays a +")
print("PASS: \(shapeCases.count + 1) ride shapes joined with straight lines, and the shape request")
SWIFT
