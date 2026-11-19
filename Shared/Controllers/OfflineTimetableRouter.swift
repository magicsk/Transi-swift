import Foundation

/// Range RAPTOR (Delling, Pajor, Werneck: "Round-Based Public Transit Routing", 2012) over one
/// service day. Every departure from the origin inside the requested range is searched, latest
/// first, reusing the labels of the later departures, so each run only explores what leaving
/// earlier improves. Round k holds the earliest arrival at each stop with at most k rides; the
/// result is the Pareto set over later departure, earlier arrival and fewer rides.
final class OfflineTimetableRouter {
    /// Minimum time to change vehicles at the same stop. Changes between stops walk at least a minute.
    static let transferBufferSeconds: Int32 = 30

    private let context: OfflineRoutingContext

    init(context: OfflineRoutingContext) {
        self.context = context
    }

    /// Journeys from the stops named like the origin to those named like the destination that
    /// leave inside `departures` and, when given, arrive by `latestArrival` (service-day seconds).
    /// Stops within the context's walk limit of a named stop count as well, with the walk added.
    /// A journey leaves as late as it can: its departure is the first boarding minus the walk to it.
    func route(
        originStopIds: [String],
        destinationStopIds: [String],
        departures: ClosedRange<Int>,
        latestArrival: Int?,
        maxTransfers: Int
    ) -> [OfflineJourneyCandidate] {
        let origins = endpoints(around: originStopIds)
        let destinations = endpoints(around: destinationStopIds)
        guard !origins.isEmpty, !destinations.isEmpty else { return [] }
        let search = Search(
            context: context,
            origins: origins,
            destinations: destinations,
            rounds: max(0, maxTransfers) + 1,
            latestArrival: latestArrival.map { Int32(clamping: $0) } ?? Search.unreached - 1
        )
        var candidates = [OfflineJourneyCandidate]()
        for departure in departureTimes(from: origins, in: departures) {
            // A journey that boards later than this run's departure leaves after the range: it is the next page's.
            for legs in search.run(departure: departure) {
                let candidate = makeCandidate(legs)
                if candidate.departureSeconds <= departures.upperBound {
                    candidates.append(candidate)
                }
            }
        }
        return candidates
    }

    /// The named stops (no walk) and every stop within walking distance of one, with its shortest walk.
    private func endpoints(around stopIds: [String]) -> [Endpoint] {
        let named = stopIds.compactMap { context.stopIndexById[$0] }.sorted()
        var byStop = [Int32: Endpoint]()
        for stop in named {
            byStop[stop] = Endpoint(stop: stop, walk: 0, anchor: stop)
        }
        for anchor in named {
            for footpath in context.footpaths[Int(anchor)] where footpath.seconds < byStop[footpath.stop]?.walk ?? .max {
                byStop[footpath.stop] = Endpoint(stop: footpath.stop, walk: footpath.seconds, anchor: anchor)
            }
        }
        return byStop.values.sorted { $0.stop < $1.stop }
    }

    /// Every time a rider can leave to board some trip at an origin, inside the range, latest first.
    private func departureTimes(from origins: [Endpoint], in range: ClosedRange<Int>) -> [Int32] {
        var times = Set<Int32>()
        for origin in origins {
            let earliest = Int32(clamping: range.lowerBound) + origin.walk
            let latest = Int32(clamping: range.upperBound) + origin.walk
            for routeStop in context.routesAtStop[Int(origin.stop)] {
                let route = context.routes[Int(routeStop.route)]
                let stopCount = route.stops.count
                let position = Int(routeStop.position)
                guard position < stopCount - 1 else { continue }
                var row = firstTrip(in: route, at: position, departingAtOrAfter: earliest, before: route.trips.count)
                while row < route.trips.count, route.departures[row * stopCount + position] <= latest {
                    times.insert(route.departures[row * stopCount + position] - origin.walk)
                    row += 1
                }
            }
        }
        return times.sorted(by: >)
    }

