//
//  TripProgress.swift
//  Transi
//
//  Created by magic_sk on 04/10/2026.
//

import Foundation

/// Where the traveller is on a journey at a moment, from the leg stop times and the vehicles' delays.
struct TripProgress: Hashable {
    enum Phase: Hashable {
        /// Waiting for the first vehicle; its part index.
        case board(Int)
        /// On the vehicle of this part.
        case ride(Int)
        /// Between vehicles; the part index of the next one.
        case change(Int)
        /// Walking to the destination after the last vehicle; the part index of the walk.
        case walk(Int)
        case arrived
    }

    var phase: Phase
    /// While riding, the index in `Part.legStops` of the next stop the vehicle reaches.
    var nextStop: Int? = nil
    /// Stops left to the alighting stop; nil when the leg's stop list did not load.
    var stopsLeft: Int? = nil
    /// How far the ride has got, 0...1.
    var fraction: Double? = nil
}

/// A leg stop whose live board the trip Live Activity watches.
struct TripTrackerTarget: Codable, Hashable {
    let part: Int
    let stop: Int
}

/// A trip Live Activity alert; `key` makes it fire once per step.
struct TripAlert: Equatable {
    let key: String
    let title: String
    let body: String
}

/// The traveller's location, good to within `accuracy` metres.
struct TripFix: Equatable {
    let gps: StopGps
    let accuracy: Double
}

/// Walking pace over the straight line to a stop, slower than on foot to cover the streets' detours.
let tripWalkMetersPerSecond = 1.0

/// A ride the traveller's location showed them not on, and the other connections found from where they are.
struct TripMissed: Equatable {
    let part: Int
    /// They rode it for a while, so they got off or the vehicle left its route.
    let boarded: Bool
    /// Nil while the search runs.
    var alternatives: TripAlternatives?
}

/// Other connections to the destination after a missed ride.
struct TripAlternatives: Equatable {
    /// On the same lines as the rest of the trip: the next vehicles.
    var sameRoute = [Journey]()
    /// The rest, the earliest arrival first.
    var others = [Journey]()

    var isEmpty: Bool { sameRoute.isEmpty && others.isEmpty }
    /// The earliest arrival.
    var best: Journey? { (sameRoute + others).min { $0.expectedArrival < $1.expectedArrival } }
}

/// One recomputation of the trip Live Activity.
struct TripUpdate {
    let progress: TripProgress
    /// Includes `alert`'s key in `alerted`.
    let state: TripActivityAttributes.ContentState
    let alert: TripAlert?
}

extension Part {
    /// Every stop of the leg, or only its boarding and alighting stops when the stop list did not load.
    var legStops: [PartStop] {
        stops ?? [
            PartStop(name: startStopName ?? "", platform: startStopCode, time: startDeparture, gps: startStopGps),
            PartStop(name: endStopName ?? "", platform: endStopCode, time: endArrival, gps: endStopGps),
        ]
    }
}

extension Connection {
    /// The delay in seconds while the vehicle reports live; timetable-only rows have none.
    var liveDelaySeconds: Int? { type == "online" ? delay * 60 : nil }
}

/// Table and trip Live Activities share background mode, so it may stop only once neither runs.
func backgroundModeCanStop(tableActivities: Int, followsTrip: Bool) -> Bool {
    tableActivities == 0 && !followsTrip
}

/// After a relaunch the saved delays may be stale, so an arrived trip ends only once a live board answered or
/// 10 minutes after its arrival.
func tripCanEnd(at now: Date, arrival: Date, awaitsLiveData: Bool) -> Bool {
    !awaitsLiveData || now >= arrival + 10 * 60
}

