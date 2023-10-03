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
    static let example = Journey(parts: [Part.example], zones: [1955, 1953], ticketID: 606)
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
    static let example = Part(startStopID: 900, endStopID: 801, startStopName: "Hronská", startStopCode: "A", endStopName: "Pažítková", endStopCode: "A", startStationID: 1386, endStationID: 1341, startStopGps: StopGps(lon: 17.208740234375, lat: 48.1357383728027), endStopGps: StopGps(lon: 17.15305519104, lat: 48.1494674682617), startDeparture: "2023-10-03T14:41:00.000Z", endArrival: "2023-10-03T14:52:00.000Z", duration: 11, routeType: 50, tripID: 11799, tripRouteID: 47, tripHeadsign: "Hlavná stanica", tripShortName: "", routeShortName: "71", tripZones: [1955, 1953], tripDelay: nil, ticketID: 604)
}
