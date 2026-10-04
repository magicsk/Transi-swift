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

            // ponytail: stops stay nil; fetchStops(for:) loads the leg from the B-API when it is opened.
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
                    routeShortName: rPart.routeShortName,
                    tripId: rPart.tripId,
                    startStopId: rPart.startStopId,
                    endStopId: rPart.endStopId,
                    startStationId: rPart.startStationId,
                    endStationId: rPart.endStationId,
                    startStopGps: rPart.startStopGps,
                    endStopGps: rPart.endStopGps,
                    delaySeconds: rPart.tripDelay
                )
            }

            return Journey(
                id: "r-\(UUID().uuidString)",
                parts: parts,
                zones: rJourney.zones?.map { String($0) },
                ticketId: rJourney.ticketId
            )
        }
    }

    private static let iApiDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSS"
        f.timeZone = TimeZone(identifier: "Europe/Bratislava")
        return f
    }()

    /// `stops` is a snapshot of the stops list, joined on `stopPoleID` for coordinates and imhd stop ids.
    func mapIApiToJourneys(_ iJourneys: [IApiJourney], stops: [Stop]) -> [Journey] {
        let stopsByPlatformId = Dictionary(
            stops.flatMap { stop in (stop.platformLabels ?? []).map { ($0.id, stop) } },
            uniquingKeysWith: { first, _ in first }
        )
        func magicStop(_ iStop: IApiStop?, platform: String?) -> Stop? {
            guard let iStop else { return nil }
            return iStop.stopPoleID.flatMap { stopsByPlatformId[$0] }
                ?? stops.stop(stationId: nil, name: iStop.name, platform: platform)
        }

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

                let startMagicStop = magicStop(startStop, platform: startStop?.label)
                let endMagicStop = magicStop(endStop, platform: endStopCode)
                let iStops = isWalking ? [] : iPart.stops ?? []
                let partStops = iStops.enumerated().map { stopIndex, iStop in
                    let isLast = stopIndex == iStops.count - 1
                    let time = isLast ? iStop.arrival ?? iStop.departure : iStop.departure ?? iStop.arrival
                    let stop = magicStop(iStop, platform: iStop.label)
                    return PartStop(
                        name: iStop.name,
                        platform: iStop.label,
                        time: time.flatMap { TripPlannerController.iApiDateFormatter.date(from: $0.date) }
                            ?? (isLast ? endArrDate : startDepDate),
                        gps: stop?.gps,
                        zone: iStop.fareZones?.zones.first,
                        isRequestStop: iStop.requestStop == "1",
                        stopId: stop?.id
                    )
                }

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
                        routeShortName: routeShortName,
                        startStationId: startMagicStop?.stationId,
                        endStationId: endMagicStop?.stationId,
                        startStopGps: startMagicStop?.gps,
                        endStopGps: endMagicStop?.gps,
                        lowFloor: isWalking ? nil : iPart.attributes?.lowfloor,
                        stops: partStops.isEmpty ? nil : partStops
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

extension Calendar {
    static let bratislava: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Bratislava") ?? .current
        return calendar
    }()

    /// The wall-clock time `minutes` after midnight of `serviceDay`; over 1440 falls on the next day.
    func date(minutes: Int, after serviceDay: Date) -> Date {
        let day = date(byAdding: .day, value: minutes / 1440, to: serviceDay) ?? serviceDay
        return date(bySettingHour: minutes % 1440 / 60, minute: minutes % 60, second: 0, of: day) ?? day
    }
}

extension Array where Element == Stop {
    /// The stop of a station, or else the first one with that name, preferring one with the platform letter.
    func stop(stationId: Int?, name: String?, platform: String?) -> Stop? {
        let candidates = filter { stationId != nil ? $0.stationId == stationId : name != nil && $0.name == name }
        return candidates.first { $0.platformLabels?.contains { $0.label == platform } == true } ?? candidates.first
    }
}

extension Stop {
    /// Station-level position, up to ~200 m from the platform.
    var gps: StopGps? {
        guard let lat, let lng else { return nil }
        return StopGps(lon: lng, lat: lat)
    }
}

extension BApiTrip {
    /// `part`'s leg: its boarding stop, then the first alighting stop after it (a trip can pass a stop
    /// twice). Nil when the part has no B-API stop ids or the trip does not serve them.
    func partStops(for part: Part, stops: [Stop]) -> [PartStop]? {
        let calendar = Calendar.bratislava
        let start = calendar.dateComponents([.hour, .minute], from: part.startDeparture)
        let startMinute = (start.hour ?? 0) * 60 + (start.minute ?? 0)
        let boardings = stopTimes.indices.filter { stopTimes[$0].stopId == part.startStopId }
        guard let first = boardings.first(where: { stopTimes[$0].departure % 1440 == startMinute }) ?? boardings.first,
              let last = stopTimes[(first + 1)...].firstIndex(where: { $0.stopId == part.endStopId }),
              let serviceDay = calendar.date(
                  byAdding: .day, value: -(stopTimes[first].departure / 1440),
                  to: calendar.startOfDay(for: part.startDeparture)
              )
        else { return nil }

        return stopTimes[first...last].map { stopTime in
            PartStop(
                name: stopTime.stopName,
                platform: stopTime.stopCode,
                time: calendar.date(
                    minutes: stopTime.stopId == part.endStopId ? stopTime.arrival : stopTime.departure,
                    after: serviceDay
                ),
                gps: stopTime.stopGps,
                zone: stopTime.zone,
                stopId: stops.stop(stationId: stopTime.stationId, name: stopTime.stopName, platform: stopTime.stopCode)?.id
            )
        }
    }
}
