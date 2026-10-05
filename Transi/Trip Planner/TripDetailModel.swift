//
//  TripDetailModel.swift
//  Transi
//
//  Created by magic_sk on 04/10/2026.
//

import Combine
import Foundation

/// One row of the journey detail's step list.
enum JourneyStep: Hashable {
    /// A transit leg, by part index.
    case ride(Int)
    /// Walk parts by index, then the ride they lead to; nil when the walk ends the journey.
    case walk([Int], to: Int?)
    /// A change between two rides with no walk part, into the ride at this index.
    case change(to: Int)
}

extension Journey {
    /// The rides, the walks before them, and the changes that need no walk.
    var steps: [JourneyStep] {
        var steps = [JourneyStep]()
        var walks = [Int]()
        var hasRidden = false
        for (index, part) in (parts ?? []).enumerated() {
            if part.routeType == 64 {
                walks.append(index)
                continue
            }
            if !walks.isEmpty {
                steps.append(.walk(walks, to: index))
            } else if hasRidden {
                steps.append(.change(to: index))
            }
            steps.append(.ride(index))
            walks = []
            hasRidden = true
        }
        if !walks.isEmpty {
            steps.append(.walk(walks, to: nil))
        }
        return steps
    }

    var rideCount: Int {
        parts?.filter { $0.routeType != 64 }.count ?? 0
    }

    var walkMinutes: Int {
        parts?.filter { $0.routeType == 64 }.reduce(0) { $0 + $1.minutes } ?? 0
    }

    /// The fare zones of the known stops, in travel order; empty until a leg knows its stops.
    var zoneNames: [String] {
        var names = [String]()
        for zone in (parts ?? []).flatMap({ $0.stops ?? [] }).compactMap(\.zone) where !names.contains(zone) {
            names.append(zone)
        }
        return names
    }
}

extension Part {
    var minutes: Int {
        minutesBetween(startDeparture, endArrival)
    }

    /// Not arrived yet, and departing within the hour or already departed: while its vehicle's live
    /// departure and delay are this leg's. A known delay (seconds) moves the end to the expected arrival.
    func isLive(at now: Date = Date(), delaySeconds: Int? = nil) -> Bool {
        endArrival.addingTimeInterval(TimeInterval(max(delaySeconds ?? 0, 0))) > now
            && startDeparture < now.addingTimeInterval(3600)
    }
}

enum MapFocus: Equatable {
    case route
    case part(Int)
    /// The change into the ride at this index: the previous ride's end (or the journey's start), the walks,
    /// this ride's start.
    case change(to: Int)
    case stop(StopGps)
    /// Stops of a ride, around where its vehicle is.
    case stretch([StopGps])
}

extension TripProgress {
    /// The step row the traveller is at: the walk or change to the next vehicle until it leaves, the ride, then the
    /// walk after the last vehicle.
    func step(in journey: Journey) -> JourneyStep? {
        let steps = journey.steps
        switch phase {
        case .board(let index), .change(let index):
            guard let ride = steps.firstIndex(of: .ride(index)) else { return nil }
            return steps[max(ride - 1, 0)]
        case .ride(let index):
            return .ride(index)
        case .walk:
            return steps.last
        case .arrived:
            return nil
        }
    }

    /// What the map follows: the walk to and the stop of the next vehicle, the vehicle from the stop it left through
    /// the next one (through the alighting stop once that is 2 stops away), the walk, then the whole route.
    /// `journey` is the one the progress was computed on, whose leg stops `nextStop` counts.
    func mapFocus(on journey: Journey) -> MapFocus {
        switch phase {
        case .board(let index), .change(let index):
            return .change(to: index)
        case .ride(let index):
            let stops = journey.parts?[index].legStops ?? []
            guard let nextStop, stops.count > 1 else { return .part(index) }
            let last = stops.count - 1
            // Past the alighting stop the vehicle still counts as reaching it.
            let next = max(min(nextStop, last), 1)
            let stretch = stops[(next - 1) ... (next >= last - 1 ? last : next)].compactMap(\.gps)
            return stretch.isEmpty ? .part(index) : .stretch(stretch)
        case .walk(let index):
            return .part(index)
        case .arrived:
            return .route
        }
    }
}

/// The journey shown in the detail, completed while it is visible: the stops of R-API legs and the live
/// departures of legs leaving within the hour.
final class TripDetailModel: ObservableObject {
    enum StopsState {
        case loading, failed
    }

    @Published private(set) var journey: Journey
    @Published private(set) var stopsState = [Int: StopsState]()
    /// Departures matched on the boarding stop's live board, by part index.
    @Published private(set) var liveConnections = [Int: Connection]()
    /// B-API trip delays in seconds, by part index, fetched with the stops while the leg was live; nil when
    /// its vehicle was not running.
    @Published private(set) var tripDelays = [Int: Int?]()
    /// Set by the map.
    var onFocus: ((MapFocus) -> Void)?
    /// Set by the map, which fits the sheet's summary detent to it: the summary's frame in the window.
    var onSummaryFrame: ((CGRect) -> Void)?
    /// Sent by the map when the sheet comes down to the summary with the list scrolled past it.
    let showSummary = PassthroughSubject<Void, Never>()

