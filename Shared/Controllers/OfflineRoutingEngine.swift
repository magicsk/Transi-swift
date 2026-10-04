import Foundation

class OfflineRoutingEngine {
    private static let overnightSearchThresholdSeconds = 21 * 60 * 60
    private static let earlyMorningSearchThresholdSeconds = 5 * 60 * 60
    private static let currentServiceDayPriorityThresholdSeconds = 4 * 60 * 60
    private static let previousServiceDayOnlyThresholdSeconds = 2 * 60 * 60
    private static let minimumEarlyMorningCandidateCount = 8
    private static let initialSearchWindowSeconds = 2 * 60 * 60
    private static let minimumWindowCandidateCount = 3
    private static let secondsPerDay = 24 * 60 * 60
    private static let contextCacheLimit = 8
    private static let contextCacheLock = NSLock()
    private static var contextCache = [ContextCacheKey: OfflineRoutingContext]()

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
        let fromStops = resolver.resolveStops(named: fromName, maxWalkDuration: maxWalkDuration)
        let toStops = resolver.resolveStops(named: toName, maxWalkDuration: maxWalkDuration)
        guard !fromStops.isEmpty, !toStops.isEmpty else { return [] }
        let directFromStops = resolver.resolveStops(named: fromName, maxWalkDuration: 0)
        let directToStops = resolver.resolveStops(named: toName, maxWalkDuration: 0)
        let originStopIds = endpointAnchorStopIds(
            directStops: directFromStops,
            resolvedStops: fromStops
        )
        let destinationStopIds = endpointAnchorStopIds(
            directStops: directToStops,
            resolvedStops: toStops
        )
        let seconds = localServiceDaySeconds(for: date)
        var candidates = [OfflineJourneyCandidate]()
        let searches = serviceDaySearches(for: date, seconds: seconds)

        for search in searches {
            let context = routingContext(date: search.serviceDate, maxWalkDuration: maxWalkDuration)
            let routeOriginStopIds = endpointCandidateStopIds(
                directStops: directFromStops,
                resolvedStops: fromStops,
                context: context
            )
            let originNeedsAnchorWalk = endpointNeedsAnchorWalk(
                directStops: directFromStops,
                resolvedStops: fromStops,
                context: context
            )
            let routeDestinationStopIds = endpointCandidateStopIds(
                directStops: arrivalDeparture == .arrival ? [] : directToStops,
                resolvedStops: toStops,
                context: context
            )
            let terminalWalkLinks = shouldUseTerminalWalkLinks(directDestinationStops: directToStops, context: context)
                ? terminalWalkLinksByStopId(
                    context: context,
                    destinationStopIds: destinationStopIds,
                    resolvedStops: toStops
                )
                : [:]
            candidates.append(contentsOf: route(
                context: context,
                originStopIds: originNeedsAnchorWalk ? originStopIds : routeOriginStopIds,
                destinationStopIds: destinationStopIds,
                routeDestinationStopIds: routeDestinationStopIds,
                terminalWalkLinksByStopId: terminalWalkLinks,
                seconds: search.seconds,
                isPreviousServiceDay: search.isPreviousServiceDay,
                arrivalDeparture: arrivalDeparture,
                maxTransfers: maxTransfers
            ))
            let validCandidateCount = filter(candidates, for: arrivalDeparture, requestedDate: date).count
            if search.isPreviousServiceDay && shouldUsePreviousServiceDayOnly(
                seconds: seconds,
                candidateCount: validCandidateCount
            ) {
                break
            }
            if !search.isPreviousServiceDay && shouldUseCurrentServiceDayOnly(
                seconds: seconds,
                candidateCount: validCandidateCount
            ) {
                break
            }
        }

