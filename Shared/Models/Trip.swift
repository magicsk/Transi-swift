//
//  Trip.swift
//  Transi
//
//  Created by magic_sk on 09/05/2023.
//

import Foundation

struct Trip: Codable, Hashable {
    var journey: [Journey]?
}

struct Journey: Codable, Hashable {
    var id: String
    var parts: [Part]?
    var zones: [String]?

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

enum ArrivalDeparture {
    case arrival
    case departure
}
