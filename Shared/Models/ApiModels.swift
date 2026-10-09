//
//  ApiModels.swift
//  Transi
//
//  Created by magic_sk on 19/11/2025.
//

import Foundation

struct FetchParams {
    let fromId: Int
    let toId: Int
    let requestBody: TripReq?
    let iApiUrl: String?
}

struct RApiTrip: Codable {
    var journey: [RApiJourney]?
}

// The fetch decoder converts snake_case keys, so "trip_id" only matches `tripId`, never `tripID`.
struct RApiJourney: Codable {
    var journeyGuid: String
    var parts: [RApiPart]?
    var zones: [Int]?
    var ticketId: Int?
}

struct RApiPart: Codable {
    var startStopId, endStopId: Int?
    var startStopName, startStopCode, endStopName, endStopCode: String?
    var startStationId, endStationId: Int?
    var startStopGps, endStopGps: StopGps?
    var startDeparture, endArrival: String?
    var duration, routeType, tripId, tripRouteId: Int?
    var tripHeadsign, tripShortName, routeShortName: String?
    var tripZones: [Int]?
    var tripDelay, ticketId: Int?
}

struct TripReq: Codable, Hashable {
    var org_id = 120
    var max_walk_duration: Int
    var max_transfers: Int
    var search_from_hours, search_to_hours: Int?
    var search_from, search_to: String?
    var from_station_id, to_station_id: [Int]
}

struct IApiTripResponse: Codable {
    let journeys: [IApiJourney]?
}

struct IApiJourney: Codable {
    let departure: IApiTime
    let arrival: IApiTime
    let parts: [IApiPart]
    let linesMapping: [Int]?
    let lines: [[AnyCodable]]?
    let fareZones: FareZones?

    enum CodingKeys: String, CodingKey {
        case departure, arrival, parts, linesMapping, lines, fareZones
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        departure = try container.decode(IApiTime.self, forKey: .departure)
        arrival = try container.decode(IApiTime.self, forKey: .arrival)
        parts = try container.decode([IApiPart].self, forKey: .parts)
        linesMapping = try container.decodeIfPresent([Int].self, forKey: .linesMapping)
        fareZones = try container.decodeIfPresent(FareZones.self, forKey: .fareZones)

        if let linesContainer = try? container.decode([[AnyCodable]].self, forKey: .lines) {
            lines = linesContainer
        } else {
            lines = nil
        }
    }
}

struct IApiPart: Codable {
    let departure: IApiTime
    let arrival: IApiTime
    let stops: [IApiStop]?
    let type: String?
    let attributes: IApiAttributes?
    let destination: String?
    let trip_service_type: Int?
}

struct IApiStop: Codable {
    let name: String
    let stopPoleID: String?
    let arrival: IApiTime?
    let departure: IApiTime?
    let label: String?
    let fareZones: FareZones?
    /// "1" for a request stop.
    let requestStop: String?
}

struct IApiTime: Codable {
    let date: String
}

struct IApiAttributes: Codable {
    let TripName: String?
    let lowfloor: Bool?
}

struct FareZones: Codable {
    let zones: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let stringVal = try? container.decode(String.self) {
            self.zones = [stringVal]
        } else if let arrayVal = try? container.decode([String].self) {
            self.zones = arrayVal
        } else if let dict = try? container.decode([String: FareZones].self) {
            self.zones = dict.values.flatMap { $0.zones }
        } else {
            self.zones = []
        }
    }
}

/// B-API `/mobile/v1/trip/{trip_id}/`.
struct BApiTrip: Codable {
    let tripId: Int
    /// Seconds; nil until the vehicle runs.
    let tripDelay: Int?
    let stopTimes: [BApiStopTime]
}

struct BApiStopTime: Codable {
    let stopId: Int
    let stationId: Int?
    let stopGps: StopGps?
    let stopCode: String?
    let stopName: String
    /// Minutes after midnight of the trip's service day, Bratislava time; over 1440 after midnight.
    let arrival, departure: Int
    let zone: String?
}

/// Magic API `/timetable/shape`: a ride along the roads or tracks, one segment of [lat, lon] points from near each
/// stop to near the next; null where unknown.
struct TimetableShape: Codable {
    let segments: [[[Double]]?]

    /// The request for a ride of `line` through `stops`.
    static func endpoint(line: String, stops: [StopGps]) -> String? {
        var components = URLComponents()
        components.path = "/timetable/shape"
        components.queryItems = [
            URLQueryItem(name: "line", value: line),
            URLQueryItem(
                name: "stops", value: stops.map { String(format: "%.5f,%.5f", $0.lat, $0.lon) }.joined(separator: ";")
            ),
        ]
        // Servers read a query's "+" as a space.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.string
    }

    /// The ride through `stops`, the ones requested, with each known segment in place of the straight line between
    /// its two stops; straight throughout unless there is a segment for each two consecutive stops.
    func path(through stops: [StopGps]) -> [StopGps] {
        guard stops.count > 1, segments.count == stops.count - 1 else { return stops }
        var path = [StopGps]()
        for (index, segment) in segments.enumerated() {
            let points = segment?.compactMap { $0.count == 2 ? StopGps(lon: $0[1], lat: $0[0]) : nil } ?? []
            let piece = points.count > 1 ? points : [stops[index], stops[index + 1]]
            // A point where one piece ends and the next starts, as the stop between two straight lines, comes once.
            path += piece.first == path.last ? piece.dropFirst() : piece[...]
        }
        return path
    }
}
