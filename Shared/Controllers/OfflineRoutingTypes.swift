import Foundation

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
    let lat: Double
    let lon: Double
    let platform: String?
    let zone: String?

    var gps: StopGps { StopGps(lon: lon, lat: lat) }
}

struct OfflineTrip {
    /// "feed:trip_id"
    let key: String
    let routeShortName: String
    let routeType: Int
    let headsign: String
}

/// Trips that serve the same stop sequence, earliest first, none overtaking another,
/// so a route scan can board the first catchable trip and ride it to every later stop.
struct OfflineRoute {
    /// Stop indices in visiting order.
    let stops: [Int32]
    /// Trip indices, earliest first.
    let trips: [Int32]
    /// Service-day seconds, one row of `stops.count` per trip.
    let departures: [Int32]
    let arrivals: [Int32]
}

struct OfflineRouteStop {
    let route: Int32
    let position: Int32
}

struct OfflineFootpath {
    let stop: Int32
    let seconds: Int32
}

/// One ride of a journey; times are service-day seconds.
struct OfflineRide: Hashable {
    let tripKey: String
    let boardStopId: String
    let alightStopId: String
    let boardTime: Int
    let alightTime: Int
}

struct OfflineJourneyCandidate {
    let rides: [OfflineRide]
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
