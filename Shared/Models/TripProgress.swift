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

    /// The Live Activity content at `now`, and the alert due that is not in `alerted` yet.
    func update(at now: Date, delays: [Int: Int], passedStops: [Int: Int] = [:], alerted: Set<String> = [])
        -> TripUpdate
    {
        let progress = progress(at: now, delays: delays, passedStops: passedStops)
        var state = state(for: progress, at: now, delays: delays, alerted: alerted)
        let alert = alert(for: progress, state: state, at: now, delays: delays)
        if let alert { state.alerted.insert(alert.key) }
        return TripUpdate(progress: progress, state: state, alert: alert)
    }

    private func state(for progress: TripProgress, at now: Date, delays: [Int: Int], alerted: Set<String>)
        -> TripActivityAttributes.ContentState
    {
        let parts = parts ?? []
        let lastTransit = parts.indices.last { parts[$0].routeType != 64 }
        func shifted(_ date: Date, _ index: Int?) -> Date {
            date.expected(delaySeconds: index.flatMap { delays[$0] })
        }
        func minutesLate(_ index: Int) -> Int? { delays[index].map(delayMinutes) }
        let buffer = upcomingChange(progress.phase).flatMap { transferBuffers(delays: delays)[$0] }
        let warning: TripActivityAttributes.ContentState.Warning? = buffer.flatMap {
            $0.isLikelyMissed ? .likelyMissedChange : $0.isTight ? .tightChange : nil
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
            return content(
                .board, line: part.routeShortName, title: "Board at \(part.startStopName ?? "the stop")",
                detail: [part.startStopCode.map { "Platform \($0)" }, countdown.phrase]
                    .compactMap { $0 }.joined(separator: " · "),
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
            let title = part.startStopCode.map {
                (sameStop && arriving?.endStopCode == $0 ? "Wait at platform " : "Walk to platform ") + $0
            } ?? "Walk to \(part.startStopName ?? "the next stop")"
            let leaves = "\(part.routeShortName ?? "The next vehicle") leaves \(countdown.phrase)"
            return content(
                .change, line: part.routeShortName, title: title,
                detail: [sameStop ? nil : part.startStopName, leaves].compactMap { $0 }.joined(separator: " · "),
                time: time, delay: minutesLate(index),
                compact: part.startStopCode.map { "\($0) · \(countdown.minimal)" } ?? countdown.short,
                minimal: part.startStopCode ?? countdown.minimal
            )
        case .walk(let index):
            let time = shifted(parts[index].endArrival, lastTransit)
            let countdown = Countdown(to: time, from: now)
            return content(
                .walk, title: "Walk to \(parts[index].endStopName ?? "your destination")",
                detail: "Arrive \(countdown.phrase)", time: time, compact: countdown.short, minimal: countdown.minimal
            )
        case .arrived:
            return content(
                .arrived, title: "Arrived", detail: parts.last?.endStopName ?? "",
                time: parts.last.map { shifted($0.endArrival, lastTransit) } ?? now, compact: "Arrived", minimal: "✓"
            )
        }
    }

    /// The most urgent alert due: a likely missed change, the platform at a change, then getting off.
    private func alert(
        for progress: TripProgress, state: TripActivityAttributes.ContentState, at now: Date, delays: [Int: Int]
    ) -> TripAlert? {
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

    private func nextTransit(after index: Int) -> Int? {
        guard let parts else { return nil }
        return parts.indices.first { $0 > index && parts[$0].routeType != 64 }
    }
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
