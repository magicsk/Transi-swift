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
    var departureTime: TimeInterval
    var delay: Int
    var delayText: String?
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
        let departureTime = (json["cas"] as? Double ?? 0) / 1000.0
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
        self.lastStopName = lastStopName.replacingOccurrences(of: "Bratislava, ", with: "")
        self.stuck = stuck
        self.expanded = false
        self.delayText = getDelayText(delay: self.delay)
    }
    
    
    func getDelayText(delay: Int) -> String? {
        let isDelay = delay > 0
        let isInAdvance = delay < 0
        if (isDelay) {
            return "\(delay) min delay"
        } else if (isInAdvance) {
            let advance = delay * -1
            return "\(advance) min in advance"
        } else {
            return nil
        }
    }
}