    private func makeCandidate(_ legs: [Leg]) -> OfflineJourneyCandidate {
        var parts = [Part]()
        var rides = [OfflineRide]()
        var zones = Set<String>()
        var walkSeconds = 0
        for leg in legs {
            switch leg {
            case let .walk(from, to, start, end):
                let fromStop = context.stops[Int(from)]
                let toStop = context.stops[Int(to)]
                parts.append(Part(
                    startStopName: fromStop.name,
                    endStopName: toStop.name,
                    startStopCode: fromStop.platform,
                    endStopCode: toStop.platform,
                    startDeparture: date(start),
                    endArrival: date(end),
                    routeType: 64,
                    tripHeadsign: "Walk",
                    routeShortName: nil,
                    startStopGps: fromStop.gps,
                    endStopGps: toStop.gps
                ))
                walkSeconds += Int(end - start)
                insertZone(of: from, into: &zones)
                insertZone(of: to, into: &zones)
            case let .ride(ride):
                let route = context.routes[Int(ride.route)]
                let trip = context.trips[Int(route.trips[Int(ride.trip)])]
                let row = Int(ride.trip) * route.stops.count
                let board = context.stops[Int(route.stops[Int(ride.board)])]
                let alight = context.stops[Int(route.stops[Int(ride.alight)])]
                let boardTime = route.departures[row + Int(ride.board)]
                let alightTime = route.arrivals[row + Int(ride.alight)]
                parts.append(Part(
                    startStopName: board.name,
                    endStopName: alight.name,
                    startStopCode: board.platform,
                    endStopCode: alight.platform,
                    startDeparture: date(boardTime),
                    endArrival: date(alightTime),
                    routeType: trip.routeType,
                    tripHeadsign: trip.headsign,
                    routeShortName: trip.routeShortName,
                    startStopGps: board.gps,
                    endStopGps: alight.gps
                ))
                rides.append(OfflineRide(
                    tripKey: trip.key,
                    boardStopId: board.id,
                    alightStopId: alight.id,
                    boardTime: Int(boardTime),
                    alightTime: Int(alightTime)
                ))
                for position in Int(ride.board)...Int(ride.alight) {
                    insertZone(of: route.stops[position], into: &zones)
                }
            }
        }
        let dayStart = context.dayStart
        return OfflineJourneyCandidate(
            rides: rides,
            parts: parts,
            zones: zones,
            arrivalSeconds: parts.last.map { Int($0.endArrival.timeIntervalSince(dayStart)) } ?? 0,
            departureSeconds: parts.first.map { Int($0.startDeparture.timeIntervalSince(dayStart)) } ?? 0,
            transferCount: max(0, rides.count - 1),
            walkSeconds: walkSeconds
        )
    }

    private func date(_ seconds: Int32) -> Date {
        context.dayStart.addingTimeInterval(TimeInterval(seconds))
    }

    private func insertZone(of stop: Int32, into zones: inout Set<String>) {
        if let zone = context.stops[Int(stop)].zone, !zone.isEmpty {
            zones.insert(zone)
        }
    }
}

private struct Endpoint {
    let stop: Int32
    /// Seconds between the stop and `anchor`, the named stop it is reached from or walked to.
    let walk: Int32
    let anchor: Int32
}

/// A ride on one trip of a route; positions index `OfflineRoute.stops`.
private struct Ride {
    let route: Int32
    /// Row of the trip in the route.
    let trip: Int32
    let board: Int32
    let alight: Int32
}

private enum Leg {
    case walk(from: Int32, to: Int32, start: Int32, end: Int32)
    case ride(Ride)
}

/// How a stop's arrival in one round was reached.
private enum Label {
    case unreached
    case origin
    /// The same arrival as with one ride fewer.
    case inherited
    case ride(Ride)
    /// Walked from where the ride alighted. The ride is kept here so the path stays intact
    /// even when that stop's own label later improves.
    case walk(from: Int32, after: Ride)
}

