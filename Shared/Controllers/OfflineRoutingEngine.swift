import Foundation

class OfflineRoutingEngine {
    /// Departure searches find the journeys leaving within this window after the requested time,
    /// arrive-by searches those arriving within it before. The next page starts where it ended.
    static let searchWindowSeconds = 60 * 60
    /// A window with fewer journeys than this is doubled, up to `maxSearchWindowSeconds`.
    private static let minimumWindowJourneyCount = 3
    static let maxSearchWindowSeconds = 8 * 60 * 60
    /// Arrive-by searches also try departures this long before the window, so journeys that take
    /// up to this long still arrive in it.
    private static let maxArriveByJourneySeconds = 2 * 60 * 60
    /// The previous service day's trips run past midnight until about this time.
    private static let earlyMorningSearchThresholdSeconds = 5 * 60 * 60
    private static let secondsPerDay = 24 * 60 * 60
    /// A query needs at most the previous, requested and next service day.
    private static let contextCacheLimit = 3
    private static let contextCacheLock = NSLock()
    /// Least recently used first.
    private static var contextCache = [(key: ContextCacheKey, context: OfflineRoutingContext)]()

    let scheduleDb: SQLiteDatabase
    let baseDb: SQLiteDatabase

    init(scheduleDb: SQLiteDatabase, baseDb: SQLiteDatabase) {
        self.scheduleDb = scheduleDb
        self.baseDb = baseDb
    }

    func planTrip(
        fromName: String,
        toName: String,
        date: Date,
        arrivalDeparture: ArrivalDeparture,
        maxTransfers: Int,
        maxWalkDuration: Int,
        imhdStops: [Stop]
    ) -> [Journey] {
        let resolver = OfflineStopResolver(baseDb: baseDb)
        let fromStopIds = resolver.resolveStops(named: fromName).map(\.id)
        let toStopIds = resolver.resolveStops(named: toName).map(\.id)
        guard !fromStopIds.isEmpty, !toStopIds.isEmpty else { return [] }

        var window = Self.searchWindowSeconds
        var candidates = [OfflineJourneyCandidate]()
        while true {
            candidates = search(
                fromStopIds: fromStopIds,
                toStopIds: toStopIds,
                date: date,
                window: window,
                arrivalDeparture: arrivalDeparture,
                maxTransfers: maxTransfers,
                maxWalkDuration: maxWalkDuration
            )
            if candidates.count >= Self.minimumWindowJourneyCount || window >= Self.maxSearchWindowSeconds { break }
            window *= 2
        }

        let representatives = OfflineJourneyGrouper()
            .group(candidates, mode: arrivalDeparture)
            .map(\.representative)
            .sorted { displaySort($0, $1, mode: arrivalDeparture) }
        let trips = tripStops(forTripKeys: Set(representatives.flatMap { $0.rides.map(\.tripKey) }))
        let imhdStopsByName = Dictionary(grouping: imhdStops.filter { $0.id > 0 }) { $0.name ?? "" }
        return representatives.map {
            Journey(
                id: "o-\(UUID().uuidString)",
                parts: partsWithStops($0, trips: trips, imhdStopsByName: imhdStopsByName),
                zones: Array($0.zones).sorted()
            )
        }
    }

    /// Journeys leaving in `[date, date + window)`, or arriving in `(date - window, date]`, with
    /// times relative to the requested day. Trips of the previous service day run past midnight,
    /// and the next day's start inside a window that crosses it.
    private func search(
        fromStopIds: [String],
        toStopIds: [String],
        date: Date,
        window: Int,
        arrivalDeparture: ArrivalDeparture,
        maxTransfers: Int,
        maxWalkDuration: Int
    ) -> [OfflineJourneyCandidate] {
        let dayStart = Self.bratislavaCalendar.startOfDay(for: date)
        let seconds = localServiceDaySeconds(for: date)
        let departures: ClosedRange<Int>
        let latestArrival: Int?
        switch arrivalDeparture {
        case .departure:
            departures = seconds...(seconds + window - 1)
            latestArrival = nil
        case .arrival:
            departures = (seconds - window - Self.maxArriveByJourneySeconds)...seconds
            latestArrival = seconds
        }

        var candidates = [OfflineJourneyCandidate]()
        for dayOffset in -1...1 {
            if dayOffset == -1 && departures.lowerBound >= Self.earlyMorningSearchThresholdSeconds { continue }
            if dayOffset == 1 && departures.upperBound < Self.secondsPerDay { continue }
            let shift = -dayOffset * Self.secondsPerDay
            let serviceDate = Self.bratislavaCalendar.date(byAdding: .day, value: dayOffset, to: dayStart)!
            let router = OfflineTimetableRouter(context: routingContext(date: serviceDate, maxWalkDuration: maxWalkDuration))
            candidates += router.route(
                originStopIds: fromStopIds,
                destinationStopIds: toStopIds,
                departures: (departures.lowerBound + shift)...(departures.upperBound + shift),
                latestArrival: latestArrival.map { $0 + shift },
                maxTransfers: maxTransfers
            )
        }
        candidates = normalize(candidates, relativeTo: dayStart)
        if arrivalDeparture == .arrival {
            // Earlier arrivals belong to the next page.
            candidates = candidates.filter { $0.arrivalSeconds > seconds - window }
        }
        return candidates
    }