        if arrivalDeparture == .departure {
            let validCandidateCount = filter(candidates, for: arrivalDeparture, requestedDate: date).count
            if shouldSearchNextServiceDay(departureSeconds: seconds, candidateCount: validCandidateCount) {
                let nextDate = nextServiceDate(after: Self.bratislavaCalendar.startOfDay(for: date))
                let nextContext = routingContext(date: nextDate, maxWalkDuration: maxWalkDuration)
                let nextRouteOriginStopIds = endpointCandidateStopIds(
                    directStops: directFromStops,
                    resolvedStops: fromStops,
                    context: nextContext
                )
                let nextOriginNeedsAnchorWalk = endpointNeedsAnchorWalk(
                    directStops: directFromStops,
                    resolvedStops: fromStops,
                    context: nextContext
                )
                let nextRouteDestinationStopIds = endpointCandidateStopIds(
                    directStops: directToStops,
                    resolvedStops: toStops,
                    context: nextContext
                )
                let nextTerminalWalkLinks = shouldUseTerminalWalkLinks(directDestinationStops: directToStops, context: nextContext)
                    ? terminalWalkLinksByStopId(
                        context: nextContext,
                        destinationStopIds: destinationStopIds,
                        resolvedStops: toStops
                    )
                    : [:]
                candidates.append(contentsOf: route(
                    context: nextContext,
                    originStopIds: nextOriginNeedsAnchorWalk ? originStopIds : nextRouteOriginStopIds,
                    destinationStopIds: destinationStopIds,
                    routeDestinationStopIds: nextRouteDestinationStopIds,
                    terminalWalkLinksByStopId: nextTerminalWalkLinks,
                    seconds: 0,
                    isPreviousServiceDay: false,
                    arrivalDeparture: arrivalDeparture,
                    maxTransfers: maxTransfers
                ))
            }
        }

        candidates = normalize(
            filter(candidates, for: arrivalDeparture, requestedDate: date),
            relativeTo: Self.bratislavaCalendar.startOfDay(for: date)
        )
        candidates = limitToInitialSearchWindow(candidates, for: arrivalDeparture, requestedDate: date)

