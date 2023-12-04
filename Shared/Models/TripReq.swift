//
//  Stops.swift
//  Transi
//
//  Created by magic_sk on 15/01/2023.
//

import Foundation
import CoreLocation

struct TripReq: Codable, Hashable {
    var org_id = 120
    var max_walk_duration = 15
    var search_from_hours = 2
    var search_to_hours = 2
    var max_transfers = 3
    var from_station_id, to_station_id: [Int]
}