    private struct TripStop {
        let stopId: String
        /// Service-day seconds, like the router's ride times.
        let arrival: Int
        let departure: Int
        let name: String
        let platform: String?
        let gps: StopGps
        let zone: String?
        let isRequestStop: Bool
    }

    private struct TripStops {
        var stops = [TripStop]()
        var lowFloor: Bool?
    }

    /// Every stop of the given trips, in order, from one query. Keys match `OfflineTrip.key`.
    private func tripStops(forTripKeys tripKeys: Set<String>) -> [String: TripStops] {
        var tripIdsByFeed = [String: [String]]()
        for key in tripKeys {
            let feedAndId = key.split(separator: ":", maxSplits: 1)
            guard feedAndId.count == 2 else { continue }
            tripIdsByFeed[String(feedAndId[0]), default: []].append(String(feedAndId[1]))
        }
        guard !tripIdsByFeed.isEmpty else { return [:] }
        var clauses = [String]()
        var params = [Any]()
        for (feed, tripIds) in tripIdsByFeed {
            clauses.append("(st.feed = ? AND st.trip_id IN (\(tripIds.map { _ in "?" }.joined(separator: ","))))")
            params.append(feed)
            params.append(contentsOf: tripIds)
        }
        let rows = scheduleDb.query("""
            SELECT st.feed, st.trip_id, st.stop_id, st.departure_time,
                   \(OfflineRoutingContext.arrivalTimeColumn(scheduleDb: scheduleDb)) AS arrival_time, st.pickup_type, st.drop_off_type,
                   t.wheelchair_accessible, s.stop_name, s.stop_lat, s.stop_lon, s.platform_code, s.zone_id
            FROM stop_times st
            JOIN trips t ON t.trip_id = st.trip_id AND t.feed = st.feed
            JOIN base.stops s ON s.stop_id = st.stop_id AND s.feed = st.feed
            WHERE \(clauses.joined(separator: " OR "))
            ORDER BY st.feed, st.trip_id, st.stop_sequence
        """, params: params)

        var result = [String: TripStops]()
        for row in rows {
            guard let feed = row["feed"] as? String,
                  let tripId = row["trip_id"] as? String,
                  let stopId = row["stop_id"] as? String,
                  let departure = row["departure_time"] as? Int,
                  let arrival = row["arrival_time"] as? Int,
                  let name = row["stop_name"] as? String,
                  let lat = row["stop_lat"] as? Double,
                  let lon = row["stop_lon"] as? Double else { continue }
            let key = "\(feed):\(tripId)"
            // The feed writes "-" for stops without a zone.
            let zone = (row["zone_id"] as? String).flatMap { $0.isEmpty || $0 == "-" ? nil : $0 }
            result[key, default: TripStops()].stops.append(TripStop(
                stopId: stopId,
                arrival: arrival,
                departure: departure,
                name: name,
                platform: row["platform_code"] as? String,
                gps: StopGps(lon: lon, lat: lat),
                zone: zone,
                isRequestStop: row["pickup_type"] as? Int == 3 || row["drop_off_type"] as? Int == 3
            ))
            // GTFS wheelchair_accessible: 1 accessible, 2 not, anything else unknown.
            switch row["wheelchair_accessible"] as? Int {
            case 1: result[key]?.lowFloor = true
            case 2: result[key]?.lowFloor = false
            default: break
            }
        }
        return result
    }

    /// The candidate's parts with every transit leg's stops, from boarding to alighting, and its low-floor flag.
    private func partsWithStops(
        _ candidate: OfflineJourneyCandidate,
        trips: [String: TripStops],
        imhdStopsByName: [String: [Stop]]
    ) -> [Part] {
        var parts = candidate.parts
        // The router builds one transit part per ride, in ride order.
        let transitIndices = parts.indices.filter { parts[$0].routeType != 64 }
        guard candidate.rides.count == transitIndices.count else { return parts }

        for (ride, index) in zip(candidate.rides, transitIndices) {
            guard let trip = trips[ride.tripKey],
                  let board = trip.stops.firstIndex(where: { $0.stopId == ride.boardStopId && $0.departure == ride.boardTime }),
                  let alight = trip.stops[(board + 1)...].firstIndex(where: {
                      $0.stopId == ride.alightStopId && $0.arrival == ride.alightTime
                  }) else { continue }
            let boardDeparture = parts[index].startDeparture
            parts[index].lowFloor = trip.lowFloor
            parts[index].stops = trip.stops[board...alight].indices.map { stopIndex in
                let stop = trip.stops[stopIndex]
                // Show when the trip leaves each stop, and when it arrives at the last one.
                let seconds = stopIndex == alight ? stop.arrival : stop.departure
                return PartStop(
                    name: stop.name,
                    platform: stop.platform,
                    // Offsets from the boarding time keep the router's service day, also past midnight.
                    time: boardDeparture.addingTimeInterval(TimeInterval(seconds - ride.boardTime)),
                    gps: stop.gps,
                    zone: stop.zone,
                    isRequestStop: stop.isRequestStop,
                    stopId: imhdStopId(name: stop.name, platform: stop.platform, in: imhdStopsByName)
                )
            }
        }
        return parts
    }

