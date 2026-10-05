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

    /// Shows `journey` as a Live Activity and ends the trip followed so far; table activities stay.
    func start(_ journey: Journey) {
        end()
        let update = journey.update(at: Date(), delays: journey.delays(live: [:]))
        do {
            let activity = try Activity.request(
                attributes: TripActivityAttributes(), contentState: update.state, pushType: nil
            )
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

    /// Follows the trip activity again after the app relaunched, and ends trip activities without a saved journey.
    func restore() {
        let saved = UserDefaults.standard.retrieve(
            object: [String: SavedTrip].self, forKey: Stored.tripLiveActivities
        ) ?? [:]
        for activity in Activity<TripActivityAttributes>.activities where Self.isRunning(activity) {
            if journey == nil, let trip = saved[activity.id] {
                awaitsLiveData = true
                follow(trip.journey, live: trip.live, activityId: activity.id, state: activity.contentState)
            } else {
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
        let update = journey.update(
            at: now, delays: journey.delays(live: live.delays), passedStops: live.passedStops, alerted: state.alerted
        )
        let newState = update.state
        if progress != update.progress {
            progress = update.progress
        }
        if update.progress.phase != .arrived {
            watch(journey.trackerTargets(for: update.progress), of: journey)
        } else if tripCanEnd(at: now, arrival: newState.time, awaitsLiveData: awaitsLiveData) {
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
        Task {
            await TripLiveActivityController.activity(activityId)?.update(using: newState, alertConfiguration: alert)
            if alert != nil {
                await VirtualTableLiveActivityController.playAlertSound()
            }
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
        let followed = (live.delays, live.busIDs, live.passedStops)
        live.receive(connection, at: target, of: journey, now: Date())
        if connection?.liveDelaySeconds != nil {
            awaitsLiveData = false
        }
        // Saved when a delay (whole minutes), the vehicle or its position changes, not on every board update.
        if followed != (live.delays, live.busIDs, live.passedStops) {
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
        journey = nil
        activityId = nil
        progress = nil
        state = nil
        UserDefaults.standard.removeObject(forKey: Stored.tripLiveActivities)
        GlobalController.stopBackgroundMode()
    }

    private static func activity(_ id: String) -> Activity<TripActivityAttributes>? {
        Activity<TripActivityAttributes>.activities.first { $0.id == id }
    }

    private static func isRunning(_ activity: Activity<TripActivityAttributes>) -> Bool {
        activity.activityState != .ended && activity.activityState != .dismissed
    }
}