/// What the live boards showed of a followed journey's vehicles, by part index. Saved with the journey, so a
/// relaunch keeps following the same vehicles from where they got to.
struct TripLiveData: Codable, Equatable {
    /// Seconds late.
    var delays = [Int: Int]()
    var busIDs = [Int: String]()
    /// The last leg stop each vehicle left; none while the boards do not show where it is.
    var passedStops = [Int: Int]()
    /// When the followed vehicle was due to leave each board that listed it.
    var listed = [TripTrackerTarget: Date]()
    /// The last leg stop each vehicle left by the traveller's location while they ride it. It never moves the vehicle
    /// the location is checked against, which comes from the boards and the timetable.
    var located = [Int: Int]()
    /// Rides the location showed the traveller on, past their boarding stop.
    var boarded = Set<Int>()
    /// Since when the location has not shown the traveller on each ride.
    var offRide = [Int: Date]()
    /// The ride the traveller is not on, so the trip offers other connections instead of its steps.
    var missed: Int?
    /// Rides the traveller kept following after the location found them off, which it no longer checks.
    var kept = Set<Int>()

    /// The last leg stop each vehicle left: on the boards, or by the location when that is further on.
    var positions: [Int: Int] { passedStops.merging(located, uniquingKeysWith: max) }

    /// One refresh of the trip: takes in `fix` against where the boards and the timetable had the vehicles a minute ago
    /// (their whole-minute times and delays may run up to that far ahead), then the ride missed, with the other
    /// connections in `found` (nil until the search answers).
    mutating func locate(_ fix: TripFix?, on journey: Journey, found: [Journey]?, now: Date) -> TripMissed? {
        if let fix {
            let progress = journey.progress(at: now - 60, delays: journey.delays(live: delays), passedStops: passedStops)
            receive(fix, on: journey, progress: progress, now: now)
        }
        return missed.map { index in
            TripMissed(
                part: index, boarded: boarded.contains(index),
                alternatives: found.map { journey.alternatives($0, missed: index, at: now) }
            )
        }
    }

    /// Takes in the traveller's location while `progress`, from the boards and the timetable, has them riding. On the
    /// vehicle's line and not more than a stop (or 500 m, between far stops) behind it, they ride it, and the stop they
    /// are at counts as reached; near the alighting stop they got off there. Otherwise for 45 s they missed it, once the
    /// vehicle is that far ahead or they are off its line. Without a live delay the vehicle may only be late: it is
    /// missed only by staying at the boarding stop or leaving the line, and not before 5 minutes after it was due.
    mutating func receive(_ fix: TripFix, on journey: Journey, progress: TripProgress, now: Date) {
        guard missed == nil, case .ride(let index) = progress.phase, !kept.contains(index),
              let part = journey.parts?[index], located[index] != part.legStops.count - 1
        else { return }
        let stops = part.legStops
        let vehicle = (progress.fraction ?? 0) * Double(stops.count - 1)
        guard let place = part.placement(of: fix, near: vehicle) else { return }
        let isLive = delays[index] != nil
        let behind = place.stop < vehicle - 1 || place.meters(atStop: vehicle) - place.along > 500
        let rides = place.onLine && (!behind || !isLive && place.along >= 150)
        let alighted = stops.last?.gps.map { fix.gps.distance(to: $0) <= 300 + fix.accuracy } ?? false
        if rides || alighted {
            offRide[index] = nil
            if rides, place.along >= 150 {
                boarded.insert(index)
            }
            let next = rides ? place.stops.firstIndex { $0 > place.along + 40 } ?? stops.count : stops.count
            located[index] = max(located[index] ?? 0, next - 1)
            return
        }
        guard isLive || now >= part.startDeparture + TimeInterval(part.delaySeconds ?? 0) + 300
        else { return }
        let since = offRide[index] ?? now
        offRide[index] = since
        if now.timeIntervalSince(since) >= 45 {
            missed = index
        }
    }

