import Foundation

enum OfflineRoutingMode {
    case departure
    case arrival
}

enum OfflineWalk {
    /// Effective speed in m/s over straight-line distance. Real paths detour
    /// around blocks and climb hills, so this is deliberately slower than an
    /// actual walking pace applied to a routed path.
    static let metersPerSecond = 0.9
    static let minimumSeconds = 60

    static func seconds(forMeters meters: Double) -> Int {
        max(minimumSeconds, Int(meters / metersPerSecond))
    }
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

    var gps: StopGps { StopGps(lon: lon, lat: lat) }
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
    let boardingCapKey: String
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
