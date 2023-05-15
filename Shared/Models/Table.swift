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
    var departureTime: String
    var departureTimeRaw: TimeInterval
    var departureTimeRemaining: String
    var delay: Int
    var delayText: String
    var type: String
    var currentStopId: Int
    var lastStopId: Int
    var lastStopName: String
    var stuck: Bool
    static let example = Tab(id: 1, line: "72", platform: 099, busID: "1:2552", headsign: "Čiližská", departureTime: "22:30", departureTimeRaw: TimeInterval(1680959460000), departureTimeRemaining: "1 min", delay: 23, delayText: "with 23 minutes delay", type: "online", currentStopId: 12, lastStopId: 12, lastStopName: "Cintorín Vrakuňa", stuck: true)
}


extension Tab {
    init?(json: [String: Any], platform: Int) {
        let id = json["i"] as? Int ?? 0
        let line = json["linka"] as? String ?? "Error"
        let busID = json["issi"] as? String ?? "Offline"
        let headsign = json["cielStr"] as? String ?? json["konecnaZstr"] as? String ?? "Error"
        let departureTimeRaw = (json["cas"] as? Double ?? 0) / 1000.0
        let delay = json["casDelta"] as? Int ?? 0
        let type = json["typ"] as? String ?? "cp"
        let currentStopId = json["tuZidx"] as? Int ?? -1
        let lastStopId = json["predoslaZidx"] as? Int ?? -1
        let lastStopName = json["predoslaZstr"] as? String ?? "none"
        let stuck = json["uviaznute"] as? Bool ?? false
        
        let departureTime = Date(timeIntervalSince1970: TimeInterval(departureTimeRaw)).formatted(date: .omitted, time: .shortened)
        let departureTimeRemainingRaw = Int(departureTimeRaw - Date().timeIntervalSince1970)
        let timeInMins = departureTimeRemainingRaw / 60
        var departureTimeRemaining = departureTimeRemainingRaw > 59 ?
        timeInMins > 59 ?
        departureTime :
        "\(timeInMins) min" :
        departureTimeRemainingRaw > 0 ? "<1 min" : "now"
        
        if (type != "online") {
            departureTimeRemaining = "~\(departureTimeRemaining)"
        }

        self.id = id
        self.line = line
        self.platform = platform
        self.busID = busID
        self.headsign = headsign
        self.departureTime = departureTime
        self.departureTimeRaw = departureTimeRaw
        self.departureTimeRemaining = departureTimeRemaining
        self.delay = delay
        self.type = type
        self.currentStopId = currentStopId
        self.lastStopId = lastStopId
        self.lastStopName = lastStopName.replacingOccurrences(of: "Bratislava, ", with: "")
        self.stuck = stuck
        self.delayText = getDelayText(delay)
    }
}

func getDelayText(_ delay: Int) -> String {
    
    let isDelay = delay > 0
    let isInAdvance = delay < 0
    let delayMinutes = (delay > 1 || delay < -1) ? "minutes" : "minute"
    if (isDelay) {
        return "with \(delay) \(delayMinutes) of delay"
    } else if (isInAdvance) {
        let advance = delay * -1
        return "\(advance) \(delayMinutes) in advance"
    } else {
        return "with no delay"
    }
}
