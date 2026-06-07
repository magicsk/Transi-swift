import Foundation

class OfflineRoutingEngine {
    private static let overnightSearchThresholdSeconds = 21 * 60 * 60
    private static let earlyMorningSearchThresholdSeconds = 5 * 60 * 60
    private static let currentServiceDayPriorityThresholdSeconds = 4 * 60 * 60
    private static let previousServiceDayOnlyThresholdSeconds = 2 * 60 * 60
    private static let minimumEarlyMorningCandidateCount = 8
    private static let secondsPerDay = 24 * 60 * 60

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
        maxWalkDuration: Int
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
            let context = OfflineRoutingContext.build(
                scheduleDb: scheduleDb,
                baseDb: baseDb,
                date: search.serviceDate,
                maxWalkDuration: maxWalkDuration
            )
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
            candidates.append(contentsOf: route(
                context: context,
                originStopIds: originNeedsAnchorWalk ? originStopIds : routeOriginStopIds,
                destinationStopIds: destinationStopIds,
                routeDestinationStopIds: routeDestinationStopIds,
                terminalWalkLinksByStopId: terminalWalkLinksByStopId(
                    context: context,
                    destinationStopIds: destinationStopIds,
                    resolvedStops: toStops
                ),
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
                let nextContext = OfflineRoutingContext.build(
                    scheduleDb: scheduleDb,
                    baseDb: baseDb,
                    date: nextDate,
                    maxWalkDuration: maxWalkDuration
                )
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
                candidates.append(contentsOf: route(
                    context: nextContext,
                    originStopIds: nextOriginNeedsAnchorWalk ? originStopIds : nextRouteOriginStopIds,
                    destinationStopIds: destinationStopIds,
                    routeDestinationStopIds: nextRouteDestinationStopIds,
                    terminalWalkLinksByStopId: terminalWalkLinksByStopId(
                        context: nextContext,
                        destinationStopIds: destinationStopIds,
                        resolvedStops: toStops
                    ),
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

        return OfflineJourneyGrouper()
            .group(candidates, mode: arrivalDeparture)
            .map {
                Journey(
                    id: UUID().uuidString,
                    parts: $0.representative.parts,
                    zones: Array($0.representative.zones).sorted()
                )
            }
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
