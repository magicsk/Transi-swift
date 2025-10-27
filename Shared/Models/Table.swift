//
//  Table.swift
//  Transi
//
//  Created by magic_sk on 13/11/2022.
//

import Foundation

struct Connection: Codable, Identifiable, Hashable {
    var id: String
    var line: String
    var platform: Int
    var stopId: Int
    var busID: String
    var headsign: String
    var departureTimeCP: TimeInterval
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

    static let example = Connection(
        id: "1:099", line: "72", platform: 099, stopId: 82, busID: "1:2552", headsign: "Čiližská",
        departureTimeCP: TimeInterval(1_680_959_460_000), departureTime: "22:30",
        departureTimeRaw: TimeInterval(1_680_959_460_000), departureTimeRemaining: "now",
        departureTimeRemainingShortened: "now", delay: 23, delayText: "23 minutes delay",
        type: "online", currentStopId: 12, lastStopId: 12, lastStopName: "Cintorín Vrakuňa",
        stuck: false
    )
    static let example2 = Connection(
        id: "2:099", line: "71", platform: 099, stopId: 82, busID: "1:6722", headsign: "Hlavná stanica",
        departureTimeCP: TimeInterval(1_680_959_460_000), departureTime: "22:36",
        departureTimeRaw: TimeInterval(1_680_959_470_000), departureTimeRemaining: "2 min",
        departureTimeRemainingShortened: "2m", delay: 0, delayText: "on time", type: "online",
        currentStopId: 0, lastStopId: 0, lastStopName: "none", stuck: true
    )
    static let example3 = Connection(
        id: "3:099", line: "736", platform: 099, stopId: 82, busID: "1:2552",
        headsign: "Bratislava, Autobusová stanica", departureTimeCP: TimeInterval(1_680_959_460_000),
        departureTime: "22:40", departureTimeRaw: TimeInterval(1_680_959_480_000),
        departureTimeRemaining: "~17 min", departureTimeRemainingShortened: "17m", delay: 0,
        delayText: "offline", type: "offline", currentStopId: 0, lastStopId: 0, lastStopName: "none",
        stuck: true
    )
    static let empty = Connection(
        id: "-1:-1", line: "", platform: -1, stopId: -1, busID: "", headsign: "",
        departureTimeCP: TimeInterval(1_000_000_000_000_000), departureTime: "",
        departureTimeRaw: TimeInterval(1_000_000_000_000_000), departureTimeRemaining: "",
        departureTimeRemainingShortened: "", delay: -1, delayText: "", type: "", currentStopId: -1,
        lastStopId: -1, lastStopName: "", stuck: false
    )
}