/// The first trip row below `end` that leaves `position` at or after `time`, or `end` when none does.
private func firstTrip(in route: OfflineRoute, at position: Int, departingAtOrAfter time: Int32, before end: Int) -> Int {
    let stopCount = route.stops.count
    var low = 0
    var high = end
    while low < high {
        let mid = (low + high) / 2
        if route.departures[mid * stopCount + position] < time {
            low = mid + 1
        } else {
            high = mid
        }
    }
    return low
}

/// The rRAPTOR labels of one query; `run` is called with ever earlier departures.
private final class Search {
    static let unreached = Int32.max / 2

    private let context: OfflineRoutingContext
    private let origins: [Endpoint]
    private let destinations: [Endpoint]
    private let rounds: Int
    private let stopCount: Int
    /// Arrivals at the named destination must be earlier than this.
    private let arrivalBound: Int32
    private var originWalk: [Int32: Endpoint]
    /// Walk from each stop to the named destination, or -1.
    private var egress: [Int32]
    /// Index into `destinations` of each stop, or -1.
    private var destinationIndex: [Int32]
    /// Indexed `round * stopCount + stop`; round k never arrives later than round k - 1.
    private var arrival: [Int32]
    private var label: [Label]
    /// The earliest ride arrival at each destination stop by round, indexed `round * destinations.count + destination`.
    /// Kept apart from `label`, which a walk to the stop can replace although the ride still ends with the final walk.
    private var finalArrival: [Int32]
    private var finalRide: [Ride?]
    /// Best arrival at the destination with at most k rides after the previous run, by round.
    private var bestByRound: [Int32]
    private var isMarked: [Bool]
    private var wasMarked: [Bool]
    /// Earliest marked position per route, -1 when the route is not queued.
    private var routeStart: [Int32]

    init(context: OfflineRoutingContext, origins: [Endpoint], destinations: [Endpoint], rounds: Int, latestArrival: Int32) {
        self.context = context
        self.origins = origins
        self.destinations = destinations
        self.rounds = rounds
        stopCount = context.stops.count
        arrivalBound = latestArrival + 1
        originWalk = Dictionary(uniqueKeysWithValues: origins.map { ($0.stop, $0) })
        egress = Array(repeating: -1, count: stopCount)
        destinationIndex = Array(repeating: -1, count: stopCount)
        for (index, destination) in destinations.enumerated() {
            egress[Int(destination.stop)] = destination.walk
            destinationIndex[Int(destination.stop)] = Int32(index)
        }
        arrival = Array(repeating: Self.unreached, count: (rounds + 1) * stopCount)
        label = Array(repeating: .unreached, count: (rounds + 1) * stopCount)
        finalArrival = Array(repeating: Self.unreached, count: (rounds + 1) * destinations.count)
        finalRide = Array(repeating: nil, count: (rounds + 1) * destinations.count)
        bestByRound = Array(repeating: latestArrival + 1, count: rounds + 1)
        isMarked = Array(repeating: false, count: stopCount)
        wasMarked = Array(repeating: false, count: stopCount)
        routeStart = Array(repeating: -1, count: context.routes.count)
    }

