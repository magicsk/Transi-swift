//
//  Timetables.swift
//  Transi
//
//  Created by magic_sk on 17/12/2023.
//

import Foundation

struct CategorizedTimetables: Codable, Hashable {
    var trams = [Route]()
    var trolleybuses = [Route]()
    var buses = [Route]()
    var nightlines = [Route]()
    var trains = [Route]()
    var regionalbuses = [Route]()
    
    mutating func clear() {
        trams.removeAll()
        trolleybuses.removeAll()
        buses.removeAll()
        nightlines.removeAll()
        trains.removeAll()
        regionalbuses.removeAll()
    }
}

struct Timetables: Codable, Hashable {
    var routes: [Route]
}

struct Route: Codable, Hashable, Identifiable {
    var id: Int { routeId }
    private var routeId: Int
    var shortName: String
    var longName: String
    var description: String?
    var routeType: Int
    var color: String?
    var textColor: String?

    init(routeId: Int, shortName: String, longName: String, description: String? = nil, routeType: Int, color: String? = nil, textColor: String? = nil) {
        self.routeId = routeId
        self.shortName = shortName
        self.longName = longName
        self.description = description
        self.routeType = routeType
        self.color = color
        self.textColor = textColor
    }

    static let empty = Route(routeId: 0, shortName: "", longName: "", routeType: 0)
}

struct Directions: Codable, Hashable {
    var all: [Direction] { directions }
    private var directions: [Direction]
}

struct Direction: Codable, Hashable, Identifiable {
    var id: Int { directionId }
    var name: String { direction }
    private var directionId: Int
    private var direction: String

    init(directionId: Int, direction: String) {
        self.directionId = directionId
        self.direction = direction
    }

    static let initial = Direction(directionId: 0, direction: "Error")
}

struct Departures: Codable, Hashable {
    var all: [Departure] { departures }
    private var departures: [Departure]
}

struct Departure: Codable, Hashable, Identifiable {
    var id: Int { tripId }
    var flags: Int { tripFlags }
    var headsign: String { tripHeadsign }
    private var tripId: Int
    private var tripFlags: Int
    private var tripHeadsign: String
    var departure: Int
    var routeType: Int
    var externalId: String
    var directionDepartures: [DirectionDeparture]

    init(tripId: Int, tripFlags: Int, tripHeadsign: String, departure: Int, routeType: Int, externalId: String, directionDepartures: [DirectionDeparture]) {
        self.tripId = tripId
        self.tripFlags = tripFlags
        self.tripHeadsign = tripHeadsign
        self.departure = departure
        self.routeType = routeType
        self.externalId = externalId
        self.directionDepartures = directionDepartures
    }

    static let initial = Departure(tripId: 0, tripFlags: 0, tripHeadsign: "Error", departure: 0, routeType: 0, externalId: "", directionDepartures: [])
}

struct DirectionDeparture: Codable, Hashable, Identifiable {
    var id: Int { stationId }
    var name: String { stationName }
    private var stationId: Int
    private var stationName: String
    var departure: Int
    var stopId: Int?
    var stopCode: String?

    init(stationId: Int, stationName: String, departure: Int, stopId: Int? = nil, stopCode: String? = nil) {
        self.stationId = stationId
        self.stationName = stationName
        self.departure = departure
        self.stopId = stopId
        self.stopCode = stopCode
    }
}

struct TimetableDetails: Codable, Hashable {
    var all: [TimetableDetail] { departures }
    private var departures: [TimetableDetail]
}

struct TimetableDetail: Codable, Hashable {
    var t: Int
    var tripId: Int
    var tripFlags: Int?
    var tripShortName: String?
    var tripHeadsign: String?
    var routeShortName: String?
    var routeType: Int?
    var externalId: String?
    var groupNotes: [GroupNote]?
    var tripDelay: Int?
    var lastStation: String?
    var lastStationId: Int?
    var lastStopId: Int?
    var lastStopCode: String?
}

struct GroupNote: Codable, Hashable {
    var priority: Int
    var mark: String
    var note: String?
}

struct HourMinute: Codable, Hashable, Identifiable {
    var id = UUID()
    var hour: Int
    var minutes: [String]
    
    static let hoursList = [4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,0,1,2,3]
}