    /// Takes in the leg's departure on `target`'s board from its PartLiveTracker, which only reports the vehicle
    /// it follows (passed from `busIDs`, or the first one live), nil while the board does not list it. A stop's
    /// board lists a vehicle with the stop it left last (not this one) until it leaves this stop, then drops it.
    mutating func receive(_ connection: Connection?, at target: TripTrackerTarget, of journey: Journey, now: Date) {
        let index = target.part
        let stops = journey.parts?[index].legStops ?? []
        if let connection, let delay = connection.liveDelaySeconds {
            delays[index] = delay
            busIDs[index] = connection.busID
            listed[target] = Date(timeIntervalSince1970: connection.departureTimeRaw)
            // A loop line passes a stop twice, so take the one nearest before this stop.
            let left = stops.indices.last { $0 < target.stop && sameStop(stops[$0].name, connection.lastStopName) }
            if let left { passedStops[index] = max(passedStops[index] ?? left, left) }
        } else if target.stop > 0, target.stop < stops.count {
            let delay = TimeInterval(journey.delays(live: delays)[index] ?? 0)
            if let due = listed[target] {
                // Dropped from the board: it left this stop, unless the board only reconnected before it was due.
                if now >= due { passedStops[index] = max(passedStops[index] ?? target.stop, target.stop) }
            } else if now >= stops[target.stop].time + delay + 180 {
                // Never listed here and long past due (the board-matching tolerance): the vehicle went by unseen
                // or the boards stopped listing it. Count by the delayed timetable until a board lists it again.
                passedStops[index] = nil
            }
        }
    }
}

extension Journey {
    /// Seconds late by part index: the live delay, else the one from the B-API or the search.
    func delays(live: [Int: Int]) -> [Int: Int] {
        var delays = live
        for (index, part) in (parts ?? []).enumerated() where delays[index] == nil {
            delays[index] = part.delaySeconds
        }
        return delays
    }

    /// `delays` (seconds, by part index) shift each vehicle's stop times; `passedStops` is the leg stop index
    /// each vehicle left last on the live boards and wins over the timetable when counting the stops left.
    func progress(at now: Date, delays: [Int: Int], passedStops: [Int: Int] = [:]) -> TripProgress {
        let parts = parts ?? []
        let transit = parts.indices.filter { parts[$0].routeType != 64 }
        func delay(_ index: Int?) -> TimeInterval { TimeInterval(index.flatMap { delays[$0] } ?? 0) }

        for index in transit {
            let part = parts[index]
            if now < part.startDeparture + delay(index) {
                return TripProgress(phase: index == transit.first ? .board(index) : .change(index))
            }
            if now < part.endArrival + delay(index) {
                return ride(index, part, at: now, delay: delay(index), passed: passedStops[index])
            }
        }
        if let walk = parts.indices.last, walk != transit.last,
           now < parts[walk].endArrival + delay(transit.last)
        {
            return TripProgress(phase: .walk(walk))
        }
        return TripProgress(phase: .arrived)
    }

    private func ride(_ index: Int, _ part: Part, at now: Date, delay: TimeInterval, passed: Int?)
        -> TripProgress
    {
        let times = part.legStops.map { $0.time + delay }
        guard times.count > 1 else { return TripProgress(phase: .ride(index)) }
        // The vehicle's own position wins.
        let next = passed.map { min($0 + 1, times.count) } ?? max(times.firstIndex { $0 > now } ?? times.count - 1, 1)
        let previous = times[next - 1]
        let gap = times[min(next, times.count - 1)].timeIntervalSince(previous)
        let between = gap > 0 ? min(max(now.timeIntervalSince(previous) / gap, 0), 1) : 1
        let fraction = min((Double(next - 1) + between) / Double(times.count - 1), 1)
        return TripProgress(
            phase: .ride(index),
            nextStop: next,
            stopsLeft: part.stops == nil ? nil : times.count - next,
            // Whole percents, so the activity is not updated for invisible changes.
            fraction: (fraction * 100).rounded() / 100
        )
    }

    /// The live boards to watch: the boarding stop until the vehicle leaves, then the next stop it reaches,
    /// plus the next vehicle's boarding stop while a change lies ahead.
    func trackerTargets(for progress: TripProgress) -> [TripTrackerTarget] {
        switch progress.phase {
        case .board(let index), .change(let index):
            return [TripTrackerTarget(part: index, stop: 0)]
        case .ride(let index):
            guard let part = parts?[index] else { return [] }
            let last = part.legStops.count - 1
            var stop = min(progress.nextStop ?? last, last)
            // A vehicle ending its run is no departure, so the terminus board will not list it.
            if stop == last, let headsign = part.tripHeadsign, terminates(headsign: headsign, at: part.endStopName) {
                stop -= 1
            }
            var targets = stop > 0 ? [TripTrackerTarget(part: index, stop: stop)] : []
            if let next = nextTransit(after: index) {
                targets.append(TripTrackerTarget(part: next, stop: 0))
            }
            return targets
        case .walk, .arrived:
            return []
        }
    }

