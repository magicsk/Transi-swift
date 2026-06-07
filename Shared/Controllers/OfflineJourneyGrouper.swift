import Foundation

final class OfflineJourneyGrouper {
    func group(_ candidates: [OfflineJourneyCandidate], mode: ArrivalDeparture) -> [OfflineGroupedJourney] {
        var groups = [GroupKey: [OfflineJourneyCandidate]]()
        for candidate in candidates {
            groups[groupKey(candidate), default: []].append(candidate)
        }
        let rank = ranker(for: mode)
        return groups.values.map { group in
            let sorted = group.sorted(by: rank)
            return OfflineGroupedJourney(representative: sorted[0], alternatives: Array(sorted.dropFirst()))
        }
        .sorted { rank($0.representative, $1.representative) }
    }

    private struct GroupKey: Hashable {
        let firstStopName: String
        let lastStopName: String
        let lines: [String]
        let bucketedArrival: Int
    }

    private func groupKey(_ candidate: OfflineJourneyCandidate) -> GroupKey {
        let transitParts = candidate.parts.filter { $0.routeType != 64 }
        return GroupKey(
            firstStopName: candidate.parts.first?.startStopName ?? "",
            lastStopName: candidate.parts.last?.endStopName ?? "",
            lines: transitParts.compactMap(\.routeShortName),
            bucketedArrival: candidate.arrivalSeconds / 180
        )
    }

    private func ranker(for mode: ArrivalDeparture) -> (OfflineJourneyCandidate, OfflineJourneyCandidate) -> Bool {
        switch mode {
        case .departure:
            return rankDeparture
        case .arrival:
            return rankArrival
        }
    }

    private func rankDeparture(_ lhs: OfflineJourneyCandidate, _ rhs: OfflineJourneyCandidate) -> Bool {
        if lhs.arrivalSeconds != rhs.arrivalSeconds { return lhs.arrivalSeconds < rhs.arrivalSeconds }
        if lhs.transferCount != rhs.transferCount { return lhs.transferCount < rhs.transferCount }
        if lhs.walkSeconds != rhs.walkSeconds { return lhs.walkSeconds < rhs.walkSeconds }
        return lhs.departureSeconds < rhs.departureSeconds
    }

    private func rankArrival(_ lhs: OfflineJourneyCandidate, _ rhs: OfflineJourneyCandidate) -> Bool {
        if lhs.departureSeconds != rhs.departureSeconds { return lhs.departureSeconds > rhs.departureSeconds }
        if lhs.transferCount != rhs.transferCount { return lhs.transferCount < rhs.transferCount }
        if lhs.walkSeconds != rhs.walkSeconds { return lhs.walkSeconds < rhs.walkSeconds }
        return lhs.arrivalSeconds < rhs.arrivalSeconds
    }
}