    /// One RAPTOR run leaving at `departure`; returns the legs of every journey that improves
    /// the arrival for its number of rides over all later departures.
    func run(departure: Int32) -> [[Leg]] {
        var marked = [Int32]()
        for origin in origins where improve(0, origin.stop, departure + origin.walk, .origin) {
            mark(origin.stop, in: &marked)
        }
        var bound = arrivalBound
        for round in 1...rounds {
            if marked.isEmpty { break }
            bound = min(bound, bestDestination(round).arrival)
            for stop in marked {
                isMarked[Int(stop)] = false
                wasMarked[Int(stop)] = true
                for routeStop in context.routesAtStop[Int(stop)] {
                    let route = Int(routeStop.route)
                    if routeStart[route] < 0 || routeStop.position < routeStart[route] {
                        routeStart[route] = routeStop.position
                    }
                }
            }
            let boardable = marked
            marked.removeAll(keepingCapacity: true)
            for stop in boardable {
                for routeStop in context.routesAtStop[Int(stop)] where routeStart[Int(routeStop.route)] >= 0 {
                    scan(route: Int(routeStop.route), round: round, bound: &bound, marked: &marked)
                }
            }
            for stop in boardable {
                wasMarked[Int(stop)] = false
            }
            walk(round: round, bound: &bound, marked: &marked)
        }
        for stop in marked {
            isMarked[Int(stop)] = false
        }

        var journeys = [[Leg]]()
        var fewerRides = arrivalBound
        for round in 1...rounds {
            let best = bestDestination(round)
            if best.arrival < fewerRides && best.arrival < bestByRound[round] {
                journeys.append(legs(round: round, destination: best.destination, byRide: best.byRide))
            }
            fewerRides = min(fewerRides, best.arrival)
            bestByRound[round] = fewerRides
        }
        return journeys
    }

    private func scan(route routeIndex: Int, round: Int, bound: inout Int32, marked: inout [Int32]) {
        let route = context.routes[routeIndex]
        let stopCount = route.stops.count
        let start = Int(routeStart[routeIndex])
        routeStart[routeIndex] = -1
        var trip = -1
        var board = 0
        for position in start..<stopCount {
            let stop = route.stops[position]
            if trip >= 0 {
                let time = route.arrivals[trip * stopCount + position]
                if time < bound {
                    let ride = Ride(route: Int32(routeIndex), trip: Int32(trip), board: Int32(board), alight: Int32(position))
                    if improve(round, stop, time, .ride(ride)) {
                        mark(stop, in: &marked)
                    }
                    // A ride to a stop the rider could walk to from the origin by then is no journey.
                    let destination = Int(destinationIndex[Int(stop)])
                    if destination >= 0, time < arrival[Int(stop)], time < finalArrival[round * destinations.count + destination] {
                        finalArrival[round * destinations.count + destination] = time
                        finalRide[round * destinations.count + destination] = ride
                        bound = min(bound, time + egress[Int(stop)])
                    }
                }
            }
            guard position < stopCount - 1, wasMarked[Int(stop)] else { continue }
            let ready = readyTime(round - 1, stop)
            if trip >= 0 && route.departures[trip * stopCount + position] < ready { continue }
            let end = trip >= 0 ? trip : route.trips.count
            let earlier = firstTrip(in: route, at: position, departingAtOrAfter: ready, before: end)
            if earlier < end {
                trip = earlier
                board = position
            }
        }
    }

    /// One walk from every stop a ride reached this round. Walks only follow rides, so a journey
    /// never walks twice in a row and the walk to the named destination comes from the ride too.
    private func walk(round: Int, bound: inout Int32, marked: inout [Int32]) {
        let sources = marked.compactMap { stop -> (stop: Int32, time: Int32, ride: Ride)? in
            let index = round * stopCount + Int(stop)
            guard case let .ride(ride) = label[index] else { return nil }
            return (stop, arrival[index], ride)
        }
        for source in sources {
            for footpath in context.footpaths[Int(source.stop)] {
                let time = source.time + footpath.seconds
                if time >= bound { break }
                if improve(round, footpath.stop, time, .walk(from: source.stop, after: source.ride)) {
                    mark(footpath.stop, in: &marked)
                    if egress[Int(footpath.stop)] == 0 {
                        bound = min(bound, time)
                    }
                }
            }
        }
    }

