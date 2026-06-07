import Foundation

enum OfflineRoutingMode {
    case departure
    case arrival
}

struct OfflineStop: Hashable {
    let id: String
    let feed: String
    let name: String
    let normalizedName: String
    let lat: Double
    let lon: Double
    let platform: String?
    let zone: String?
}

struct OfflineStopTime {
    let tripKey: String
    let stopId: String
    let sequence: Int
    let arrival: Int
    let departure: Int
}

struct OfflineTrip {
    let key: String
    let id: String
    let feed: String
    let routeShortName: String
    let routeType: Int
    let headsign: String
    let serviceId: String
    let stopTimes: [OfflineStopTime]
}

struct OfflineWalkLink: Hashable {
    let fromStopId: String
    let toStopId: String
    let seconds: Int
}

struct OfflineRoutingLabel: Hashable {
    let stopId: String
    let time: Int
    let transfers: Int
    let walkSeconds: Int
    let previousIndex: Int?
    let tripKey: String?
    let boardStopId: String?
    let alightStopId: String?
    let boardTime: Int?
    let alightTime: Int?
    let walkLink: OfflineWalkLink?
}

struct OfflineJourneyCandidate {
    let labels: [OfflineRoutingLabel]
    let parts: [Part]
    let zones: Set<String>
    let arrivalSeconds: Int
    let departureSeconds: Int
    let transferCount: Int
    let walkSeconds: Int
}

struct OfflineGroupedJourney {
    let representative: OfflineJourneyCandidate
    let alternatives: [OfflineJourneyCandidate]
}
