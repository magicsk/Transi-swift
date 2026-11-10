//
//  TripScheduleController.swift
//  Transi
//
//  Created by magic_sk on 09/11/2026.
//

import ActivityKit
import UIKit
import UserNotifications

/// A journey the traveller wants to follow once it is close.
struct ScheduledTrip: Codable, Identifiable {
    let id: String
    let journey: Journey
    /// The Live Activity scheduled to start by itself at `startsAt`, on iOS 26 and later. Without one the trip only
    /// starts from its reminder.
    let activityId: String?
    let startsAt: Date?
    let remindsAt: Date?
}

/// The scheduled trips: their Live Activities, reminders, and what happens to them when one starts or is tapped.
/// Call on the main thread.
final class TripScheduleController: NSObject, ObservableObject {
    @Published private(set) var trips: [ScheduledTrip]

    /// The scheduled activities whose start is awaited while the app runs.
    private var watched = Set<String>()
    /// A tapped reminder, kept until the app is active: a Live Activity only starts from the foreground.
    private var tapped: (id: String, starts: Bool)?

    private static let startAction = "eu.magicsk.Transi.ScheduledTrip.start"
    private static let viewAction = "eu.magicsk.Transi.ScheduledTrip.view"
    private static let idKey = "scheduledTripId"

    /// The reminder's actions, shown on a long press: a plain tap starts the trip too.
    static let category = UNNotificationCategory(
        identifier: "eu.magicsk.Transi.ScheduledTrip",
        actions: [
            UNNotificationAction(
                identifier: startAction, title: NSLocalizedString("Start trip", comment: ""), options: .foreground
            ),
            UNNotificationAction(
                identifier: viewAction, title: NSLocalizedString("View trip", comment: ""), options: .foreground
            ),
        ],
        intentIdentifiers: []
    )

    override init() {
        trips = UserDefaults.standard.retrieve(object: [ScheduledTrip].self, forKey: Stored.scheduledTrips) ?? []
        super.init()
    }

    func trip(for journey: Journey) -> ScheduledTrip? {
        trips.first { $0.journey == journey }
    }

    /// Schedules `journey` with the times from Settings, which it keeps if they change later.
    func schedule(_ journey: Journey) {
        guard trip(for: journey) == nil, let departure = journey.parts?.first?.startDeparture else { return }
        let journey = journey.positioned(in: GlobalController.stopsListProvider.stops)
        let defaults = UserDefaults.standard
        let startMinutes = defaults.integer(forKey: Stored.tripStartMinutes)
        func before(_ minutes: Int) -> Date { departure.addingTimeInterval(-Double(minutes) * 60) }
        let activityId = requestActivity(of: journey, at: before(startMinutes), minutes: startMinutes)
        let reminderMinutes = scheduledTripReminderMinutes(
            reminder: defaults.integer(forKey: Stored.tripReminderMinutes), start: startMinutes,
            hasActivity: activityId != nil
        )
        let trip = ScheduledTrip(
            id: UUID().uuidString, journey: journey, activityId: activityId,
            startsAt: activityId == nil ? nil : before(startMinutes), remindsAt: reminderMinutes.map(before)
        )
        trips.append(trip)
        func leaves(_ trip: ScheduledTrip) -> Date { trip.journey.parts?.first?.startDeparture ?? .distantPast }
        trips.sort { leaves($0) < leaves($1) }
        save()
        addReminder(of: trip, minutes: reminderMinutes)
        sync()
    }

    /// Removes the trip with its reminder and its Live Activity, also one already started and not followed.
    func cancel(_ trip: ScheduledTrip) {
        remove(trip)
        guard let id = trip.activityId else { return }
        Task { await Activity<TripActivityAttributes>.activities.first { $0.id == id }?.end(dismissalPolicy: .immediate) }
    }

    func cancel(journey: Journey) {
        trip(for: journey).map(cancel)
    }

    /// Catches up on the Live Activities: one that started gets followed, and a trip that has arrived or whose Live
    /// Activity the system dropped goes. iOS launches the app in the background when a Live Activity starts, but suspends
    /// it within seconds whatever it does, so the trip then waits on the Lock Screen until `opened`, when the traveller
    /// brings the app up. A followed step's countdown would stand still and the app stopped notification would fire.
    func sync(opened: Bool = false) {
        let now = Date()
        let activities = Activity<TripActivityAttributes>.activities
        for trip in trips {
            if trip.journey.progress(at: now, delays: [:]).phase == .arrived {
                cancel(trip)
                continue
            }
            guard let id = trip.activityId else { continue }
            guard let activity = activities.first(where: { $0.id == id }),
                  activity.activityState != .ended, activity.activityState != .dismissed
            else {
                remove(trip)
                continue
            }
            if !Self.hasStarted(activity.activityState) {
                // Not from a background launch, whose process the start could resume only to be suspended again.
                if UIApplication.shared.applicationState != .background {
                    watch(activity)
                }
            } else if opened {
                remove(trip)
                GlobalController.tripLiveActivity.follow(trip.journey, startedAs: activity)
            }
        }
    }

