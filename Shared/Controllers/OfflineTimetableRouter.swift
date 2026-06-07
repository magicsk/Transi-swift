import Foundation

final class OfflineTimetableRouter {
    private typealias FrontierEntry = (index: Int, label: OfflineRoutingLabel)

    private let maxCandidatesPerStopPerRound = 3
    private let maxReturnedCandidates = 40
    private let maxScannedStopTimesPerExpansion = 80
    private let maxWalkOriginsPerExpansion = 12

    private let context: OfflineRoutingContext

    init(context: OfflineRoutingContext) {
        self.context = context
    }

    func routeDeparture(
        originStopIds: Set<String>,
        destinationStopIds: Set<String>,
        departureSeconds: Int,
        maxTransfers: Int
    ) -> [OfflineJourneyCandidate] {
        guard !originStopIds.isEmpty, !destinationStopIds.isEmpty else { return [] }

        let transferLimit = max(0, maxTransfers)
        var labels = [OfflineRoutingLabel]()
        var bestByRound = Array(repeating: [String: [FrontierEntry]](), count: transferLimit + 2)
        var frontier = [FrontierEntry]()

        for stopId in originStopIds.sorted() {
            let label = OfflineRoutingLabel(
                stopId: stopId,
                time: departureSeconds,
                transfers: 0,
                walkSeconds: 0,
                previousIndex: nil,
                tripKey: nil,
                boardStopId: nil,
                alightStopId: nil,
                boardTime: nil,
                alightTime: nil,
                walkLink: nil
            )
            labels.append(label)
            let index = labels.count - 1
            let entry = (index: index, label: label)
            bestByRound[0][stopId] = [entry]
            frontier.append(entry)
        }

        var candidates = [OfflineJourneyCandidate]()
        for round in 0...transferLimit {
            let expanded = expandDeparture(
                frontier: frontier,
                round: round,
                labels: &labels,
                bestByRound: &bestByRound,
                destinationStopIds: destinationStopIds,
                candidates: &candidates
            )
            frontier = expanded
            if frontier.isEmpty { break }
        }

        return Array(candidates.sorted(by: departureSort).prefix(maxReturnedCandidates))
    }

    private func expandDeparture(
        frontier: [FrontierEntry],
        round: Int,
        labels: inout [OfflineRoutingLabel],
        bestByRound: inout [[String: [FrontierEntry]]],
        destinationStopIds: Set<String>,
        candidates: inout [OfflineJourneyCandidate]
    ) -> [FrontierEntry] {
        var next = [FrontierEntry]()
        for entry in frontier {
            let origins = walkingOrigins(from: entry.label)
            for origin in origins {
                var scannedStopTimes = 0
                var boardingsByLine = [String: Int]()
                for stopTime in departingStopTimes(from: origin.stopId, atOrAfter: origin.time) {
                    if scannedStopTimes >= maxScannedStopTimesPerExpansion {
                        break
                    }
                    scannedStopTimes += 1
                    if stopTime.tripKey == entry.label.tripKey {
                        continue
                    }
                    guard let trip = context.tripsByKey[stopTime.tripKey],
                          let boardIndex = trip.stopTimes.firstIndex(where: { $0.stopId == stopTime.stopId && $0.sequence == stopTime.sequence }) else {
                        continue
                    }
                    let lineBoardings = boardingsByLine[trip.routeShortName, default: 0]
                    if lineBoardings >= 3 {
                        continue
                    }
                    boardingsByLine[trip.routeShortName] = lineBoardings + 1
                    for alight in trip.stopTimes[(boardIndex + 1)...] {
                        let newLabel = OfflineRoutingLabel(
                            stopId: alight.stopId,
                            time: alight.arrival,
                            transfers: round,
                            walkSeconds: origin.walkSeconds,
                            previousIndex: entry.index,
                            tripKey: trip.key,
                            boardStopId: stopTime.stopId,
                            alightStopId: alight.stopId,
                            boardTime: stopTime.departure,
                            alightTime: alight.arrival,
                            walkLink: origin.walkLink
                        )
                        let nextRound = min(round + 1, bestByRound.count - 1)
                        let newIndex = labels.count
                        let newEntry = (index: newIndex, label: newLabel)
                        guard let removedEntries = admit(newEntry, into: &bestByRound, round: nextRound) else {
                            continue
                        }
                        labels.append(newLabel)
                        removeEntries(removedEntries, from: &next)
                        removeCandidates(endingAt: removedEntries, from: &candidates)
                        if destinationStopIds.contains(alight.stopId) {
                            if let candidate = buildCandidate(terminal: newLabel, allLabels: labels) {
                                candidates.append(candidate)
                            }
                        } else {
                            next.append(newEntry)
                        }
                    }
                }
            }
        }
        return next
    }

