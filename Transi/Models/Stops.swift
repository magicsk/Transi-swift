//
//  Stops.swift
//  Transi
//
//  Created by magic_sk on 15/01/2023.
//

import Foundation
import CoreLocation

struct Stop: Codable, Identifiable, Hashable {
    var id, stationID: Int?
    var name, city: String?
    var type: String?
    var tripsCount: Int?
    var lat, lng: Double?
    var platformLabels: [PlatformLabel]?
    var location: CLLocation {
        return CLLocation(latitude: self.lat ?? 0, longitude: self.lng ?? 0)
    }

    func distance(to location: CLLocation) -> CLLocationDistance {
        return location.distance(from: self.location)
    }
}


struct PlatformLabel: Codable, Identifiable, Hashable {
    let id: String
    let label: String
}
