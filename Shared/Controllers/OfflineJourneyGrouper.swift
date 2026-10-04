import Foundation

final class OfflineJourneyGrouper {
    func group(_ candidates: [OfflineJourneyCandidate], mode: ArrivalDeparture) -> [OfflineGroupedJourney] {
        let candidates = prune(candidates)
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

    private static let maxTransferWaitSeconds = 60 * 60

    private func prune(_ candidates: [OfflineJourneyCandidate]) -> [OfflineJourneyCandidate] {
        let withoutLoops = candidates.filter {
            !hasRepeatedTransitLine($0) && !revisitsStop($0) && !hasExcessiveTransferWait($0)
        }
        let source = withoutLoops.isEmpty ? candidates : withoutLoops
        let nonDominated = source.filter { candidate in
            !source.contains { other in
                other.labels != candidate.labels && dominates(other, candidate)
            }
        }
        let useful = nonDominated.isEmpty ? source : nonDominated
        return pruneExtremeDurationDetours(useful)
    }

    private static let maxDurationDetourSlackSeconds = 30 * 60
    private static let maxDurationDetourMultiplier = 2

    private func pruneExtremeDurationDetours(_ candidates: [OfflineJourneyCandidate]) -> [OfflineJourneyCandidate] {
        let durations = candidates.map(durationSeconds).filter { $0 > 0 }
        guard let bestDuration = durations.min() else { return candidates }
        let limit = max(
            bestDuration + Self.maxDurationDetourSlackSeconds,
            bestDuration * Self.maxDurationDetourMultiplier
        )
        let filtered = candidates.filter { durationSeconds($0) <= limit }
        return filtered.isEmpty ? candidates : filtered
    }

    private func hasRepeatedTransitLine(_ candidate: OfflineJourneyCandidate) -> Bool {
        var seen = Set<String>()
        for line in transitLines(candidate) {
            if seen.contains(line) {
                return true
            }
            seen.insert(line)
        }
        return false
    }

    /// A journey that comes back to a stop it already left (e.g. ride away,
    /// ride back to the origin, board a third line) is never a sensible
    /// suggestion. Consecutive duplicates (platform changes at the same stop)
    /// are fine.
    private func revisitsStop(_ candidate: OfflineJourneyCandidate) -> Bool {
        var visited = [String]()
        for part in candidate.parts {
            for rawName in [part.startStopName, part.endStopName] {
                guard let rawName else { continue }
                let name = normalizedName(rawName)
                if name == visited.last { continue }
                if visited.contains(name) { return true }
                visited.append(name)
            }
        }
        return false
    }

    /// Waiting hours at a transfer stop for the day's next departure is never
    /// a journey worth suggesting.
    private func hasExcessiveTransferWait(_ candidate: OfflineJourneyCandidate) -> Bool {
        for (previous, part) in zip(candidate.parts, candidate.parts.dropFirst()) {
            let wait = part.startDeparture.timeIntervalSince(previous.endArrival)
            if Int(wait) > Self.maxTransferWaitSeconds {
                return true
            }
        }
        return false
    }

    private func dominates(_ lhs: OfflineJourneyCandidate, _ rhs: OfflineJourneyCandidate) -> Bool {
        // Walk differences under two minutes should not keep an otherwise
        // worse journey alive (e.g. an extra transfer to save a few seconds
        // of platform walking), so compare walks in coarse buckets.
        let lhsWalk = lhs.walkSeconds / 120
        let rhsWalk = rhs.walkSeconds / 120
        guard endpointKey(lhs) == endpointKey(rhs),
              lhs.departureSeconds >= rhs.departureSeconds,
              lhs.arrivalSeconds <= rhs.arrivalSeconds,
              lhs.transferCount <= rhs.transferCount,
              lhsWalk <= rhsWalk else {
            return false
        }
        return lhs.departureSeconds > rhs.departureSeconds ||
            lhs.arrivalSeconds < rhs.arrivalSeconds ||
            lhs.transferCount < rhs.transferCount ||
            lhsWalk < rhsWalk
    }

    private func endpointKey(_ candidate: OfflineJourneyCandidate) -> EndpointKey {
        EndpointKey(
            startStopName: normalizedName(candidate.parts.first?.startStopName ?? ""),
            endStopName: normalizedName(candidate.parts.last?.endStopName ?? "")
        )
    }

    private struct EndpointKey: Hashable {
        let startStopName: String
        let endStopName: String
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
            firstStopName: normalizedName(candidate.parts.first?.startStopName ?? ""),
            lastStopName: normalizedName(candidate.parts.last?.endStopName ?? ""),
            lines: transitParts.compactMap(\.routeShortName),
            bucketedArrival: candidate.arrivalSeconds / 180
        )
    }

    private func transitLines(_ candidate: OfflineJourneyCandidate) -> [String] {
        candidate.parts
            .filter { $0.routeType != 64 }
            .compactMap(\.routeShortName)
    }

    private func normalizedName(_ name: String) -> String {
        name.replacingOccurrences(of: "Bratislava, ", with: "")
            .replacingOccurrences(of: "Rovinka, ", with: "")
            .replacingOccurrences(of: "Dunajská Lužná, ", with: "")
            .replacingOccurrences(of: "Miloslavov, ", with: "")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "sk_SK"))
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
        let lhsDuration = durationSeconds(lhs)
        let rhsDuration = durationSeconds(rhs)
        if lhsDuration != rhsDuration { return lhsDuration < rhsDuration }
        if lhs.transferCount != rhs.transferCount { return lhs.transferCount < rhs.transferCount }
        if lhs.walkSeconds != rhs.walkSeconds { return lhs.walkSeconds < rhs.walkSeconds }
        if lhs.arrivalSeconds != rhs.arrivalSeconds { return lhs.arrivalSeconds < rhs.arrivalSeconds }
        return lhs.departureSeconds < rhs.departureSeconds
    }

    private func rankArrival(_ lhs: OfflineJourneyCandidate, _ rhs: OfflineJourneyCandidate) -> Bool {
        let lhsDuration = durationSeconds(lhs)
        let rhsDuration = durationSeconds(rhs)
        if lhsDuration != rhsDuration { return lhsDuration < rhsDuration }
        if lhs.transferCount != rhs.transferCount { return lhs.transferCount < rhs.transferCount }
        if lhs.walkSeconds != rhs.walkSeconds { return lhs.walkSeconds < rhs.walkSeconds }
        if lhs.departureSeconds != rhs.departureSeconds { return lhs.departureSeconds > rhs.departureSeconds }
        return lhs.arrivalSeconds < rhs.arrivalSeconds
    }

    private func durationSeconds(_ candidate: OfflineJourneyCandidate) -> Int {
        candidate.arrivalSeconds - candidate.departureSeconds
    }
}
