//
//  TripLiveActivityController.swift
//  Transi
//
//  Created by magic_sk on 04/10/2026.
//

import ActivityKit
import Combine
import Foundation

/// Runs the trip Live Activity: one journey at a time, followed on live departure boards until it arrives.
/// Call on the main thread.
final class TripLiveActivityController: ObservableObject {
    /// The journey being followed, so its StartTripButton offers to end it.
    @Published private(set) var journey: Journey?
    /// Where the traveller is on `journey`, which its detail follows on the map and marks in the steps.
    @Published private(set) var progress: TripProgress?
    /// The step the Live Activity shows, which the detail repeats above its summary.
    @Published private(set) var state: TripActivityAttributes.ContentState?
    /// `journey`'s delays on the live boards (seconds, by part index), which its detail shows too.
    @Published private(set) var liveDelays = [Int: Int]()
    /// The ride the traveller is not on, may not be on, or cannot change to, with the other connections its detail
    /// offers.
    @Published private(set) var missed: TripMissed?

    /// A trip is followed while its journey is saved, which also makes this safe to read from any thread.
    static var followsTrip: Bool { UserDefaults.standard.data(forKey: Stored.tripLiveActivities) != nil }

    private var activityId: String?
    private var live = TripLiveData() {
        didSet {
            if live.delays != liveDelays {
                liveDelays = live.delays
            }
        }
    }
    /// Set by a relaunch until a live board answers, so the trip does not end on stale saved delays.
    private var awaitsLiveData = false
    private var trackers = [TripTrackerTarget: PartLiveTracker]()
    private var ticker: AnyCancellable?
    /// The journeys found to the destination for `search`; nil until the search answers.
    private var found: [Journey]?
    /// The ride `found` was searched for, without its other connections.
    private var search: TripMissed?
    private var searchedAt: Date?
    /// The last update sent to the activity, which an answer from it waits for before the app may suspend again.
    private var sending: Task<Void, Never>?

    /// Shows `journey` as a Live Activity and ends the trip followed so far; table activities stay.
    func start(_ journey: Journey) {
        end()
        // The location is checked against the stops' positions.
        let journey = journey.positioned(in: GlobalController.stopsListProvider.stops)
        let update = journey.update(at: Date(), delays: journey.delays(live: [:]))
        do {
            let activity = try Activity.request(
                attributes: TripActivityAttributes(), contentState: update.state, pushType: nil
            )
            // Only once it runs, so a trip that could not start stays scheduled.
            GlobalController.tripSchedule.cancel(journey: journey)
            follow(journey, activityId: activity.id, state: update.state)
        } catch {
            #if DEBUG
            print("Trip Live Activity did not start: \(error)")
            #endif
        }
    }

    func end() {
        guard let activityId else { return }
        stopFollowing()
        Task { await TripLiveActivityController.activity(activityId)?.end(dismissalPolicy: .immediate) }
    }

    /// Follows the activity a scheduled trip started by itself, in place of the trip followed so far.
    func follow(_ journey: Journey, startedAs activity: Activity<TripActivityAttributes>) {
        end()
        follow(journey, activityId: activity.id, state: activity.contentState)
    }

    /// Follows the trip activity again after the app relaunched, and ends trip activities without a saved journey
    /// that no scheduled trip owns either.
    func restore() {
        let saved = UserDefaults.standard.retrieve(
            object: [String: SavedTrip].self, forKey: Stored.tripLiveActivities
        ) ?? [:]
        let scheduled = Set(GlobalController.tripSchedule.trips.compactMap(\.activityId))
        for activity in Activity<TripActivityAttributes>.activities where Self.isRunning(activity) {
            if journey == nil, let trip = saved[activity.id] {
                awaitsLiveData = true
                follow(trip.journey, live: trip.live, activityId: activity.id, state: activity.contentState)
            } else if !scheduled.contains(activity.id) {
                let id = activity.id
                Task { await TripLiveActivityController.activity(id)?.end(dismissalPolicy: .immediate) }
            }
        }
        if journey == nil {
            UserDefaults.standard.removeObject(forKey: Stored.tripLiveActivities)
        }
    }

    private func follow(
        _ journey: Journey, live: TripLiveData = TripLiveData(), activityId: String,
        state: TripActivityAttributes.ContentState
    ) {
        self.journey = journey
        self.live = live
        self.activityId = activityId
        self.state = state
        save()
        GlobalController.startBackgroundMode()
        ticker = Timer.publish(every: 15, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            self?.refresh()
        }
        loadStops(of: journey, for: activityId)
        refresh()
    }

    private struct SavedTrip: Codable {
        let journey: Journey
        let live: TripLiveData
    }

    private func save() {
        guard let activityId, let journey else { return }
        UserDefaults.standard.save(
            customObject: [activityId: SavedTrip(journey: journey, live: live)], forKey: Stored.tripLiveActivities
        )
    }

