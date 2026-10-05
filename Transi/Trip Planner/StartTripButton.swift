//
//  StartTripButton.swift
//  Transi
//
//  Created by magic_sk on 04/10/2026.
//

import ActivityKit
import SwiftUI

/// Starts a Live Activity that guides through `journey` step by step, or ends it while it runs.
/// Enabled while a leg is live, as in the trip detail: from an hour before the journey leaves. Not on iPad and the
/// Mac, which do not run Live Activities. The trip detail drops it once the journey has arrived.
struct StartTripButton: View {
    let journey: Journey
    /// Updated every minute by the trip detail, so the start enables itself an hour before departure.
    let now: Date

    @StateObject private var tripLiveActivity = GlobalController.tripLiveActivity
    @Environment(\.scenePhase) private var scenePhase
    @State private var activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled

    var body: some View {
        // iPad and the Mac report Live Activities off, with no setting that turns them on.
        if UIDevice.current.userInterfaceIdiom == .phone, !ProcessInfo.processInfo.isiOSAppOnMac {
            content(
                isRunning: tripLiveActivity.journey == journey,
                canStart: journey.parts?.contains { $0.isLive(at: now) } ?? false
            )
            .onChange(of: scenePhase) { _ in
                activitiesEnabled = ActivityAuthorizationInfo().areActivitiesEnabled
            }
        }
    }

    private func content(isRunning: Bool, canStart: Bool) -> some View {
        VStack(spacing: 6.0) {
            let button = Button(role: isRunning ? .destructive : nil) {
                if isRunning {
                    tripLiveActivity.end()
                } else {
                    tripLiveActivity.start(journey)
                }
            } label: {
                Text(isRunning ? "End trip" : "Start trip")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(!isRunning && (!activitiesEnabled || !canStart))
            .accessibilityHint(
                isRunning
                    ? "Removes the trip from the Lock Screen and the Dynamic Island."
                    : "Shows each step on the Lock Screen and in the Dynamic Island."
            )

            if isRunning {
                // Not filled like the start, so a running trip looks different and ending it is the lesser action.
                if #available(iOS 26.0, *) {
                    button.buttonStyle(.glass)
                } else {
                    button.buttonStyle(.bordered)
                }
                footnote("Your trip is on the Lock Screen and in the Dynamic Island.")
            } else {
                if #available(iOS 26.0, *) {
                    button.buttonStyle(.glassProminent)
                } else {
                    button.buttonStyle(.borderedProminent)
                }
                if !activitiesEnabled {
                    footnote("Turn on Live Activities for Transi in Settings to follow this trip.")
                } else if !canStart {
                    footnote("You can start the trip up to 1 hour before departure.")
                }
            }
        }
    }

    private func footnote(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }
}