    /// The Live Activity content at `now`, and the alert due that is not in `alerted` yet. `fix` adds the walk to the
    /// next stop; `missed` replaces the steps with the other connections.
    func update(
        at now: Date, delays: [Int: Int], passedStops: [Int: Int] = [:], alerted: Set<String> = [],
        fix: TripFix? = nil, missed: TripMissed? = nil
    ) -> TripUpdate {
        let progress = progress(at: now, delays: delays, passedStops: passedStops)
        var state = missed.map { missedState($0, delays: delays, alerted: alerted) }
            ?? state(for: progress, at: now, delays: delays, alerted: alerted, fix: fix)
        let alert = alert(for: progress, state: state, at: now, delays: delays, missed: missed)
        if let alert { state.alerted.insert(alert.key) }
        return TripUpdate(progress: progress, state: state, alert: alert)
    }

    private func state(
        for progress: TripProgress, at now: Date, delays: [Int: Int], alerted: Set<String>, fix: TripFix?
    ) -> TripActivityAttributes.ContentState {
        let parts = parts ?? []
        let lastTransit = parts.indices.last { parts[$0].routeType != 64 }
        func shifted(_ date: Date, _ index: Int?) -> Date {
            date.expected(delaySeconds: index.flatMap { delays[$0] })
        }
        func minutesLate(_ index: Int) -> Int? { delays[index].map(delayMinutes) }
        var fix = fix
        // A change starts at the arriving vehicle's whole-minute arrival, when it may still be a stop away, so the walk
        // counts from the location only a minute later.
        if case .change(let index) = progress.phase,
           let arriving = parts[..<index].lastIndex(where: { $0.routeType != 64 }),
           now < shifted(parts[arriving].endArrival, arriving) + 60
        {
            fix = nil
        }
        /// Metres to `gps` while the traveller is further than the location tells apart from being there.
        func away(_ gps: StopGps?) -> Double? {
            guard let fix, let gps else { return nil }
            let meters = fix.gps.distance(to: gps)
            return meters > max(50, fix.accuracy) ? meters : nil
        }
        let buffer = upcomingChange(progress.phase).flatMap { transferBuffers(delays: delays)[$0] }
        var warning: TripActivityAttributes.ContentState.Warning? = buffer.flatMap {
            $0.isLikelyMissed ? .likelyMissedChange : $0.isTight ? .tightChange : nil
        }
        // Searches and older trips may only know the station's position, up to ~150 m from the platform.
        if warning != .likelyMissedChange, let index = boarding(progress.phase),
           let meters = away(parts[index].legStops.first?.gps),
           (meters - 150) / tripWalkMetersPerSecond > shifted(parts[index].startDeparture, index).timeIntervalSince(now)
        {
            warning = .mayMiss
        }
        func content(
            _ step: TripActivityAttributes.ContentState.Step, line: String? = nil, title: String, detail: String,
            time: Date, delay: Int? = nil, progress: Double? = nil, compact: String, minimal: String
        ) -> TripActivityAttributes.ContentState {
            TripActivityAttributes.ContentState(
                step: step, line: line, title: title, detail: detail, time: time, delay: delay, progress: progress,
                compact: compact, minimal: minimal, warning: warning, alerted: alerted
            )
        }

        switch progress.phase {
        case .board(let index):
            let part = parts[index]
            let time = shifted(part.startDeparture, index)
            let countdown = Countdown(to: time, from: now)
            let stop = part.startStopName ?? "the stop"
            let platform = part.legStops.first?.gps
            let detail = away(platform).map { meters in
                distanceText(meters) + (part.startStopCode.map { " to platform \($0)" } ?? "")
                    + " · leaves \(countdown.phrase)"
            } ?? [part.startStopCode.map { "Platform \($0)" }, countdown.phrase].compactMap { $0 }.joined(separator: " · ")
            return content(
                .board, line: part.routeShortName,
                title: away(platform) == nil ? "Board at \(stop)" : "Walk to \(stop)", detail: detail,
                time: time, delay: minutesLate(index), compact: countdown.short, minimal: countdown.minimal
            )
        case .ride(let index):
            let part = parts[index]
            let time = shifted(part.endArrival, index)
            let countdown = Countdown(to: time, from: now)
            let title: String
            switch progress.stopsLeft {
            case nil: title = "Get off \(countdown.phrase)"
            case 0: title = "Get off now"
            case 1: title = "Get off at the next stop"
            case let stops?: title = "Get off in \(stops) stops"
            }
            return content(
                .ride, line: part.routeShortName, title: title,
                detail: [part.endStopName, part.endStopCode.map { "platform \($0)" }]
                    .compactMap { $0 }.joined(separator: ", "),
                time: time, delay: minutesLate(index), progress: progress.fraction,
                compact: progress.stopsLeft.map { $0 == 0 ? "now" : $0 == 1 ? "1 stop" : "\($0) stops" }
                    ?? countdown.short,
                minimal: progress.stopsLeft.map(String.init) ?? countdown.minimal
            )
        case .change(let index):
            let part = parts[index]
            let time = shifted(part.startDeparture, index)
            let countdown = Countdown(to: time, from: now)
            let arriving = parts[..<index].last { $0.routeType != 64 }
            let sameStop = arriving?.endStopName == part.startStopName
            let platform = part.legStops.first?.gps
            let meters = away(platform)
            // Where the location and the stop's position are known, waiting is being at the stop.
            let waits = fix != nil && platform != nil
                ? meters == nil : sameStop && arriving?.endStopCode == part.startStopCode
            let title = part.startStopCode.map { (waits ? "Wait at platform " : "Walk to platform ") + $0 }
                ?? (waits ? "Wait at " : "Walk to ") + (part.startStopName ?? "the next stop")
            let leaves = "\(part.routeShortName ?? "The next vehicle") leaves \(countdown.phrase)"
            let walk = meters.map { distanceText($0) + (sameStop ? "" : part.startStopName.map { " to \($0)" } ?? "") }
            return content(
                .change, line: part.routeShortName, title: title,
                detail: [walk ?? (sameStop ? nil : part.startStopName), leaves].compactMap { $0 }.joined(separator: " · "),
                time: time, delay: minutesLate(index),
                compact: part.startStopCode.map { "\($0) · \(countdown.minimal)" } ?? countdown.short,
                minimal: part.startStopCode ?? countdown.minimal
            )
        case .walk(let index):
            let time = shifted(parts[index].endArrival, lastTransit)
            let countdown = Countdown(to: time, from: now)
            let arrive = "Arrive \(countdown.phrase)"
            return content(
                .walk, title: "Walk to \(parts[index].endStopName ?? "your destination")",
                detail: away(parts[index].endStopGps).map { "\(distanceText($0)) · \(arrive.lowercased())" } ?? arrive,
                time: time, compact: countdown.short, minimal: countdown.minimal
            )
        case .arrived:
            return content(
                .arrived, title: "Arrived", detail: parts.last?.endStopName ?? "",
                time: parts.last.map { shifted($0.endArrival, lastTransit) } ?? now, compact: "Arrived", minimal: "✓"
            )
        }
    }

