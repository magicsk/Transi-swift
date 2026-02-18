//
//  TripPlannerController+Mapping.swift
//  Transi
//
//  Created by Antigravity on 11/01/2026.
//

import Foundation

extension TripPlannerController {
    func mapRApiToJourneys(_ rJourneys: [RApiJourney]) -> [Journey] {
        return rJourneys.compactMap { rJourney -> Journey? in
            guard let rParts = rJourney.parts else { return nil }

            let parts = rParts.map { rPart in
                Part(
                    startStopName: rPart.startStopName,
                    endStopName: rPart.endStopName,
                    startStopCode: rPart.startStopCode,
                    endStopCode: rPart.endStopCode,
                    startDeparture: dateFromUtc(rPart.startDeparture),
                    endArrival: dateFromUtc(rPart.endArrival),
                    routeType: rPart.routeType,
                    tripHeadsign: rPart.tripHeadsign,
                    routeShortName: rPart.routeShortName
                )
            }

            return Journey(
                id: "r-\(UUID().uuidString)",
                parts: parts,
                zones: rJourney.zones?.map { String($0) }
            )
        }
    }

    private static let iApiDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
        f.timeZone = TimeZone(identifier: "Europe/Bratislava")
        return f
    }()

    func mapIApiToJourneys(_ iJourneys: [IApiJourney]) -> [Journey] {

        return iJourneys.compactMap { iJourney -> Journey? in
            let iParts = iJourney.parts

            let mappedLines: [String] =
                iJourney.linesMapping?.map { index in
                    guard let lines = iJourney.lines,
                        lines.indices.contains(index),
                        lines[index].count > 1,
                        let lineValue = lines[index][1].value as? String
                    else {
                        return "Err"
                    }
                    return lineValue
                } ?? []

            var parts: [Part] = []

            for (index, iPart) in iParts.enumerated() {
                let startStop = iPart.stops?.first
                let endStop = iPart.stops?.last

                let isWalking = iPart.type == "🚶" || iPart.type == "\u{1F6B6}"
                let routeType = isWalking ? 64 : 1

                var endStopCode = endStop?.label
                if isWalking && endStopCode == nil && iParts.indices.contains(index + 1) {
                    endStopCode = iParts[index + 1].stops?.first?.label
                }

                let routeShortName = mappedLines.indices.contains(index) ? mappedLines[index] : nil

                let startDepDate = TripPlannerController.iApiDateFormatter.date(from: iPart.departure.date) ?? Date()
                let endArrDate = TripPlannerController.iApiDateFormatter.date(from: iPart.arrival.date) ?? Date()

                parts.append(
                    Part(
                        startStopName: startStop?.name,
                        endStopName: endStop?.name,
                        startStopCode: startStop?.label,
                        endStopCode: endStopCode,
                        startDeparture: startDepDate,
                        endArrival: endArrDate,
                        routeType: routeType,
                        tripHeadsign: iPart.destination,
                        routeShortName: routeShortName
                    ))
            }

            return Journey(
                id: "i-\(UUID().uuidString)",
                parts: parts,
                zones: iJourney.fareZones?.zones
            )
        }
    }
}
