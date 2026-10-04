//
//  Trip.swift
//  Transi
//
//  Created by magic_sk on 09/05/2023.
//

import AppIntents
import Foundation

struct Trip: Codable, Hashable {
    var journey: [Journey]?
}

struct Journey: Codable, Hashable, AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Journey"
    static var defaultQuery = JourneyQuery()

    var id: String
    var parts: [Part]?
    var zones: [String]?
    /// R-API id of the cheapest single ticket that covers the whole journey.
    var ticketId: Int? = nil

    var displayRepresentation: DisplayRepresentation {
        let start = parts?.first?.startStopName ?? "Start"
        let end = parts?.last?.endStopName ?? "End"
        return DisplayRepresentation(title: "\(start) to \(end)", subtitle: "\(parts?.count ?? 0) parts")
    }

    static func == (lhs: Journey, rhs: Journey) -> Bool {
        guard let lParts = lhs.parts, let rParts = rhs.parts, lParts.count == rParts.count else {
            return false
        }
        for (i, lPart) in lParts.enumerated() {
            let rPart = rParts[i]

            if lPart.routeType == 64 && rPart.routeType == 64 {
                continue
            }

            let lStart = Int(lPart.startDeparture.timeIntervalSinceReferenceDate / 60)
            let rStart = Int(rPart.startDeparture.timeIntervalSinceReferenceDate / 60)
            let lEnd = Int(lPart.endArrival.timeIntervalSinceReferenceDate / 60)
            let rEnd = Int(rPart.endArrival.timeIntervalSinceReferenceDate / 60)

            if lStart != rStart
                || lEnd != rEnd
                || lPart.routeShortName != rPart.routeShortName
                || lPart.startStopName != rPart.startStopName
                || lPart.endStopName != rPart.endStopName
            {
                return false
            }
        }
        return true
    }

    func hash(into hasher: inout Hasher) {
        if let parts = parts {
            for part in parts {
                if part.routeType == 64 {
                    hasher.combine("walking")
                } else {
                    hasher.combine(Int(part.startDeparture.timeIntervalSinceReferenceDate / 60))
                    hasher.combine(Int(part.endArrival.timeIntervalSinceReferenceDate / 60))
                    hasher.combine(part.routeShortName)
                    hasher.combine(part.startStopName)
                    hasher.combine(part.endStopName)
                }
            }
        } else {
            hasher.combine("no_parts")
        }
    }
}

struct JourneyQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [Journey] {
        return [] // Placeholder
    }
}

struct Part: Codable, Hashable {
    var startStopName: String?
    var endStopName: String?
    var startStopCode: String?
    var endStopCode: String?

    var startDeparture: Date
    var endArrival: Date

    var routeType: Int?
    var tripHeadsign: String?
    var routeShortName: String?

    // Optional, so trips saved by older versions and offline results without them still decode.
    /// R-API/B-API trip id, used to fetch the leg's stops.
    var tripId: Int? = nil
    /// B-API platform ids of the boarding and alighting stops.
    var startStopId: Int? = nil
    var endStopId: Int? = nil
    /// Station ids, equal to `Stop.stationId`.
    var startStationId: Int? = nil
    var endStationId: Int? = nil
    var startStopGps: StopGps? = nil
    var endStopGps: StopGps? = nil
    /// Vehicle delay in seconds when the search ran; nil when it was not running yet.
    var delaySeconds: Int? = nil
    var lowFloor: Bool? = nil
    /// Every stop of the leg, boarding and alighting included; nil until known.
    var stops: [PartStop]? = nil

    static let example = Part(
        startStopName: "Hronská",
        endStopName: "Pažítková",
        startStopCode: "A",
        endStopCode: "A",
        startDeparture: dateFromUtc("2023-10-03T14:41:00.000Z"),
        endArrival: dateFromUtc("2023-10-03T14:52:00.000Z"),
        routeType: 50,
        tripHeadsign: "Hlavná stanica",
        routeShortName: "X99"
    )
}

struct PartStop: Codable, Hashable {
    var name: String
    /// Platform letter.
    var platform: String?
    /// Scheduled time.
    var time: Date
    var gps: StopGps?
    /// Fare zone name, like "100".
    var zone: String?
    var isRequestStop = false
    /// imhd stop id (`Stop.id`), which opens the stop's departure board.
    var stopId: Int?
}

struct ZoneChange: Hashable {
    /// Index of the first stop in the new zone.
    let index: Int
    let from: String
    let to: String
}

extension Array where Element == PartStop {
    /// The fare zone borders the leg crosses. Stops without a zone are skipped.
    var zoneChanges: [ZoneChange] {
        var changes = [ZoneChange]()
        var current: String?
        for (index, stop) in enumerated() {
            guard let zone = stop.zone else { continue }
            if let current, current != zone {
                changes.append(ZoneChange(index: index, from: current, to: zone))
            }
            current = zone
        }
        return changes
    }
}

struct TransferBuffer: Hashable {
    /// Spare minutes left after the walk, rounded down; negative once the connection is gone.
    let minutes: Int
    var isTight: Bool { minutes <= 1 }
    var isLikelyMissed: Bool { minutes < 0 }
}

/// The whole minutes a delay in seconds is shown as, rounded to the nearest: a vehicle 50 s late reads
/// "+1 min", 20 s late "on time".
func delayMinutes(_ seconds: Int) -> Int {
    Int((Double(seconds) / 60).rounded())
}

extension Journey {
    /// The spare time at each change between transit legs, keyed by the index of the leg to catch:
    /// its departure minus the previous transit leg's arrival minus the walks between them.
    /// `delays` (seconds, by part index) shift both vehicles by the whole minutes they are shown as, so a
    /// change is likely missed only when the delays on screen make it so; pass live delays to spot one.
    func transferBuffers(delays: [Int: Int] = [:]) -> [Int: TransferBuffer] {
        let parts = parts ?? []
        var buffers = [Int: TransferBuffer]()
        var arriving: Int?
        var walk: TimeInterval = 0
        for (index, part) in parts.enumerated() {
            if part.routeType == 64 {
                walk += part.endArrival.timeIntervalSince(part.startDeparture)
                continue
            }
            if let arriving {
                let arrival = parts[arriving].endArrival + TimeInterval(delayMinutes(delays[arriving] ?? 0) * 60)
                let departure = part.startDeparture + TimeInterval(delayMinutes(delays[index] ?? 0) * 60)
                let seconds = departure.timeIntervalSince(arrival) - walk
                buffers[index] = TransferBuffer(minutes: Int((seconds / 60).rounded(.down)))
            }
            arriving = index
            walk = 0
        }
        return buffers
    }
}

enum ArrivalDeparture: String, Codable {
    case arrival
    case departure
}
