//
//  Stops.swift
//  Transi
//
//  Created by magic_sk on 15/01/2023.
//

import Foundation

struct Stop: Codable, Identifiable, Hashable {
    var id, stationID: Int?
    var name, city: String?
    var type: String?
    var tripsCount: Int?
    var lat, lng: Double?
    var platformLabels: [PlatformLabel]?
}


struct PlatformLabel: Codable, Identifiable, Hashable {
    let id: String
    let label: String
}