    /// Sets the arrival if it is earlier, and carries it to the rounds above that arrive later.
    private func improve(_ round: Int, _ stop: Int32, _ time: Int32, _ newLabel: Label) -> Bool {
        let index = round * stopCount + Int(stop)
        guard time < arrival[index] else { return false }
        arrival[index] = time
        label[index] = newLabel
        var above = index + stopCount
        while above < arrival.count, time < arrival[above] {
            arrival[above] = time
            label[above] = .inherited
            above += stopCount
        }
        return true
    }

    private func mark(_ stop: Int32, in marked: inout [Int32]) {
        if !isMarked[Int(stop)] {
            isMarked[Int(stop)] = true
            marked.append(stop)
        }
    }

    /// The label that set this round's arrival, looking through inherited ones.
    private func source(_ round: Int, _ stop: Int32) -> Label {
        var round = round
        while round > 0, case .inherited = label[round * stopCount + Int(stop)] {
            round -= 1
        }
        return label[round * stopCount + Int(stop)]
    }

    /// When a rider at the stop can board: arriving by ride needs the transfer buffer.
    private func readyTime(_ round: Int, _ stop: Int32) -> Int32 {
        let time = arrival[round * stopCount + Int(stop)]
        if case .ride = source(round, stop) {
            return time + OfflineTimetableRouter.transferBufferSeconds
        }
        return time
    }

    /// The earliest arrival at the named destination in this round: a ride to a destination stop
    /// and its walk to the named stop, or a walk that ends at a named stop. Arrivals without a ride
    /// do not count, nor a walk that would need a second walk to reach the named stop.
    private func bestDestination(_ round: Int) -> (arrival: Int32, destination: Int, byRide: Bool) {
        var best = (arrival: Self.unreached, destination: -1, byRide: false)
        for (index, destination) in destinations.enumerated() {
            let byRide = finalArrival[round * destinations.count + index] + destination.walk
            if byRide < best.arrival {
                best = (byRide, index, true)
            }
            let time = arrival[round * stopCount + Int(destination.stop)]
            if destination.walk == 0, time < best.arrival, case .walk = source(round, destination.stop) {
                best = (time, index, false)
            }
        }
        return best
    }

    private func legs(round: Int, destination index: Int, byRide: Bool) -> [Leg] {
        var reversed = [Leg]()
        var round = round
        let destination = destinations[index]
        var stop = destination.stop
        if byRide, let ride = finalRide[round * destinations.count + index] {
            let time = finalArrival[round * destinations.count + index]
            if destination.walk > 0 {
                reversed.append(.walk(from: stop, to: destination.anchor, start: time, end: time + destination.walk))
            }
            reversed.append(.ride(ride))
            stop = context.routes[Int(ride.route)].stops[Int(ride.board)]
            round -= 1
        }
        while round >= 0 {
            switch label[round * stopCount + Int(stop)] {
            case .inherited:
                round -= 1
            case let .ride(ride):
                reversed.append(.ride(ride))
                stop = context.routes[Int(ride.route)].stops[Int(ride.board)]
                round -= 1
            case let .walk(from, ride):
                let route = context.routes[Int(ride.route)]
                let alighted = route.arrivals[Int(ride.trip) * route.stops.count + Int(ride.alight)]
                reversed.append(.walk(from: from, to: stop, start: alighted, end: arrival[round * stopCount + Int(stop)]))
                reversed.append(.ride(ride))
                stop = route.stops[Int(ride.board)]
                round -= 1
            case .origin:
                // Leave as late as possible: walk so as to reach the first trip as it departs.
                if let origin = originWalk[stop], origin.walk > 0, case let .ride(first)? = reversed.last {
                    let route = context.routes[Int(first.route)]
                    let boards = route.departures[Int(first.trip) * route.stops.count + Int(first.board)]
                    reversed.append(.walk(from: origin.anchor, to: stop, start: boards - origin.walk, end: boards))
                }
                return reversed.reversed()
            case .unreached:
                return reversed.reversed()
            }
        }
        return reversed.reversed()
    }
}