extension Connection {
    init?(json: [String: Any], platform: Int, stopId: Int, expanded: Bool = false) {
        let id = "\(json["i"] as? Int ?? 0):\(platform)"
        let line = json["linka"] as? String ?? "Error"
        let busID = json["issi"] as? String ?? "Offline"
        let headsign = json["cielStr"] as? String ?? json["konecnaZstr"] as? String ?? "Error"
        let departureTimeCP = (json["casCP"] as? Double ?? 0) / 1000.0
        let departureTimeRaw = (json["cas"] as? Double ?? 0) / 1000.0
        let delay = json["casDelta"] as? Int ?? 0
        let type = json["typ"] as? String ?? "cp"
        let currentStopId = json["tuZidx"] as? Int ?? -1
        let lastStopId = json["predoslaZidx"] as? Int ?? -1
        let lastStopName = json["predoslaZstr"] as? String ?? "none"
        let stuck = json["uviaznute"] as? Bool ?? false

        let departureTime = Date(timeIntervalSince1970: TimeInterval(departureTimeRaw)).formatted(
            date: .omitted, time: .shortened
        )

        self.id = id
        self.line = line
        self.platform = platform
        self.stopId = stopId
        self.busID = busID
        self.headsign = headsign
        self.departureTimeCP = (departureTimeCP / 60.0).rounded() * 60.0
        self.departureTime = departureTime
        self.departureTimeRaw = departureTimeRaw
        departureTimeRemaining = getDepartureTimeRemainingText(
            departureTime, departureTimeRaw, type
        )
        departureTimeRemainingShortened = getShortDepartureTimeRemainingText(
            departureTime, departureTimeRaw, type
        )
        self.delay = delay
        self.type = type
        self.currentStopId = currentStopId
        self.lastStopId = lastStopId
        self.lastStopName = lastStopName.replacingOccurrences(of: "Bratislava, ", with: "")
        self.stuck = stuck
        delayText = getDelayText(delay, type)
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

func getDepartureTimeRemainingText(
    _ departureTime: String, _ departureTimeRaw: TimeInterval, _ type: String
) -> String {
    let departureTimeRemainingRaw = Int(departureTimeRaw - Date().timeIntervalSince1970)
    let timeInMins = departureTimeRemainingRaw / 60
    let departureTimeRemaining =
        departureTimeRemainingRaw > 59
            ? timeInMins > 59 ? departureTime : "\(timeInMins) min"
            : departureTimeRemainingRaw > 0 ? "<1 min" : "now"

    if type != "online" {
        return "~\(departureTimeRemaining)"
    }
    return departureTimeRemaining
}

func getShortDepartureTimeRemainingText(
    _ departureTime: String, _ departureTimeRaw: TimeInterval, _: String
) -> String {
    let departureTimeRemainingRaw = Int(departureTimeRaw - Date().timeIntervalSince1970)
    let timeInMins = departureTimeRemainingRaw / 60
    let shortenedFullTime = ":" + (departureTime.components(separatedBy: ":").last ?? "?")
    return departureTimeRemainingRaw > 59
        ? timeInMins > 59 ? shortenedFullTime : "\(timeInMins)m"
        : departureTimeRemainingRaw > 0 ? "<1" : "now"
}

struct RegionalConnectionsResponse: Codable {
    let current: [RegionalConnection]
}

struct RegionalConnection: Codable, Hashable {
    let tripId: Int
    let tripHeadsign: String
    let routeShortName: String
    let departure: Int
    let stopId: Int
    let stopCode: String?
    let tripDelay: Int?
    let lastStation: String?
    let lastStationId: Int?
}

extension Connection {
    init(from connection: RegionalConnection, for stop: Stop) {
        let calendar = Calendar.current
        let now = Date()
        let startOfToday = calendar.startOfDay(for: now)
        let delayMinutes = (connection.tripDelay ?? 0) / 60
        let departureDateCP =
            calendar.date(byAdding: .minute, value: connection.departure, to: startOfToday)
                ?? startOfToday
        let departureDate =
            calendar.date(byAdding: .minute, value: delayMinutes, to: departureDateCP) ?? startOfToday
        let departureTimeRaw = departureDate.timeIntervalSince1970
        let departureTime = departureDate.formatted(date: .omitted, time: .shortened)

        line = connection.routeShortName

        if let platformCode = connection.stopCode,
           let platform = stop.platformLabels?.first(where: { $0.label == platformCode })
        {
            self.platform = Int(platform.id) ?? -1
        } else {
            platform = -1
        }

        stopId = stop.id
        busID = "0:0"
        headsign = connection.tripHeadsign
        departureTimeCP = departureDateCP.timeIntervalSince1970
        id = "\(connection.tripId):\(connection.stopId):\(departureTimeCP)"
        self.departureTime = departureTime
        self.departureTimeRaw = departureTimeRaw
        delay = delayMinutes
        type = connection.tripDelay == nil ? "cp" : "online"

        departureTimeRemaining = getDepartureTimeRemainingText(
            departureTime, departureTimeRaw, type
        )
        departureTimeRemainingShortened = getShortDepartureTimeRemainingText(
            departureTime, departureTimeRaw, type
        )
        delayText = getDelayText(delayMinutes, type)

        currentStopId = -1
        lastStopId = connection.lastStationId ?? -1
        lastStopName = connection.lastStation ?? "none"
        stuck = false
        expanded = false
    }
}
