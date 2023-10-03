//
//  StopGps.swift
//  Transi
//
//  Created by magic_sk on 09/05/2023.
//

import Foundation

struct StopGps: Codable, Hashable {
    let lon, lat: Double
    static let example = StopGps(lon: 17.208740234375, lat: 48.1357383728027)
}