        let representatives = OfflineJourneyGrouper()
            .group(candidates, mode: arrivalDeparture)
            .map(\.representative)
            .sorted { displaySort($0, $1, mode: arrivalDeparture) }
        let trips = tripStops(forTripKeys: Set(representatives.flatMap { $0.labels.compactMap(\.tripKey) }))
        let imhdStopsByName = Dictionary(grouping: imhdStops.filter { $0.id > 0 }) { $0.name ?? "" }
        return representatives.map {
            Journey(
                id: "o-\(UUID().uuidString)",
                parts: partsWithStops($0, trips: trips, imhdStopsByName: imhdStopsByName),
                zones: Array($0.zones).sorted()
            )
        }
    }

    private struct TripStop {
        let stopId: String
        /// Service-day seconds, like the router's label times.
        let seconds: Int
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
            SELECT st.feed, st.trip_id, st.stop_id, st.departure_time, st.pickup_type, st.drop_off_type,
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
                  let seconds = row["departure_time"] as? Int,
                  let name = row["stop_name"] as? String,
                  let lat = row["stop_lat"] as? Double,
                  let lon = row["stop_lon"] as? Double else { continue }
            let key = "\(feed):\(tripId)"
            // The feed writes "-" for stops without a zone.
            let zone = (row["zone_id"] as? String).flatMap { $0.isEmpty || $0 == "-" ? nil : $0 }
            result[key, default: TripStops()].stops.append(TripStop(
                stopId: stopId,
                seconds: seconds,
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
        // The router builds one transit part per trip label, in label order.
        let tripLabels = candidate.labels.filter { $0.tripKey != nil }
        let transitIndices = parts.indices.filter { parts[$0].routeType != 64 }
        guard tripLabels.count == transitIndices.count else { return parts }

        for (label, index) in zip(tripLabels, transitIndices) {
            guard let trip = label.tripKey.flatMap({ trips[$0] }),
                  let boardTime = label.boardTime,
                  let alightTime = label.alightTime,
                  let board = trip.stops.firstIndex(where: { $0.stopId == label.boardStopId && $0.seconds == boardTime }),
                  let alight = trip.stops[(board + 1)...].firstIndex(where: {
                      $0.stopId == label.alightStopId && $0.seconds == alightTime
                  }) else { continue }
            let boardDeparture = parts[index].startDeparture
            parts[index].lowFloor = trip.lowFloor
            parts[index].stops = trip.stops[board...alight].map { stop in
                PartStop(
                    name: stop.name,
                    platform: stop.platform,
                    // Offsets from the boarding time keep the router's service day, also past midnight.
                    time: boardDeparture.addingTimeInterval(TimeInterval(stop.seconds - boardTime)),
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

    private func endpointAnchorStopIds(
        directStops: [OfflineStop],
        resolvedStops: [OfflineStop]
    ) -> Set<String> {
        let preferredStops = directStops.isEmpty ? resolvedStops : directStops
        return Set(preferredStops.map(\.id))
    }

    private func endpointCandidateStopIds(
        directStops: [OfflineStop],
        resolvedStops: [OfflineStop],
        context: OfflineRoutingContext
    ) -> Set<String> {
        let preferredStops = directStops.isEmpty ? resolvedStops : directStops
        let activePreferredStops = preferredStops.filter { hasActiveStopTimes($0.id, in: context) }
        if !activePreferredStops.isEmpty {
            return Set(activePreferredStops.map(\.id))
        }

        let activeResolvedStops = resolvedStops.filter { hasActiveStopTimes($0.id, in: context) }
        if !activeResolvedStops.isEmpty {
            return Set(activeResolvedStops.map(\.id))
        }

        return Set(preferredStops.map(\.id))
    }

    private func shouldUseTerminalWalkLinks(
        directDestinationStops: [OfflineStop],
        context: OfflineRoutingContext
    ) -> Bool {
        directDestinationStops.isEmpty ||
            !directDestinationStops.contains { hasActiveStopTimes($0.id, in: context) }
    }

    private func terminalWalkLinksByStopId(
        context: OfflineRoutingContext,
        destinationStopIds: Set<String>,
        resolvedStops: [OfflineStop]
    ) -> [String: [OfflineWalkLink]] {
        let links = resolvedStops
            .flatMap { context.walkLinksByStopId[$0.id] ?? [] }
            .filter { destinationStopIds.contains($0.toStopId) }
            .sorted { lhs, rhs in
                if lhs.seconds != rhs.seconds { return lhs.seconds < rhs.seconds }
                if lhs.fromStopId != rhs.fromStopId { return lhs.fromStopId < rhs.fromStopId }
                return lhs.toStopId < rhs.toStopId
            }
            .prefix(20)

        var result = [String: [OfflineWalkLink]]()
        for link in links {
            result[link.fromStopId, default: []].append(link)
        }
        return result
    }

    private func endpointNeedsAnchorWalk(
        directStops: [OfflineStop],
        resolvedStops: [OfflineStop],
        context: OfflineRoutingContext
    ) -> Bool {
        let preferredStops = directStops.isEmpty ? resolvedStops : directStops
        let hasActivePreferredStop = preferredStops.contains { hasActiveStopTimes($0.id, in: context) }
        let hasActiveResolvedStop = resolvedStops.contains { hasActiveStopTimes($0.id, in: context) }
        return !hasActivePreferredStop && hasActiveResolvedStop
    }

    private func hasActiveStopTimes(_ stopId: String, in context: OfflineRoutingContext) -> Bool {
        context.stopTimesByStopId[stopId]?.isEmpty == false
    }

    private struct ServiceDaySearch {
        let serviceDate: Date
        let seconds: Int
        let isPreviousServiceDay: Bool
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
        if let cached = Self.contextCache[key] {
            Self.contextCacheLock.unlock()
            return cached
        }
        Self.contextCacheLock.unlock()

        let context = OfflineRoutingContext.build(
            scheduleDb: scheduleDb,
            baseDb: baseDb,
            date: date,
            maxWalkDuration: maxWalkDuration
        )

        Self.contextCacheLock.lock()
        Self.contextCache[key] = context
        if Self.contextCache.count > Self.contextCacheLimit,
           let oldestKey = Self.contextCache.keys.first {
            Self.contextCache.removeValue(forKey: oldestKey)
        }
        Self.contextCacheLock.unlock()

        return context
    }

    private func serviceDaySearches(for date: Date, seconds: Int) -> [ServiceDaySearch] {
        let dayStart = Self.bratislavaCalendar.startOfDay(for: date)
        var searches = [
            ServiceDaySearch(serviceDate: dayStart, seconds: seconds, isPreviousServiceDay: false)
        ]
        if shouldSearchPreviousServiceDay(seconds: seconds) {
            let previousSearch = ServiceDaySearch(
                serviceDate: previousServiceDate(before: dayStart),
                seconds: seconds + Self.secondsPerDay,
                isPreviousServiceDay: true
            )
            if shouldPrioritizeCurrentServiceDay(seconds: seconds) {
                searches.append(previousSearch)
            } else {
                searches.insert(previousSearch, at: 0)
            }
        }
        return searches
    }

    private func route(
        context: OfflineRoutingContext,
        originStopIds: Set<String>,
        destinationStopIds: Set<String>,
        routeDestinationStopIds: Set<String>,
        terminalWalkLinksByStopId: [String: [OfflineWalkLink]],
        seconds: Int,
        isPreviousServiceDay: Bool,
        arrivalDeparture: ArrivalDeparture,
        maxTransfers: Int
    ) -> [OfflineJourneyCandidate] {
        let router = OfflineTimetableRouter(context: context)
        switch arrivalDeparture {
        case .departure:
            return router.routeDeparture(
                originStopIds: originStopIds,
                destinationStopIds: routeDestinationStopIds,
                departureSeconds: seconds,
                maxTransfers: maxTransfers,
                finalDestinationStopIds: destinationStopIds,
                terminalWalkLinksByStopId: terminalWalkLinksByStopId
            )
        case .arrival:
            return router.routeArrival(
                originStopIds: originStopIds,
                destinationStopIds: routeDestinationStopIds,
                arrivalSeconds: seconds,
                maxTransfers: maxTransfers,
                finalDestinationStopIds: destinationStopIds,
                earliestArrivalSeconds: isPreviousServiceDay ? Self.secondsPerDay : nil
            )
        }
    }

    private func filter(
        _ candidates: [OfflineJourneyCandidate],
        for arrivalDeparture: ArrivalDeparture,
        requestedDate date: Date
    ) -> [OfflineJourneyCandidate] {
        switch arrivalDeparture {
        case .departure:
            return candidates.filter { candidate in
                guard let departure = candidate.parts.first?.startDeparture else { return false }
                return departure >= date
            }
        case .arrival:
            return candidates.filter { candidate in
                guard let arrival = candidate.parts.last?.endArrival else { return false }
                return arrival <= date
            }
        }
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
                labels: candidate.labels,
                parts: candidate.parts,
                zones: candidate.zones,
                arrivalSeconds: Int(last.endArrival.timeIntervalSince(dayStart)),
                departureSeconds: Int(first.startDeparture.timeIntervalSince(dayStart)),
                transferCount: candidate.transferCount,
                walkSeconds: candidate.walkSeconds
            )
        }
    }

    private func limitToInitialSearchWindow(
        _ candidates: [OfflineJourneyCandidate],
        for arrivalDeparture: ArrivalDeparture,
        requestedDate date: Date
    ) -> [OfflineJourneyCandidate] {
        let requestedSeconds = Int(date.timeIntervalSince(Self.bratislavaCalendar.startOfDay(for: date)))
        let inWindow: [OfflineJourneyCandidate]
        switch arrivalDeparture {
        case .departure:
            inWindow = candidates.filter {
                $0.departureSeconds <= requestedSeconds + Self.initialSearchWindowSeconds
            }
        case .arrival:
            inWindow = candidates.filter {
                $0.arrivalSeconds >= requestedSeconds - Self.initialSearchWindowSeconds
            }
        }
        return inWindow.count >= Self.minimumWindowCandidateCount ? inWindow : candidates
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

    private func shouldSearchNextServiceDay(departureSeconds: Int, candidateCount: Int) -> Bool {
        candidateCount < 8 && departureSeconds >= Self.overnightSearchThresholdSeconds
    }

    private func shouldSearchPreviousServiceDay(seconds: Int) -> Bool {
        seconds < Self.earlyMorningSearchThresholdSeconds
    }

    private func shouldUsePreviousServiceDayOnly(seconds: Int, candidateCount: Int) -> Bool {
        seconds < Self.previousServiceDayOnlyThresholdSeconds &&
            candidateCount >= Self.minimumEarlyMorningCandidateCount
    }

    private func shouldPrioritizeCurrentServiceDay(seconds: Int) -> Bool {
        seconds >= Self.currentServiceDayPriorityThresholdSeconds
    }

    private func shouldUseCurrentServiceDayOnly(seconds: Int, candidateCount: Int) -> Bool {
        shouldPrioritizeCurrentServiceDay(seconds: seconds) &&
            seconds < Self.earlyMorningSearchThresholdSeconds &&
            candidateCount >= Self.minimumEarlyMorningCandidateCount
    }

    private func nextServiceDate(after dayStart: Date) -> Date {
        Self.bratislavaCalendar.date(byAdding: .day, value: 1, to: dayStart)!
    }

    private func previousServiceDate(before dayStart: Date) -> Date {
        Self.bratislavaCalendar.date(byAdding: .day, value: -1, to: dayStart)!
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