    /// The other connections in place of the steps, the soonest arrival first.
    private func missedState(_ missed: TripMissed, delays: [Int: Int], alerted: Set<String>)
        -> TripActivityAttributes.ContentState
    {
        let part = parts?[missed.part]
        let line = part?.routeShortName
        let best = missed.alternatives?.best
        let ride = best?.parts?.first { $0.routeType != 64 }
        let leaves = ride.map { $0.startDeparture.expected(delaySeconds: $0.delaySeconds) }
        let detail: String
        if let ride, let leaves {
            detail = "Take \(ride.routeShortName ?? "the next vehicle") at \(timeStringFromDate(leaves)) from "
                + [ride.startStopName ?? "the stop", ride.startStopCode].compactMap { $0 }.joined(separator: " ")
        } else {
            detail = missed.alternatives == nil ? "Finding other connections…" : "No other connections found"
        }
        return TripActivityAttributes.ContentState(
            step: .missed, line: ride?.routeShortName ?? line,
            title: missed.boarded ? "Off the route" : "Missed \(line ?? "the vehicle")", detail: detail,
            // Until there is another one, when the missed vehicle left.
            time: leaves ?? part.map { $0.startDeparture.expected(delaySeconds: delays[missed.part]) } ?? .distantPast,
            compact: "Missed", minimal: "!", alerted: alerted
        )
    }