    private func departingStopTimes(from stopId: String, atOrAfter time: Int) -> ArraySlice<OfflineStopTime> {
        guard let stopTimes = context.stopTimesByStopId[stopId], !stopTimes.isEmpty else {
            return ArraySlice<OfflineStopTime>()
        }
        var low = stopTimes.startIndex
        var high = stopTimes.endIndex
        while low < high {
            let mid = low + (high - low) / 2
            if stopTimes[mid].departure < time {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return stopTimes[low...]
    }

    private struct WalkOrigin {
        let stopId: String
        let time: Int
        let walkSeconds: Int
        let walkLink: OfflineWalkLink?
    }

    private func walkingOrigins(from label: OfflineRoutingLabel) -> [WalkOrigin] {
        var result = [
            WalkOrigin(
                stopId: label.stopId,
                time: label.time,
                walkSeconds: label.walkSeconds,
                walkLink: nil
            )
        ]
        for link in (context.walkLinksByStopId[label.stopId] ?? []).prefix(maxWalkOriginsPerExpansion) {
            result.append(WalkOrigin(
                stopId: link.toStopId,
                time: label.time + link.seconds,
                walkSeconds: label.walkSeconds + link.seconds,
                walkLink: link
            ))
        }
        return result
    }

    private func admit(
        _ entry: FrontierEntry,
        into bestByRound: inout [[String: [FrontierEntry]]],
        round: Int
    ) -> [FrontierEntry]? {
        let stopId = entry.label.stopId
        var entries = bestByRound[round][stopId] ?? []
        if entries.contains(where: { dominates($0.label, entry.label) }) {
            return nil
        }
        let previousEntries = entries
        entries.removeAll { dominates(entry.label, $0.label) }
        entries.append(entry)
        entries.sort(by: frontierSort)
        let keptEntries = Array(entries.prefix(maxCandidatesPerStopPerRound))
        guard keptEntries.contains(where: { $0.index == entry.index }) else {
            return nil
        }
        let keptIndices = Set(keptEntries.map { $0.index })
        let removed = previousEntries.filter { !keptIndices.contains($0.index) }
        bestByRound[round][stopId] = keptEntries
        return removed
    }

    private func removeEntries(_ removedEntries: [FrontierEntry], from frontier: inout [FrontierEntry]) {
        guard !removedEntries.isEmpty else { return }
        let removedIndices = Set(removedEntries.map { $0.index })
        frontier.removeAll { removedIndices.contains($0.index) }
    }

    private func removeCandidates(endingAt removedEntries: [FrontierEntry], from candidates: inout [OfflineJourneyCandidate]) {
        guard !removedEntries.isEmpty else { return }
        let removedLabels = Set(removedEntries.map { $0.label })
        candidates.removeAll { candidate in
            guard let terminal = candidate.labels.last else { return false }
            return removedLabels.contains(terminal)
        }
    }

    private func dominates(_ lhs: OfflineRoutingLabel, _ rhs: OfflineRoutingLabel) -> Bool {
        lhs.time <= rhs.time &&
            lhs.transfers <= rhs.transfers &&
            lhs.walkSeconds <= rhs.walkSeconds
    }

    private func buildCandidate(terminal: OfflineRoutingLabel, allLabels: [OfflineRoutingLabel]) -> OfflineJourneyCandidate? {
        var chain = [OfflineRoutingLabel]()
        var current: OfflineRoutingLabel? = terminal
        while let label = current {
            chain.append(label)
            if let previous = label.previousIndex {
                current = allLabels[previous]
            } else {
                current = nil
            }
        }
        chain.reverse()
        let parts = mapParts(labels: chain)
        guard let first = parts.first, let last = parts.last else { return nil }
        let transitPartCount = parts.filter { $0.routeType != 64 }.count
        return OfflineJourneyCandidate(
            labels: chain,
            parts: parts,
            zones: zones(for: chain),
            arrivalSeconds: Int(last.endArrival.timeIntervalSince(context.dayStart)),
            departureSeconds: Int(first.startDeparture.timeIntervalSince(context.dayStart)),
            transferCount: max(0, transitPartCount - 1),
            walkSeconds: chain.last?.walkSeconds ?? 0
        )
    }

    private func mapParts(labels: [OfflineRoutingLabel]) -> [Part] {
        var parts = [Part]()
        for (index, label) in labels.enumerated() {
            if let link = label.walkLink,
               index > 0,
               let from = context.stopsById[link.fromStopId],
               let to = context.stopsById[link.toStopId] {
                let previous = labels[index - 1]
                let walkArrival = previous.time + link.seconds
                parts.append(Part(
                    startStopName: from.name,
                    endStopName: to.name,
                    startStopCode: from.platform,
                    endStopCode: to.platform,
                    startDeparture: context.dayStart.addingTimeInterval(TimeInterval(previous.time)),
                    endArrival: context.dayStart.addingTimeInterval(TimeInterval(walkArrival)),
                    routeType: 64,
                    tripHeadsign: "Walk",
                    routeShortName: nil
                ))
            }
            guard let tripKey = label.tripKey,
                  let trip = context.tripsByKey[tripKey],
                  let board = label.boardStopId.flatMap({ context.stopsById[$0] }),
                  let alight = label.alightStopId.flatMap({ context.stopsById[$0] }),
                  let boardTime = label.boardTime,
                  let alightTime = label.alightTime else {
                continue
            }
            parts.append(Part(
                startStopName: board.name,
                endStopName: alight.name,
                startStopCode: board.platform,
                endStopCode: alight.platform,
                startDeparture: context.dayStart.addingTimeInterval(TimeInterval(boardTime)),
                endArrival: context.dayStart.addingTimeInterval(TimeInterval(alightTime)),
                routeType: trip.routeType,
                tripHeadsign: trip.headsign,
                routeShortName: trip.routeShortName
            ))
        }
        return parts
    }

    private func zones(for labels: [OfflineRoutingLabel]) -> Set<String> {
        var result = Set<String>()
        for label in labels {
            insertZone(label.stopId, into: &result)
            if let link = label.walkLink {
                insertZone(link.fromStopId, into: &result)
                insertZone(link.toStopId, into: &result)
            }
            guard let tripKey = label.tripKey,
                  let trip = context.tripsByKey[tripKey],
                  let boardStopId = label.boardStopId,
                  let alightStopId = label.alightStopId,
                  let boardTime = label.boardTime,
                  let alightTime = label.alightTime else {
                continue
            }
            guard let boardIndex = trip.stopTimes.firstIndex(where: { $0.stopId == boardStopId && $0.departure == boardTime }),
                  let alightIndex = trip.stopTimes.firstIndex(where: { $0.stopId == alightStopId && $0.arrival == alightTime && $0.sequence > trip.stopTimes[boardIndex].sequence }) else {
                insertZone(boardStopId, into: &result)
                insertZone(alightStopId, into: &result)
                continue
            }
            for stopTime in trip.stopTimes[boardIndex...alightIndex] {
                insertZone(stopTime.stopId, into: &result)
            }
        }
        return result
    }

    private func insertZone(_ stopId: String, into zones: inout Set<String>) {
        if let zone = context.zonesByStopId[stopId], !zone.isEmpty {
            zones.insert(zone)
        }
    }

    private func departureSort(_ lhs: OfflineJourneyCandidate, _ rhs: OfflineJourneyCandidate) -> Bool {
        if lhs.arrivalSeconds != rhs.arrivalSeconds { return lhs.arrivalSeconds < rhs.arrivalSeconds }
        if lhs.transferCount != rhs.transferCount { return lhs.transferCount < rhs.transferCount }
        if lhs.walkSeconds != rhs.walkSeconds { return lhs.walkSeconds < rhs.walkSeconds }
        return lhs.departureSeconds < rhs.departureSeconds
    }

    private func frontierSort(_ lhs: FrontierEntry, _ rhs: FrontierEntry) -> Bool {
        if lhs.label.time != rhs.label.time { return lhs.label.time < rhs.label.time }
        if lhs.label.transfers != rhs.label.transfers { return lhs.label.transfers < rhs.label.transfers }
        if lhs.label.walkSeconds != rhs.label.walkSeconds { return lhs.label.walkSeconds < rhs.label.walkSeconds }
        return lhs.label.stopId < rhs.label.stopId
    }
}
