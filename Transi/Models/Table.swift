//
//  Table.swift
//  Transi
//
//  Created by magic_sk on 13/11/2022.
//

import Foundation

struct Tab: Codable, Identifiable, Hashable {
    var id: Int
    var line: String
    var platform: Int
    var busID: String
    var headsign: String
    var departureTime: Int
    var delay: Int
    var type: String
    var currentStopId: Int
    var lastStopId: Int
    var lastStopName: String
    var stuck: Bool
    var expanded: Bool
}

extension Tab {
    init?(json: [String: Any], platform: Int) {
        let id = json["i"] as? Int ?? 0
        let line = json["linka"] as? String ?? "Error"
        let busID = json["issi"] as? String ?? "Offline"
        let headsign = json["cielStr"] as? String ?? json["konecnaZstr"] as? String ?? "Error"
        let departureTime = (json["cas"] as? Int ?? 0) / 1000
        let delay = json["casDelta"] as? Int ?? 0
        let type = json["typ"] as? String ?? "cp"
        let currentStopId = json["tuZidx"] as? Int ?? -1
        let lastStopId = json["predoslaZidx"] as? Int ?? -1
        let lastStopName = json["predoslaZstr"] as? String ?? "none"
        let stuck = json["uviaznute"] as? Bool ?? false

        self.id = id
        self.line = line
        self.platform = platform
        self.busID = busID
        self.headsign = headsign
        self.departureTime = departureTime
        self.delay = delay
        self.type = type
        self.currentStopId = currentStopId
        self.lastStopId = lastStopId
        self.lastStopName = lastStopName
        self.stuck = stuck
        self.expanded = false
    }
}
