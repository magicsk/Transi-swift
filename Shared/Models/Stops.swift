//
//  Stops.swift
//  Transi
//
//  Created by magic_sk on 15/01/2023.
//

import CoreLocation
import Foundation

struct Stop: Codable, Identifiable, Hashable {
    var id: Int
    var stationId: Int?
    var name, city: String?
    var type: String?
    var tripsCount: Int?
    var lat, lng: Double?
    var platformLabels: [PlatformLabel]?
    var score: Double?
    var location: CLLocationCoordinate2D {
        return CLLocationCoordinate2D(latitude: self.lat ?? 0, longitude: self.lng ?? 0)
    }
    var normalizedName: String {
        return self.name?.normalize() ?? ""
    }

    static let example = Stop(id: 94, stationId: 1386, name: "Hronská", platformLabels: [PlatformLabel(id: "240", label: "A"), PlatformLabel(id: "241", label: "B")])
    static let empty = Stop(id: 0)
    static let actualLocation = Stop(id: -1, stationId: -1, name: "Actual location", type: "location")

    func distance(to location: CLLocationCoordinate2D) -> CLLocationDistance {
        return location.distance(to: self.location)
    }
}

struct PlatformLabel: Codable, Identifiable, Hashable {
    let id: String
    let label: String
    
    static let example = PlatformLabel(id: "300", label: "A")
}

struct StopsVersion: Codable, Hashable {
    let version: String
}
