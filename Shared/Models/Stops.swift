//
//  Stops.swift
//  Transi
//
//  Created by magic_sk on 15/01/2023.
//

import CoreLocation
import Foundation

struct Stop: Codable, Identifiable, Hashable {
    var id, stationId: Int?
    var name, city: String?
    var type: String?
    var tripsCount: Int?
    var lat, lng: Double?
    var platformLabels: [PlatformLabel]?
    var score: Double?
    var location: CLLocation {
        return CLLocation(latitude: self.lat ?? 0, longitude: self.lng ?? 0)
    }

    static let example = Stop(id: 94)
    static let actualLocation = Stop(id: -1, stationId: -1, name: "Actual location", type: "location")

    func distance(to location: CLLocation) -> CLLocationDistance {
        return location.distance(from: self.location)
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