    /// The imhd stop with that name, preferring one with the platform letter. Regional stops
    /// in the city carry a "Bratislava, " prefix the imhd names do not have.
    private func imhdStopId(name: String, platform: String?, in stopsByName: [String: [Stop]]) -> Int? {
        let stops = stopsByName[name] ?? stopsByName[name.replacingOccurrences(of: "Bratislava, ", with: "")] ?? []
        return (stops.first { $0.platformLabels?.contains { $0.label == platform } == true } ?? stops.first)?.id
    }

    private struct ContextCacheKey: Hashable {
        let schedule: SQLiteDatabaseFingerprint
        let base: SQLiteDatabaseFingerprint
        let serviceDay: TimeInterval
        let maxWalkDuration: Int
    }

    private func routingContext(date: Date, maxWalkDuration: Int) -> OfflineRoutingContext {
        let key = ContextCacheKey(
            schedule: scheduleDb.fingerprint,
            base: baseDb.fingerprint,
            serviceDay: Self.bratislavaCalendar.startOfDay(for: date).timeIntervalSince1970,
            maxWalkDuration: maxWalkDuration
        )

        Self.contextCacheLock.lock()
        if let index = Self.contextCache.firstIndex(where: { $0.key == key }) {
            let entry = Self.contextCache.remove(at: index)
            Self.contextCache.append(entry)
            Self.contextCacheLock.unlock()
            return entry.context
        }
        Self.contextCacheLock.unlock()

        let context = OfflineRoutingContext.build(
            scheduleDb: scheduleDb,
            baseDb: baseDb,
            date: date,
            maxWalkDuration: maxWalkDuration
        )

        Self.contextCacheLock.lock()
        Self.contextCache.removeAll { $0.key == key }
        Self.contextCache.append((key, context))
        if Self.contextCache.count > Self.contextCacheLimit {
            Self.contextCache.removeFirst()
        }
        Self.contextCacheLock.unlock()

        return context
    }

    private func normalize(
        _ candidates: [OfflineJourneyCandidate],
        relativeTo dayStart: Date
    ) -> [OfflineJourneyCandidate] {
        candidates.map { candidate in
            guard let first = candidate.parts.first, let last = candidate.parts.last else {
                return candidate
            }
            return OfflineJourneyCandidate(
                rides: candidate.rides,
                parts: candidate.parts,
                zones: candidate.zones,
                arrivalSeconds: Int(last.endArrival.timeIntervalSince(dayStart)),
                departureSeconds: Int(first.startDeparture.timeIntervalSince(dayStart)),
                transferCount: candidate.transferCount,
                walkSeconds: candidate.walkSeconds
            )
        }
    }

    private func displaySort(
        _ lhs: OfflineJourneyCandidate,
        _ rhs: OfflineJourneyCandidate,
        mode: ArrivalDeparture
    ) -> Bool {
        switch mode {
        case .departure:
            if lhs.departureSeconds != rhs.departureSeconds { return lhs.departureSeconds < rhs.departureSeconds }
            return qualitySort(lhs, rhs, mode: mode)
        case .arrival:
            if lhs.arrivalSeconds != rhs.arrivalSeconds { return lhs.arrivalSeconds > rhs.arrivalSeconds }
            return qualitySort(lhs, rhs, mode: mode)
        }
    }

    private func qualitySort(
        _ lhs: OfflineJourneyCandidate,
        _ rhs: OfflineJourneyCandidate,
        mode: ArrivalDeparture
    ) -> Bool {
        let lhsDuration = lhs.arrivalSeconds - lhs.departureSeconds
        let rhsDuration = rhs.arrivalSeconds - rhs.departureSeconds
        if lhsDuration != rhsDuration { return lhsDuration < rhsDuration }
        if lhs.transferCount != rhs.transferCount { return lhs.transferCount < rhs.transferCount }
        if lhs.walkSeconds != rhs.walkSeconds { return lhs.walkSeconds < rhs.walkSeconds }
        switch mode {
        case .departure:
            return lhs.arrivalSeconds < rhs.arrivalSeconds
        case .arrival:
            return lhs.departureSeconds > rhs.departureSeconds
        }
    }

    private func localServiceDaySeconds(for date: Date) -> Int {
        let components = Self.bratislavaCalendar.dateComponents([.hour, .minute, .second], from: date)
        return (components.hour ?? 0) * 3600 +
            (components.minute ?? 0) * 60 +
            (components.second ?? 0)
    }

    private static var bratislavaCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Bratislava")!
        return calendar
    }
}
