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
    var stopId: Int
    var busID: String
    var headsign: String
    var departureTime: String
    var departureTimeRaw: TimeInterval
    var departureTimeRemaining: String
    var departureTimeRemainingShortened: String
    var delay: Int
    var delayText: String
    var type: String
    var currentStopId: Int
    var lastStopId: Int
    var lastStopName: String
    var stuck: Bool
    var expanded: Bool = false

    static let example = Tab(id: 1, line: "72", platform: 099, stopId: 82, busID: "1:2552", headsign: "Čiližská", departureTime: "22:30", departureTimeRaw: TimeInterval(1680959460000), departureTimeRemaining: "now", departureTimeRemainingShortened: "now", delay: 23, delayText: "23 minutes delay", type: "online", currentStopId: 12, lastStopId: 12, lastStopName: "Cintorín Vrakuňa", stuck: false)
    static let example2 = Tab(id: 2, line: "71", platform: 099, stopId: 82, busID: "1:6722", headsign: "Hlavná stanica", departureTime: "22:36", departureTimeRaw: TimeInterval(1680959470000), departureTimeRemaining: "2 min", departureTimeRemainingShortened: "2m", delay: 0, delayText: "on time", type: "online", currentStopId: 0, lastStopId: 0, lastStopName: "none", stuck: true)
    static let example3 = Tab(id: 3, line: "736", platform: 099, stopId: 82, busID: "1:2552", headsign: "Bratislava, Autobusová stanica", departureTime: "22:40", departureTimeRaw: TimeInterval(1680959480000), departureTimeRemaining: "~17 min", departureTimeRemainingShortened: "17m", delay: 0, delayText: "offline", type: "offline", currentStopId: 0, lastStopId: 0, lastStopName: "none", stuck: true)
    static let empty = Tab(id: -1, line: "", platform: -1, stopId: -1, busID: "", headsign: "", departureTime: "", departureTimeRaw: TimeInterval(1000000000000000), departureTimeRemaining: "", departureTimeRemainingShortened: "", delay: -1, delayText: "", type: "", currentStopId: -1, lastStopId: -1, lastStopName: "", stuck: false)
}

extension Tab {
    init?(json: [String: Any], platform: Int, stopId: Int, expanded: Bool = false) {
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

        self.id = id
        self.line = line
        self.platform = platform
        self.stopId = stopId
        self.busID = busID
        self.headsign = headsign
        self.departureTime = departureTime
        self.departureTimeRaw = departureTimeRaw
        self.departureTimeRemaining = getDepartureTimeRemainingText(departureTime, departureTimeRaw, type)
        self.departureTimeRemainingShortened = getShortDepartureTimeRemainingText(departureTime, departureTimeRaw, type)
        self.delay = delay
        self.type = type
        self.currentStopId = currentStopId
        self.lastStopId = lastStopId
        self.lastStopName = lastStopName.replacingOccurrences(of: "Bratislava, ", with: "")
        self.stuck = stuck
        self.delayText = getDelayText(delay, type)
        self.expanded = expanded
    }
}

func getDelayText(_ delay: Int, _ type: String) -> String {
    if type != "online" {
        return "offline"
    }
    let isDelay = delay > 0
    let isInAdvance = delay < 0
    if isDelay {
        return "\(delay) min delay"
    } else if isInAdvance {
        let advance = delay * -1
        return "\(advance) min in advance"
    } else {
        return "no delay"
    }
}

func getDepartureTimeRemainingText(_ departureTime: String, _ departureTimeRaw: TimeInterval, _ type: String) -> String {
    let departureTimeRemainingRaw = Int(departureTimeRaw - Date().timeIntervalSince1970)
    let timeInMins = departureTimeRemainingRaw / 60
    let departureTimeRemaining = departureTimeRemainingRaw > 59 ?
        timeInMins > 59 ?
        departureTime :
        "\(timeInMins) min" :
        departureTimeRemainingRaw > 0 ? "<1 min" : "now"

    if type != "online" {
        return "~\(departureTimeRemaining)"
    }
    return departureTimeRemaining
}

func getShortDepartureTimeRemainingText(_ departureTime: String, _ departureTimeRaw: TimeInterval, _ type: String) -> String {
    let departureTimeRemainingRaw = Int(departureTimeRaw - Date().timeIntervalSince1970)
    let timeInMins = departureTimeRemainingRaw / 60
    let shortenedFullTime = ":" + (departureTime.components(separatedBy: ":").last ?? "?")
    return departureTimeRemainingRaw > 59 ?
        timeInMins > 59 ?
        shortenedFullTime :
        "\(timeInMins)m" :
        departureTimeRemainingRaw > 0 ? "<1" : "now"
}
