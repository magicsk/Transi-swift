import Foundation

class OfflineRoutingEngine {
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
        let destinationEndpointFeeds = Set(endpointToStops.map(\.feed))
        let originStopIds = Set((endpointFromStops.isEmpty ? fromStops : endpointFromStops).map(\.id))
        let destinationStopIds = Set((endpointToStops.isEmpty ? toStops : endpointToStops).map(\.id))

        let context = OfflineRoutingContext.build(
            scheduleDb: scheduleDb,
            baseDb: baseDb,
            date: date,
            maxWalkDuration: maxWalkDuration
        )
        guard destinationStopIds.contains(where: { context.stopTimesByStopId[$0]?.isEmpty == false }) else {
            return []
        }
        let seconds = max(0, Int(date.timeIntervalSince(context.dayStart)))
        let router = OfflineTimetableRouter(context: context)
        let routeMaxTransfers = originFeeds == Set(["trains"]) && destinationEndpointFeeds == Set(["trains"]) ? 0 : maxTransfers
        let candidates: [OfflineJourneyCandidate]

        switch arrivalDeparture {
        case .departure:
            candidates = router.routeDeparture(
                originStopIds: originStopIds,
                destinationStopIds: destinationStopIds,
                departureSeconds: seconds,
                maxTransfers: routeMaxTransfers
            )
        case .arrival:
            candidates = router.routeArrival(
                originStopIds: originStopIds,
                destinationStopIds: destinationStopIds,
                arrivalSeconds: seconds,
                maxTransfers: routeMaxTransfers
            )
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
}

extension OfflineTimetableRouter {
    func routeArrival(
        originStopIds: Set<String>,
        destinationStopIds: Set<String>,
        arrivalSeconds: Int,
        maxTransfers: Int
    ) -> [OfflineJourneyCandidate] {
        return []
    }
}

final class OfflineJourneyGrouper {
    func group(_ candidates: [OfflineJourneyCandidate]) -> [OfflineGroupedJourney] {
        candidates.map { OfflineGroupedJourney(representative: $0, alternatives: []) }
    }
}
