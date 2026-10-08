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
                    TripStepDetail(state: state).padding(.horizontal, 10.0)
                        .accessibilityElement(children: .combine)
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

/// The Lock Screen banner: the step with its time, then the detail, delay, ride progress and change warning.
struct TripActivityLiveView: View {
    @Environment(\.colorScheme) private var colorScheme

    let state: TripActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8.0) {
            HStack(spacing: 8.0) {
                TripStepIcon(state: state, size: 20.0)
                Text(state.title).font(.headline).lineLimit(1)
                Spacer(minLength: 4.0)
                Text(state.time, style: .time).font(.headline).monospacedDigit()
            }
            TripStepDetail(state: state)
        }
        .padding(15.0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(state.accessibilitySummary)
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
            if let progress = state.progress {
                ProgressView(value: progress).tint(state.line.flatMap(colorFromLineNum))
            }
            if let warning = state.warningText {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(state.warning == .likelyMissedChange ? Color.systemRed : Color.systemOrange)
            }
        }
    }
}

extension TripActivityAttributes.ContentState {
    /// Everything the Lock Screen shows, in reading order.
    var accessibilitySummary: String {
        [
            line.map { "Line \($0)" }, title, detail, time.formatted(date: .omitted, time: .shortened),
            delay.map { getDelayText($0, "online") }, warningText,
        ].compactMap { $0 }.joined(separator: ", ")
    }
}
