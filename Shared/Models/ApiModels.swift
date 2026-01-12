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

struct RApiJourney: Codable {
    var journeyGuid: String
    var parts: [RApiPart]?
    var zones: [Int]?
    var ticketID: Int?
}

struct RApiPart: Codable {
    var startStopID, endStopID: Int?
    var startStopName, startStopCode, endStopName, endStopCode: String?
    var startStationID, endStationID: Int?
    var startStopGps, endStopGps: StopGps?
    var startDeparture, endArrival: String?
    var duration, routeType, tripID, tripRouteID: Int?
    var tripHeadsign, tripShortName, routeShortName: String?
    var tripZones: [Int]?
    var tripDelay, ticketID: Int?
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