    /// Loads the stop lists that R-API legs leave out, with the B-API delay. A leg whose fetch fails keeps
    /// only its boarding and alighting stops.
    private func loadStops(of journey: Journey, for activityId: String) {
        let parts = journey.parts ?? []
        let missing = parts.indices.filter { parts[$0].stops == nil && parts[$0].tripId != nil }
        guard !missing.isEmpty else { return }
        var loaded = journey
        let group = DispatchGroup()
        for index in missing {
            group.enter()
            GlobalController.tripPlanner.fetchStops(for: parts[index]) { stops, delay in
                loaded.parts?[index].stops = stops
                loaded.parts?[index].delaySeconds = delay ?? parts[index].delaySeconds
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            guard let self, self.activityId == activityId else { return }
            // Stop indices now point into the full stop lists.
            self.watch([], of: loaded)
            self.live.passedStops = self.live.passedStops.filter { !missing.contains($0.key) }
            self.live.dropped = self.live.dropped.filter { !missing.contains($0.key) }
            self.live.located = self.live.located.filter { !missing.contains($0.key) }
            self.live.listed = self.live.listed.filter { !missing.contains($0.key.part) }
            self.journey = loaded
            self.save()
            self.refresh()
        }
    }

    /// Recomputes the step every 15 s and on every live update, and sends it when it changed.
    private func refresh() {
        guard let journey, let activityId, let state else { return }
        guard let activity = Self.activity(activityId), Self.isRunning(activity) else {
            // Dismissed on the Lock Screen or ended by the system.
            stopFollowing()
            return
        }
        let now = Date()
        let fix = Self.fix(at: now)
        let before = live
        var missed = live.locate(fix, on: journey, now: now)
        if live.needsSaving(since: before) {
            save()
        }
        if let ride = missed {
            if !(search.map(ride.canReuse) ?? false) {
                // Another ride or change stop, or an earlier arrival: what was found may not answer it.
                search = ride
                found = nil
                searchedAt = nil
            }
            missed?.alternatives = found.map {
                journey.alternatives($0, missed: ride.part, at: max(now, ride.at ?? now))
            }
            if missed?.alternatives?.isEmpty ?? true {
                findAlternatives(ride, of: journey, at: now, fix: fix)
            }
        } else if search != nil {
            search = nil
            found = nil
            searchedAt = nil
        }
        if self.missed != missed {
            self.missed = missed
        }
        let update = journey.update(
            at: now, delays: journey.delays(live: live.delays), passedStops: live.positions,
            vehicleStops: live.lastStops, alerted: state.alerted, fix: fix, missed: missed
        )
        let newState = update.state
        if progress != update.progress {
            progress = update.progress
        }
        let isMissed = missed?.kind == .missed
        if update.progress.phase != .arrived {
            // Once a ride is missed, the trip's vehicles no longer matter.
            watch(isMissed ? [] : journey.trackerTargets(for: update.progress, dropped: live.dropped), of: journey)
        } else if isMissed || tripCanEnd(at: now, arrival: newState.time, awaitsLiveData: awaitsLiveData) {
            // A missed trip ends when it would have arrived; its boards are no longer watched.
            stopFollowing()
            Task {
                await TripLiveActivityController.activity(activityId)?.end(
                    using: newState, dismissalPolicy: .after(newState.time.addingTimeInterval(5 * 60))
                )
            }
            return
        } else {
            // Ask the last vehicle's board whether it runs later than saved.
            let lastLeg = journey.parts?.lastIndex { $0.routeType != 64 }
            watch(lastLeg.map { journey.trackerTargets(for: TripProgress(phase: .ride($0))) } ?? [], of: journey)
        }
        guard newState != state else { return }
        self.state = newState
        let alert = update.alert.map {
            AlertConfiguration(title: "\($0.title)", body: "\($0.body)", sound: .named(""))
        }
        sending = Task {
            await TripLiveActivityController.activity(activityId)?.update(using: newState, alertConfiguration: alert)
            if alert != nil {
                await VirtualTableLiveActivityController.playAlertSound()
            }
        }
    }

    /// Keeps following the trip's steps for the ride missed or asked about, which the location then no longer checks.
    func keepFollowing() {
        guard let index = live.missed ?? live.suspected else { return }
        live.kept.insert(index)
        live.missed = nil
        live.suspected = nil
        live.missedChange = false
        live.offRide = [:]
        found = nil
        search = nil
        searchedAt = nil
        save()
        refresh()
    }

    /// Takes the ride asked about as missed, so the trip offers the other connections instead of its steps.
    func confirmMissed() {
        guard let index = live.suspected else { return }
        live.missed = index
        live.suspected = nil
        // They chose the other connections, which the trip shows at once: no alert to tell them again.
        state?.alerted.insert("lost-\(index)")
        save()
        refresh()
    }

    /// The traveller's answer to the trip's question from its Live Activity: still on the ride, as keepFollowing(), or
    /// not, as confirmMissed(). Returns once the activity shows it, so the app may suspend again.
    @MainActor
    func answer(stillOn: Bool) async {
        if stillOn {
            keepFollowing()
        } else {
            confirmMissed()
        }
        await sending?.value
    }

    /// The traveller's last location when it tells stops apart: within 100 m, from the last half hour (it updates every
    /// 50 m, so standing at a stop keeps an older one), with its speed and course where known.
    private static func fix(at now: Date) -> TripFix? {
        guard let location = LocationProvider.lastLocation, (0 ... 100).contains(location.horizontalAccuracy),
              now.timeIntervalSince(location.timestamp) < 1800
        else { return nil }
        let coordinate = location.coordinate
        return TripFix(
            gps: StopGps(lon: coordinate.longitude, lat: coordinate.latitude), accuracy: location.horizontalAccuracy,
            speed: location.speed >= 0 ? location.speed : nil, course: location.course >= 0 ? location.course : nil,
            time: location.timestamp
        )
    }

    /// Searches to the trip's destination: from the change stop at the arriving ride's expected arrival, else from the
    /// stop nearest `fix` now; again 2 minutes after a search found nothing still to catch. Without a location it
    /// searches from the boarding stop of a ride not boarded, and waits for one after a boarded ride, which took the
    /// traveller away from that stop.
    private func findAlternatives(_ missed: TripMissed, of journey: Journey, at now: Date, fix: TripFix?) {
        let index = missed.part
        let change = missed.arriving.flatMap { journey.parts?[$0] }
        guard change != nil || fix != nil || !live.boarded.contains(index),
              searchedAt.map({ now.timeIntervalSince($0) >= 120 }) ?? true, let activityId
        else { return }
        searchedAt = now
        let stops = GlobalController.stopsListProvider.stops
        let from: Stop?
        if let change {
            from = stops.stop(stationId: change.endStationId, name: change.endStopName, platform: change.endStopCode)
        } else if let fix {
            // Measured from the fix: the list is sorted by the location only some time after it updates.
            from = stops.filter { $0.id > 0 }
                .compactMap { stop in stop.gps.map { (stop: stop, meters: fix.gps.distance(to: $0)) } }
                .min { $0.meters < $1.meters }?.stop
        } else {
            let part = journey.parts?[index]
            from = stops.stop(stationId: part?.startStationId, name: part?.startStopName, platform: part?.startStopCode)
        }
        let last = journey.parts?.last
        guard let from, let to = stops.stop(stationId: last?.endStationId, name: last?.endStopName, platform: nil) else {
            found = []
            return
        }
        let search = self.search
        GlobalController.tripPlanner.searchJourneys(from: from, to: to, at: max(now, missed.at ?? now)) {
            [weak self] journeys in
            guard let self, self.activityId == activityId, self.search == search else { return }
            self.found = journeys
            self.refresh()
        }
    }

    /// Keeps one live board tracker per target and stops the rest, so only the current step's sockets stay open.
    private func watch(_ targets: [TripTrackerTarget], of journey: Journey) {
        for (target, tracker) in trackers where !targets.contains(target) {
            tracker.stop()
            trackers[target] = nil
        }
        let parts = journey.parts ?? []
        for target in targets where trackers[target] == nil {
            let part = parts[target.part]
            // Nil while the stops list is still loading; the next refresh tries again.
            trackers[target] = PartLiveTracker(
                part: part, at: target.stop == 0 ? nil : part.legStops[target.stop], busID: live.busIDs[target.part]
            ) { [weak self] connection, _ in
                self?.receive(connection, at: target)
            }
        }
    }

    private func receive(_ connection: Connection?, at target: TripTrackerTarget) {
        guard let journey else { return }
        let followed = (live.delays, live.busIDs, live.passedStops, live.dropped, live.lastStops)
        live.receive(connection, at: target, of: journey, now: Date())
        if connection?.liveDelaySeconds != nil {
            awaitsLiveData = false
        }
        // Saved when a delay (whole minutes), the vehicle or its position changes, not on every board update.
        if followed != (live.delays, live.busIDs, live.passedStops, live.dropped, live.lastStops) {
            save()
        }
        refresh()
    }

    private func stopFollowing() {
        ticker = nil
        trackers.values.forEach { $0.stop() }
        trackers = [:]
        live = TripLiveData()
        awaitsLiveData = false
        found = nil
        search = nil
        searchedAt = nil
        sending = nil
        missed = nil
        journey = nil
        activityId = nil
        progress = nil
        state = nil
        UserDefaults.standard.removeObject(forKey: Stored.tripLiveActivities)
        if GlobalController.appState.phase == .background {
            // Table activities only need the app kept running.
            GlobalController.locationProvider.decreaseAccuracy()
        }
        GlobalController.stopBackgroundMode()
    }

    private static func activity(_ id: String) -> Activity<TripActivityAttributes>? {
        Activity<TripActivityAttributes>.activities.first { $0.id == id }
    }

    private static func isRunning(_ activity: Activity<TripActivityAttributes>) -> Bool {
        activity.activityState != .ended && activity.activityState != .dismissed
    }
}
