//
//  TripActivityLiveActivity.swift
//  VirtualTableActivityExtension
//
//  Created by magic_sk on 04/10/2026.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct TripActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TripActivityAttributes.self) { context in
            TripActivityLiveView(state: context.state)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    TripStepIcon(state: state, size: 20.0).padding(.leading, 10.0)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(state.time, style: .time).font(.headline).monospacedDigit().padding(.trailing, 10.0)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.title).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8.0) {
                        TripStepDetail(state: state).accessibilityElement(children: .combine)
                        if state.step == .question {
                            TripQuestionAnswers()
                        }
                    }
                    .padding(.horizontal, 10.0)
                }
            } compactLeading: {
                TripStepIcon(state: state, size: 16.0).padding(.leading, 7.5)
            } compactTrailing: {
                Text(state.compact).font(.headline).lineLimit(1).padding(.trailing, 7.5)
                    .accessibilityLabel(state.accessibilitySummary)
            } minimal: {
                Text(state.minimal).font(.system(size: 15.0, weight: .semibold)).lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityLabel(state.accessibilitySummary)
            }
            .widgetURL(URL(string: "transi://trip/active"))
        }
    }
}

/// The Lock Screen banner: the step with its time, then the detail, where the vehicle to board is, delay, ride progress
/// and change warning; the answers while it asks.
struct TripActivityLiveView: View {
    @Environment(\.colorScheme) private var colorScheme

    let state: TripActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            VStack(alignment: .leading, spacing: 8.0) {
                HStack(spacing: 8.0) {
                    TripStepIcon(state: state, size: 20.0)
                    Text(state.title).font(.headline).lineLimit(1)
                    Spacer(minLength: 4.0)
                    Text(state.time, style: .time).font(.headline).monospacedDigit()
                }
                TripStepDetail(state: state)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(state.accessibilitySummary)
            if state.step == .question {
                TripQuestionAnswers()
            }
        }
        .padding(15.0)
        .activityBackgroundTint(backgroundTint)
        .widgetURL(URL(string: "transi://trip/active"))
    }

    private var backgroundTint: Color {
        if #available(iOS 26.0, *) {
            return Color.clear
        }
        return colorScheme == .dark ? Color.black.opacity(0.43) : Color.systemBackground.opacity(0.43)
    }
}

/// The line badge to board, ride or change to; a walker or a check mark without one.
struct TripStepIcon: View {
    let state: TripActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        if let line = state.line {
            LineText(line, size)
        } else if state.step == .arrived {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Color.systemGreen)
        } else if state.step == .missed {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Color.systemOrange)
        } else if state.step == .question {
            Image(systemName: "questionmark.circle.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(Color.systemOrange)
        } else {
            Image(systemName: "figure.walk").font(.system(size: size, weight: .semibold))
        }
    }
}

struct TripStepDetail: View {
    let state: TripActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 6.0) {
            HStack(spacing: 5.0) {
                Text(state.detail).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 4.0)
                if let delay = state.delay {
                    Image(systemName: "circle.fill")
                        .foregroundColor(getDelayColor(delay, "online"))
                        .font(.system(size: 10.0))
                        .accessibilityHidden(true)
                    Text(getDelayText(delay, "online")).font(.subheadline).lineLimit(1).fixedSize()
                }
            }
            if let lastStop = state.lastStop {
                // As the table's Live Activity shows the vehicle's last stop.
                HStack(spacing: 5.0) {
                    StopIcon(color: .accent).scaleEffect(1.3).accessibilityHidden(true)
                    Text(lastStop).font(.subheadline).lineLimit(1)
                }
            }
            if let progress = state.progress {
                ProgressView(value: progress).tint(state.line.flatMap(colorFromLineNum))
            }
            if let warning = state.warningText {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(state.warning == .likelyMissedChange ? Color.systemRed : Color.systemOrange)
            }
            if let alternative = state.alternative {
                Text(alternative).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

/// The answers to the trip's question: buttons from iOS 17, where a Live Activity runs App Intents; earlier a tap opens
/// the trip, which asks.
struct TripQuestionAnswers: View {
    var body: some View {
        if #available(iOS 17.0, *) {
            HStack(spacing: 8.0) {
                Button(intent: TripQuestionIntent(stillOn: true)) {
                    Text("I'm on it").frame(maxWidth: .infinity)
                }
                Button(intent: TripQuestionIntent(stillOn: false)) {
                    Text("Other connections").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        } else {
            Text("Tap to answer").font(.footnote).foregroundStyle(.secondary)
        }
    }
}

extension TripActivityAttributes.ContentState {
    /// Everything the Lock Screen shows, in reading order.
    var accessibilitySummary: String {
        [
            line.map { "Line \($0)" }, title, detail, lastStop.map { "Vehicle at or past \($0)" },
            time.formatted(date: .omitted, time: .shortened), delay.map { getDelayText($0, "online") }, warningText,
            alternative,
        ].compactMap { $0 }.joined(separator: ", ")
    }
}
