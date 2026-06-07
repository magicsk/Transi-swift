import Foundation

final class OfflineTimetableRouter {
    private typealias FrontierEntry = (index: Int, label: OfflineRoutingLabel)

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
        let transferLimit = max(0, maxTransfers)
        var labels = [OfflineRoutingLabel]()
        var bestByRound = Array(repeating: [String: OfflineRoutingLabel](), count: transferLimit + 2)
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
            bestByRound[0][stopId] = label
            frontier.append((index: index, label: label))
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

        return Array(candidates.sorted(by: departureSort).prefix(40))
    }

    private func expandDeparture(
        frontier: [FrontierEntry],
        round: Int,
        labels: inout [OfflineRoutingLabel],
        bestByRound: inout [[String: OfflineRoutingLabel]],
        destinationStopIds: Set<String>,
        candidates: inout [OfflineJourneyCandidate]
    ) -> [FrontierEntry] {
        var next = [FrontierEntry]()
        for entry in frontier {
            let origins = walkingOrigins(from: entry.label)
            for origin in origins {
                for stopTime in context.stopTimesByStopId[origin.stopId] ?? [] where stopTime.departure >= origin.time {
                    guard let trip = context.tripsByKey[stopTime.tripKey],
                          let boardIndex = trip.stopTimes.firstIndex(where: { $0.stopId == stopTime.stopId && $0.sequence == stopTime.sequence }) else {
                        continue
                    }
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
                        if isDominated(newLabel, by: bestByRound[nextRound][alight.stopId]) {
                            continue
                        }
                        labels.append(newLabel)
                        let newIndex = labels.count - 1
                        bestByRound[nextRound][alight.stopId] = newLabel
                        if destinationStopIds.contains(alight.stopId) {
                            if let candidate = buildCandidate(terminal: newLabel, allLabels: labels) {
                                candidates.append(candidate)
                            }
                        } else {
                            next.append((index: newIndex, label: newLabel))
                        }
                    }
                }
            }
        }
        return next
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
        for link in context.walkLinksByStopId[label.stopId] ?? [] {
            result.append(WalkOrigin(
                stopId: link.toStopId,
                time: label.time + link.seconds,
                walkSeconds: label.walkSeconds + link.seconds,
                walkLink: link
            ))
        }
        return result
    }

    private func isDominated(_ label: OfflineRoutingLabel, by existing: OfflineRoutingLabel?) -> Bool {
        guard let existing else { return false }
        return existing.time <= label.time &&
            existing.transfers <= label.transfers &&
            existing.walkSeconds <= label.walkSeconds
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
}
