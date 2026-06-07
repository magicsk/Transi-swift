import Foundation

class OfflineRoutingEngine {
    private static let overnightSearchThresholdSeconds = 21 * 60 * 60

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
        let destinationFeeds = Set(directToStops.map(\.feed))
        let feedMatchedFromStops = directFromStops.filter { destinationFeeds.contains($0.feed) }
        let endpointFromStops = feedMatchedFromStops.isEmpty ? directFromStops : feedMatchedFromStops
        let originFeeds = Set(endpointFromStops.map(\.feed))
        let feedMatchedToStops = directToStops.filter { originFeeds.contains($0.feed) }
        let endpointToStops = feedMatchedToStops.isEmpty ? directToStops : feedMatchedToStops
        let originStopIds = Set((endpointFromStops.isEmpty ? fromStops : endpointFromStops).map(\.id))
        let destinationStopIds = Set((endpointToStops.isEmpty ? toStops : endpointToStops).map(\.id))

        let context = OfflineRoutingContext.build(
            scheduleDb: scheduleDb,
            baseDb: baseDb,
            date: date,
            maxWalkDuration: maxWalkDuration
        )
        let hasMainDestinationStopTimes = destinationStopIds.contains { context.stopTimesByStopId[$0]?.isEmpty == false }
        guard hasMainDestinationStopTimes || arrivalDeparture == .departure else {
            return []
        }
        let seconds = max(0, Int(date.timeIntervalSince(context.dayStart)))
        let router = OfflineTimetableRouter(context: context)
        var candidates: [OfflineJourneyCandidate]

        switch arrivalDeparture {
        case .departure:
            candidates = router.routeDeparture(
                originStopIds: originStopIds,
                destinationStopIds: destinationStopIds,
                departureSeconds: seconds,
                maxTransfers: maxTransfers
            )
        case .arrival:
            candidates = router.routeArrival(
                originStopIds: originStopIds,
                destinationStopIds: destinationStopIds,
                arrivalSeconds: seconds,
                maxTransfers: maxTransfers
            )
        }

        if arrivalDeparture == .departure {
            candidates = candidates.filter { candidate in
                guard let departure = candidate.parts.first?.startDeparture else { return false }
                return departure >= date
            }
            if shouldSearchNextServiceDay(departureSeconds: seconds, candidateCount: candidates.count) {
                let nextDate = nextServiceDate(after: context.dayStart)
                let nextContext = OfflineRoutingContext.build(
                    scheduleDb: scheduleDb,
                    baseDb: baseDb,
                    date: nextDate,
                    maxWalkDuration: maxWalkDuration
                )
                let nextRouter = OfflineTimetableRouter(context: nextContext)
                candidates.append(contentsOf: nextRouter.routeDeparture(
                    originStopIds: originStopIds,
                    destinationStopIds: destinationStopIds,
                    departureSeconds: 0,
                    maxTransfers: maxTransfers
                ))
                candidates = candidates.filter { candidate in
                    guard let departure = candidate.parts.first?.startDeparture else { return false }
                    return departure >= date
                }
            }
        }

        return OfflineJourneyGrouper()
            .group(candidates)
            .map {
                Journey(
                    id: UUID().uuidString,
                    parts: $0.representative.parts,
                    zones: Array($0.representative.zones).sorted()
                )
            }
    }

    private func shouldSearchNextServiceDay(departureSeconds: Int, candidateCount: Int) -> Bool {
        candidateCount < 8 && departureSeconds >= Self.overnightSearchThresholdSeconds
    }

    private func nextServiceDate(after dayStart: Date) -> Date {
        Self.bratislavaCalendar.date(byAdding: .day, value: 1, to: dayStart)!
    }

    private static var bratislavaCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Bratislava")!
        return calendar
    }
}

final class OfflineJourneyGrouper {
    func group(_ candidates: [OfflineJourneyCandidate]) -> [OfflineGroupedJourney] {
        candidates.map { OfflineGroupedJourney(representative: $0, alternatives: []) }
    }
}
