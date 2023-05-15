//
//  Journey.swift
//  Transi
//
//  Created by magic_sk on 09/05/2023.
//

import Foundation

struct Trip: Codable, Hashable {
    var journey: [Journey]?
}

struct Journey: Codable, Hashable {
    var parts: [Part]?
    var zones: [Int]?
    var ticketID: Int?
}

struct Part: Codable, Hashable {
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
