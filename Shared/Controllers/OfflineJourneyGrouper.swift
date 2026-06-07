import Foundation

final class OfflineJourneyGrouper {
    func group(_ candidates: [OfflineJourneyCandidate]) -> [OfflineGroupedJourney] {
        var groups = [String: [OfflineJourneyCandidate]]()
        for candidate in candidates {
            groups[groupKey(candidate), default: []].append(candidate)
        }
        return groups.values.map { group in
            let sorted = group.sorted(by: rank)
            return OfflineGroupedJourney(representative: sorted[0], alternatives: Array(sorted.dropFirst()))
        }
        .sorted { rank($0.representative, $1.representative) }
    }

    private func groupKey(_ candidate: OfflineJourneyCandidate) -> String {
        let transitParts = candidate.parts.filter { $0.routeType != 64 }
        let lines = transitParts.compactMap(\.routeShortName).joined(separator: ">")
        let bucketedArrival = candidate.arrivalSeconds / 180
        let first = candidate.parts.first?.startStopName ?? ""
        let last = candidate.parts.last?.endStopName ?? ""
        return "\(first)|\(last)|\(lines)|\(bucketedArrival)"
    }

    private func rank(_ lhs: OfflineJourneyCandidate, _ rhs: OfflineJourneyCandidate) -> Bool {
        if lhs.arrivalSeconds != rhs.arrivalSeconds { return lhs.arrivalSeconds < rhs.arrivalSeconds }
        if lhs.transferCount != rhs.transferCount { return lhs.transferCount < rhs.transferCount }
        if lhs.walkSeconds != rhs.walkSeconds { return lhs.walkSeconds < rhs.walkSeconds }
        return lhs.departureSeconds < rhs.departureSeconds
    }
}
