//
//  Stops.swift
//  Transi
//
//  Created by magic_sk on 15/01/2023.
//

import Foundation
import CoreLocation

struct TripReq: Codable, Hashable {
    var org_id, max_walk_duration, search_from_hours, search_to_hours, max_transfers: Int
    var from_station_id, to_station_id: [Int]
    var search_from: String?
}
