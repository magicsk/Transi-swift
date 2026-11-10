//
//  StartTripButton.swift
//  Transi
//
//  Created by magic_sk on 04/10/2026.
//

import ActivityKit
import SwiftUI
import UserNotifications

/// The trip's one action. From half an hour before the journey leaves it starts a Live Activity that guides through
/// `journey` step by step, or ends it while it runs; earlier it schedules the trip or cancels the schedule.
/// Not on iPad and the Mac, which do not run Live Activities. The trip detail drops it once the journey has arrived.
struct StartTripButton: View {
    let journey: Journey
    /// Updated every minute by the trip detail, so scheduling turns into starting half an hour before departure.
    let now: Date

    private enum Action {
        case end, start, schedule, cancelSchedule
    }

    @StateObject private var tripLiveActivity = GlobalController.tripLiveActivity
    @StateObject private var tripSchedule = GlobalController.tripSchedule
    @Environment(\.scenePhase) private var scenePhase
    @State private var activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
    @State private var notificationsAllowed = true
    @AppStorage(Stored.tripReminderMinutes) private var reminderMinutes = 15
    @AppStorage(Stored.tripStartMinutes) private var startMinutes = 15

    var body: some View {
        // iPad and the Mac report Live Activities off, with no setting that turns them on.
        if UIDevice.current.userInterfaceIdiom == .phone, !ProcessInfo.processInfo.isiOSAppOnMac {
            content(scheduled: tripSchedule.trip(for: journey))
                .onAppear(perform: checkNotifications)
                .onChange(of: scenePhase) { _ in
                    activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
                    checkNotifications()
                }
        }
    }

    private func content(scheduled: ScheduledTrip?) -> some View {
        let action = action(scheduled: scheduled)
        return VStack(spacing: 6.0) {
            let button = Button(role: action == .end || action == .cancelSchedule ? .destructive : nil) {
                switch action {
                case .end: tripLiveActivity.end()
                case .start: tripLiveActivity.start(journey)
                case .schedule: tripSchedule.schedule(journey)
                case .cancelSchedule: tripSchedule.cancel(journey: journey)
                }
            } label: {
                title(of: action)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(isDisabled(action))
            .accessibilityHint(hint(of: action))

            if action == .end || action == .cancelSchedule {
                // Not filled like the start, so a running trip looks different and ending it is the lesser action.
                if #available(iOS 26.0, *) {
                    button.buttonStyle(.glass)
                } else {
                    button.buttonStyle(.bordered)
                }
            } else {
                if #available(iOS 26.0, *) {
                    button.buttonStyle(.glassProminent)
                } else {
                    button.buttonStyle(.borderedProminent)
                }
            }
            footnote(of: action, scheduled: scheduled)
        }
    }

    private func action(scheduled: ScheduledTrip?) -> Action {
        if tripLiveActivity.journey == journey { return .end }
        if journey.canStart(at: now) { return .start }
        return scheduled == nil ? .schedule : .cancelSchedule
    }

    /// Before iOS 26, and while two scheduled trips already wait to start, the reminder is the only way it starts.
    private var startsByItself: Bool {
        tripSchedule.startsByItself
    }

    private func isDisabled(_ action: Action) -> Bool {
        switch action {
        case .end, .cancelSchedule: return false
        case .start: return !activitiesEnabled
        case .schedule: return !activitiesEnabled || (!startsByItself && !notificationsAllowed)
        }
    }

    private func title(of action: Action) -> Text {
        switch action {
        case .end: return Text("End trip")
        case .start: return Text("Start trip")
        case .schedule: return Text("Schedule trip")
        case .cancelSchedule: return Text("Cancel scheduled trip")
        }
    }

    private func hint(of action: Action) -> Text {
        switch action {
        case .end: return Text("Removes the trip from the Lock Screen and the Dynamic Island.")
        case .start: return Text("Shows each step on the Lock Screen and in the Dynamic Island.")
        case .schedule: return Text("Sets the trip up to follow it shortly before departure.")
        case .cancelSchedule: return Text("Removes the trip and its reminder.")
        }
    }

    @ViewBuilder
    private func footnote(of action: Action, scheduled: ScheduledTrip?) -> some View {
        if action == .end {
            footnote("Your trip is on the Lock Screen and in the Dynamic Island.")
        } else if !activitiesEnabled {
            footnote("Turn on Live Activities for Transi in Settings to follow this trip.")
        } else if let scheduled {
            scheduledFootnote(scheduled)
        } else if action == .schedule {
            if !startsByItself && !notificationsAllowed {
                footnote("Turn on notifications for Transi in Settings to get a reminder for this trip.")
            } else if startsByItself {
                footnote("It starts \(startMinutes) min before departure.")
            } else {
                footnote(
                    "You get a reminder \(scheduledTripReminderMinutes(reminder: reminderMinutes, start: startMinutes, hasActivity: false) ?? startMinutes) min before departure."
                )
            }
        }
    }

    @ViewBuilder
    private func scheduledFootnote(_ scheduled: ScheduledTrip) -> some View {
        if scheduled.startsAt == nil, !notificationsAllowed {
            // Its reminder is the only way it starts.
            footnote("Turn on notifications for Transi in Settings to get a reminder for this trip.")
        } else if let startsAt = scheduled.startsAt, let remindsAt = scheduled.remindsAt {
            footnote("Starts at \(dayAndTime(startsAt)), with a reminder at \(dayAndTime(remindsAt)).")
        } else if let startsAt = scheduled.startsAt {
            footnote("Starts at \(dayAndTime(startsAt)).")
        } else if let remindsAt = scheduled.remindsAt {
            footnote("You get a reminder at \(dayAndTime(remindsAt)).")
        }
    }

    private func footnote(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    private func checkNotifications() {
        GlobalController.notificationQueue.async {
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                DispatchQueue.main.async {
                    notificationsAllowed = settings.authorizationStatus != .denied
                }
            }
        }
    }
}

/// "17:15", or "Tomorrow 17:15" when it isn't today.
func dayAndTime(_ date: Date) -> String {
    (dayStringUnlessToday(date).map { "\($0) " } ?? "") + timeStringFromDate(date)
}