    private var trackers = [Int: PartLiveTracker]()
    private var trackerTimer: Timer?
    /// The vehicle followed on each leg, so a restarted tracker never picks the line's next departure.
    private var busIDs = [Int: String]()
    private var liveParts = Set<Int>()

    /// Call on the main thread.
    init(journey: Journey) {
        // Offline results and trips saved by older versions have no positions; use the stations'.
        var journey = journey
        let stops = GlobalController.stopsListProvider.stops
        for index in journey.parts?.indices ?? 0 ..< 0 {
            guard var part = journey.parts?[index] else { continue }
            part.startStopGps = part.startStopGps ?? stops.stop(
                stationId: part.startStationId, name: part.startStopName, platform: part.startStopCode
            )?.gps
            part.endStopGps = part.endStopGps ?? stops.stop(
                stationId: part.endStationId, name: part.endStopName, platform: part.endStopCode
            )?.gps
            journey.parts?[index] = part
        }
        self.journey = journey
    }

    /// Loads missing stops and follows the legs leaving soon; `stop()` ends the live updates.
    func start() {
        guard trackerTimer == nil else { return }
        for (index, part) in (journey.parts ?? []).enumerated()
            where part.tripId != nil && part.stops == nil && stopsState[index] != .loading
        {
            loadStops(index)
        }
        updateTrackers()
        trackerTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.updateTrackers()
        }
    }

    /// Keeps the last known delays: a restarted tracker only finds a vehicle still at the boarding stop.
    func stop() {
        trackerTimer?.invalidate()
        trackerTimer = nil
        trackers.values.forEach { $0.stop() }
        trackers.removeAll()
    }

    func loadStops(_ index: Int) {
        guard let part = journey.parts?[index] else { return }
        stopsState[index] = .loading
        GlobalController.tripPlanner.fetchStops(for: part) { [weak self] stops, delaySeconds in
            guard let self else { return }
            guard let stops else {
                self.stopsState[index] = .failed
                return
            }
            self.journey.parts?[index].stops = stops
            // The B-API reports the run on the road now, whatever its date, so it is this leg's only while live.
            if part.isLive(delaySeconds: delaySeconds) {
                self.tripDelays.updateValue(delaySeconds, forKey: index)
            }
            self.stopsState[index] = nil
        }
    }

    /// Delay to show and to plan changes with while the leg is live, until its expected arrival.
    func delaySeconds(_ index: Int) -> Int? {
        guard let part = journey.parts?[index] else { return nil }
        let delay = knownDelaySeconds(index)
        return part.isLive(delaySeconds: delay) ? delay : nil
    }

    /// From the boards the trip Live Activity follows this journey's vehicles on, so the step it shows above the
    /// summary agrees (the sheet observes it, which redraws the delays); else the departure board (the last one
    /// seen), else the B-API's (nil when its vehicle was not running), else the one from the search. Nil when none
    /// is known.
    private func knownDelaySeconds(_ index: Int) -> Int? {
        let trip = GlobalController.tripLiveActivity
        if trip.journey == journey, let delay = trip.liveDelays[index] {
            return delay
        }
        if let connection = liveConnections[index], connection.type == "online" {
            return connection.delay * 60
        }
        if let tripDelay = tripDelays[index] {
            return tripDelay
        }
        return journey.parts?[index].delaySeconds
    }

    var transferBuffers: [Int: TransferBuffer] {
        let delays = (journey.parts ?? []).indices.compactMap { index in delaySeconds(index).map { (index, $0) } }
        return journey.transferBuffers(delays: Dictionary(uniqueKeysWithValues: delays))
    }

    func focus(_ target: MapFocus) {
        onFocus?(target)
    }

    // ponytail: one socket per leg leaving within the hour; share a board per stop if journeys get longer.
    private func updateTrackers() {
        let now = Date()
        let parts = journey.parts ?? []
        let live = Set(parts.indices.filter {
            parts[$0].routeType != 64 && parts[$0].isLive(at: now, delaySeconds: knownDelaySeconds($0))
        })
        if live != liveParts {
            // Delays only count while a leg is live.
            objectWillChange.send()
            liveParts = live
        }
        for (index, part) in parts.enumerated() where part.routeType != 64 {
            let isDue = live.contains(index)
            if isDue, trackers[index] == nil {
                trackers[index] = PartLiveTracker(part: part, busID: busIDs[index]) { [weak self] connection, _ in
                    guard let self else { return }
                    if let connection, connection.type == "online" {
                        self.busIDs[index] = connection.busID
                    }
                    // Once our vehicle has left the board, keep its last known delay rather than none.
                    guard connection != nil || self.busIDs[index] == nil,
                          self.liveConnections[index] != connection
                    else { return }
                    self.liveConnections[index] = connection
                }
            } else if !isDue, let tracker = trackers.removeValue(forKey: index) {
                tracker.stop()
            }
        }
    }

    deinit {
        trackerTimer?.invalidate()
    }
}