    /// The most urgent alert due: a missed ride, a likely missed change, the walk to a vehicle that may leave first,
    /// the platform at a change, then getting off.
    private func alert(
        for progress: TripProgress, state: TripActivityAttributes.ContentState, at now: Date, delays: [Int: Int],
        missed: TripMissed?
    ) -> TripAlert? {
        if let missed {
            // Once the search answered, so the alert says what to take.
            let alert = TripAlert(key: "lost-\(missed.part)", title: state.title, body: state.detail)
            return missed.alternatives == nil || state.alerted.contains(alert.key) ? nil : alert
        }
        let parts = parts ?? []
        var due = [TripAlert]()
        if state.warning == .likelyMissedChange, let index = upcomingChange(progress.phase) {
            let part = parts[index]
            let departure = part.startDeparture.expected(delaySeconds: delays[index])
            due.append(TripAlert(
                key: "missed-\(index)", title: "Change likely missed",
                body: "\(part.routeShortName ?? "The next vehicle") leaves \(part.startStopName ?? "the stop") "
                    + "at \(timeStringFromDate(departure))"
            ))
        }
        if state.warning == .mayMiss, let index = boarding(progress.phase) {
            due.append(TripAlert(
                key: "hurry-\(index)", title: "You may miss \(parts[index].routeShortName ?? "the next vehicle")",
                body: state.detail
            ))
        }
        switch progress.phase {
        case .change(let index):
            let part = parts[index]
            due.append(TripAlert(
                key: "change-\(index)",
                title: part.startStopCode.map { "Change to platform \($0)" } ?? state.title, body: state.detail
            ))
        case .ride(let index) where progress.stopsLeft.map { $0 <= 1 } ?? (state.time.timeIntervalSince(now) <= 120):
            due.append(TripAlert(key: "off-\(index)", title: state.title, body: state.detail))
        default:
            break
        }
        return due.first { !state.alerted.contains($0.key) }
    }

    /// The change ahead: the vehicle after the current or awaited one.
    private func upcomingChange(_ phase: TripProgress.Phase) -> Int? {
        switch phase {
        case .board(let index), .ride(let index): return nextTransit(after: index)
        case .change(let index): return index
        case .walk, .arrived: return nil
        }
    }

    /// The vehicle to walk to and board.
    private func boarding(_ phase: TripProgress.Phase) -> Int? {
        switch phase {
        case .board(let index), .change(let index): return index
        case .ride, .walk, .arrived: return nil
        }
    }

    private func nextTransit(after index: Int) -> Int? {
        guard let parts else { return nil }
        return parts.indices.first { $0 > index && parts[$0].routeType != 64 }
    }
}

extension Journey {
    /// The last arrival, the last vehicle's search-time delay included.
    var expectedArrival: Date {
        let last = parts?.last { $0.routeType != 64 }
        return (parts?.last?.endArrival ?? .distantFuture).expected(delaySeconds: last?.delaySeconds)
    }

    /// The lines of the rides from part `index` on.
    func lines(from index: Int = 0) -> [String?] {
        (parts ?? []).dropFirst(index).filter { $0.routeType != 64 }.map(\.routeShortName)
    }

    /// `found` (from where the traveller is, soonest first) whose first vehicle has not left, sorted out against this trip's rides
    /// from the missed `index` on: the next two on its lines, then three others.
    func alternatives(_ found: [Journey], missed index: Int, at now: Date) -> TripAlternatives {
        let upcoming = found.filter { journey in
            guard let ride = journey.parts?.first(where: { $0.routeType != 64 }) else { return false }
            return ride.startDeparture.expected(delaySeconds: ride.delaySeconds) >= now
        }
        let lines = lines(from: index)
        return TripAlternatives(
            sameRoute: Array(upcoming.filter { $0.lines() == lines }.prefix(2)),
            others: Array(upcoming.filter { $0.lines() != lines }.sorted { $0.expectedArrival < $1.expectedArrival }
                .prefix(3))
        )
    }
}