    /// Opens the tapped reminder's trip, started unless the traveller only asked to view it. Call once the app is active.
    func runTappedReminder() {
        guard let tapped else { return }
        self.tapped = nil
        sync(opened: true)
        guard let trip = trips.first(where: { $0.id == tapped.id }) else {
            // Its Live Activity is followed by now; or the trip is over, which leaves the planner.
            GlobalController.appState.pendingNavigation = .activeTrip
            return
        }
        if tapped.starts {
            GlobalController.tripLiveActivity.start(trip.journey)
        }
        GlobalController.appState.pendingNavigation = .journey(trip.journey)
    }

    private func remove(_ trip: ScheduledTrip) {
        trips.removeAll { $0.id == trip.id }
        save()
        let identifier = Self.notificationIdentifier(trip.id)
        GlobalController.notificationQueue.async {
            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [identifier])
            center.removeDeliveredNotifications(withIdentifiers: [identifier])
        }
    }

    private func save() {
        UserDefaults.standard.save(customObject: trips, forKey: Stored.scheduledTrips)
    }

    /// Whether a trip scheduled now starts by itself: from iOS 26, while fewer than two scheduled Live Activities wait.
    /// Waiting ones count towards the system's limit of Live Activities (five on iOS 26), which a started trip and the
    /// tables need too. The other trips only get the reminder.
    var startsByItself: Bool {
        guard #available(iOS 26.0, *) else { return false }
        return Activity<TripActivityAttributes>.activities.filter { $0.activityState == .pending }.count < 2
    }

    /// The id of a Live Activity starting at `date`, or nil where it can't: see `startsByItself`; the request also fails
    /// at the system's limit. Those trips only have the reminder.
    /// The SDK claims `ActivityStyle` from iOS 16.1, but iOS 17 does not have it, so the app weak-links ActivityKit
    /// (`-weak_framework`): otherwise it can't even launch on the older versions, whatever the availability check.
    private func requestActivity(of journey: Journey, at date: Date, minutes: Int) -> String? {
        guard #available(iOS 26.0, *), startsByItself, date > Date(), let state = journey.scheduledState,
              let text = journey.reminderText(minutes: minutes)
        else { return nil }
        let sound: AlertConfiguration.AlertSound = UserDefaults.standard.bool(forKey: Stored.liveActivitiesSounds)
            ? .default : .named("")
        do {
            return try Activity.request(
                attributes: TripActivityAttributes(), content: ActivityContent(state: state, staleDate: nil),
                pushType: nil, style: .standard,
                alertConfiguration: AlertConfiguration(title: "\(text.title)", body: "\(text.body)", sound: sound),
                start: date
            ).id
        } catch {
            #if DEBUG
            print("Trip Live Activity was not scheduled: \(error)")
            #endif
            return nil
        }
    }

    private func addReminder(of trip: ScheduledTrip, minutes: Int?) {
        guard let minutes, let date = trip.remindsAt, let text = trip.journey.reminderText(minutes: minutes) else { return }
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body
        content.sound = .default
        content.categoryIdentifier = Self.category.identifier
        content.userInfo = [Self.idKey: trip.id]
        content.interruptionLevel = .timeSensitive
        // Never in the past, which the trigger refuses: the minute the schedule button showed may just have ended.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(date.timeIntervalSinceNow, 1), repeats: false)
        let request = UNNotificationRequest(
            identifier: Self.notificationIdentifier(trip.id), content: content, trigger: trigger
        )
        GlobalController.notificationQueue.async {
            UNUserNotificationCenter.current().add(request)
        }
    }

    private func watch(_ activity: Activity<TripActivityAttributes>) {
        guard watched.insert(activity.id).inserted else { return }
        Task {
            for await state in activity.activityStateUpdates where Self.hasStarted(state) {
                // The app was running before the start, so it keeps running when it is on screen or keeps table
                // Live Activities updated; a background launch for the start does neither.
                DispatchQueue.main.async {
                    GlobalController.tripSchedule.sync(
                        opened: UIApplication.shared.applicationState == .active || GlobalController.shouldRunInBackground
                    )
                }
                break
            }
        }
    }

    /// Anything past waiting for the start, also when it ended.
    private static func hasStarted(_ state: ActivityState) -> Bool {
        guard #available(iOS 26.0, *) else { return true }
        return state != .pending
    }

    private static func notificationIdentifier(_ id: String) -> String {
        "eu.magicsk.Transi.ScheduledTrip.\(id)"
    }
}

extension TripScheduleController: UNUserNotificationCenterDelegate {
    /// The app stopped running notification has no use while the app runs; a due reminder does.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler(
            notification.request.content.categoryIdentifier == Self.category.identifier ? [.banner, .list, .sound] : []
        )
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let id = response.notification.request.content.userInfo[Self.idKey] as? String
        let starts = response.actionIdentifier != Self.viewAction
        DispatchQueue.main.async {
            if let id {
                self.tapped = (id, starts)
                // Otherwise the app is still coming up, and its scene turning active runs it.
                if UIApplication.shared.applicationState == .active {
                    self.runTappedReminder()
                }
            }
            completionHandler()
        }
    }
}