/// Where a location lies along a ride's stops.
struct RidePlacement {
    /// Each stop's metres along the straight lines between the stops.
    let stops: [Double]
    /// Metres along them to their point nearest the location.
    let along: Double
    /// That point as a stop index with the fraction on to the next stop.
    let stop: Double
    /// Within 250 m of the line (a quarter of the gap between far stops) plus the location's accuracy: the streets
    /// curve between stops.
    let onLine: Bool

    /// Metres along to `stop`, a stop index with the fraction on to the next stop.
    func meters(atStop stop: Double) -> Double {
        let lower = min(max(Int(stop), 0), stops.count - 2)
        return stops[lower] + (stop - Double(lower)) * (stops[lower + 1] - stops[lower])
    }
}

extension Part {
    /// Where `fix` lies along the leg's stops; where the line passes it more than once, nearest `stop` (a stop index with
    /// the fraction on to the next). Nil while a stop's position is unknown.
    func placement(of fix: TripFix, near stop: Double) -> RidePlacement? {
        // The location is the origin.
        let points = legStops.compactMap { $0.gps?.meters(from: fix.gps) }
        guard points.count == legStops.count, points.count > 1 else { return nil }
        var stops = [0.0]
        var best: (rank: (Int, Double), along: Double, stop: Double)?
        for index in 1 ..< points.count {
            let (a, b) = (points[index - 1], points[index])
            let (dx, dy) = (b.x - a.x, b.y - a.y)
            let length = hypot(dx, dy)
            let t = length > 0 ? min(max(-(a.x * dx + a.y * dy) / (length * length), 0), 1) : 0
            let off = hypot(a.x + t * dx, a.y + t * dy)
            let tolerance = max(250, length / 4) + fix.accuracy
            let at = Double(index - 1) + t
            let rank = off <= tolerance ? (0, abs(at - stop)) : (1, off - tolerance)
            if best.map({ rank < $0.rank }) ?? true {
                best = (rank, stops[index - 1] + t * length, at)
            }
            stops.append(stops[index - 1] + length)
        }
        guard let best else { return nil }
        return RidePlacement(stops: stops, along: best.along, stop: best.stop, onLine: best.rank.0 == 0)
    }
}

extension StopGps {
    /// Metres east and north of `origin` on a plane, true to well under 1% across a city.
    func meters(from origin: StopGps) -> (x: Double, y: Double) {
        let perDegree = 111_195.0
        return ((lon - origin.lon) * perDegree * cos(origin.lat * .pi / 180), (lat - origin.lat) * perDegree)
    }

    func distance(to other: StopGps) -> Double {
        let offset = meters(from: other)
        return hypot(offset.x, offset.y)
    }
}

/// "80 m", "350 m", "1.2 km".
private func distanceText(_ meters: Double) -> String {
    meters < 950 ? "\(Int((meters / 10).rounded()) * 10) m" : String(format: "%.1f km", meters / 1000)
}

/// Live feeds drop the "Bratislava, " prefix of regional stop names.
private func sameStop(_ a: String, _ b: String) -> Bool {
    a.replacingOccurrences(of: "Bratislava, ", with: "") == b.replacingOccurrences(of: "Bratislava, ", with: "")
}

/// The table's countdown style from `now`: "4 min", "<1 min", "now", or the clock time from an hour ahead.
private struct Countdown {
    let short: String
    let minimal: String
    let phrase: String

    init(to date: Date, from now: Date) {
        let seconds = Int(date.timeIntervalSince(now))
        if seconds >= 3600 {
            short = timeStringFromDate(date)
            minimal = "\(seconds / 3600)h"
            phrase = "at \(short)"
        } else if seconds >= 60 {
            short = "\(seconds / 60) min"
            minimal = "\(seconds / 60)m"
            phrase = "in \(short)"
        } else if seconds > 0 {
            short = "<1 min"
            minimal = "<1m"
            phrase = "in <1 min"
        } else {
            short = "now"
            minimal = "now"
            phrase = "now"
        }
    }
}
