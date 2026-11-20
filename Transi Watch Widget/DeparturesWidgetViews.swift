//
//  DeparturesWidgetViews.swift
//  Transi Watch Widget
//
//  Created by magic_sk on 19/11/2026.
//

import SwiftUI
import WidgetKit

struct DeparturesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DeparturesEntry

    var body: some View {
        content
            // transi://table/-1 makes the app follow the nearest stop.
            .widgetURL(URL(string: "transi://table/\(entry.stopId)"))
            .containerBackground(Color.accentColor.opacity(0.3).gradient, for: .widget)
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryCircular: CircularDeparturesView(entry: entry)
        case .accessoryCorner: CornerDeparturesView(entry: entry)
        case .accessoryInline: InlineDeparturesView(entry: entry)
        default: RectangularDeparturesView(entry: entry)
        }
    }
}

// MARK: - Families

private struct RectangularDeparturesView: View {
    @ScaledMetric(relativeTo: .footnote) private var badgeSize: CGFloat = 12
    let entry: DeparturesEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            header
            if case let .departures(departures) = entry.state, !departures.isEmpty {
                ForEach(departures, id: \.self) { departure in
                    DepartureRow(departure: departure, badgeSize: badgeSize)
                }
            } else {
                entry.state.message
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 3) {
            if entry.state == .noStop {
                Text("Transi")
            } else {
                if entry.isNearest {
                    Image(systemName: "location.fill")
                        .imageScale(.small)
                        .accessibilityLabel("Nearest stop")
                }
                Text(entry.stopName)
            }
        }
        .font(.footnote.weight(.semibold))
        .lineLimit(1)
        .widgetAccentable()
    }
}

private struct DepartureRow: View {
    let departure: WidgetDeparture
    let badgeSize: CGFloat

    var body: some View {
        HStack(spacing: 4) {
            LineBadge(line: departure.line, size: badgeSize)
            Text(departure.headsign)
                .lineLimit(1)
            Spacer(minLength: 2)
            if !departure.platform.isEmpty {
                Text(departure.platform)
                    .foregroundStyle(.secondary)
            }
            Text(departure.remaining)
                .monospacedDigit()
                .minimumScaleFactor(0.8)
                .layoutPriority(1)
        }
        // Only the time may shrink; a long headsign truncates at the same size as its neighbours.
        .font(.footnote)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(departure.spokenText)
    }
}

private struct CircularDeparturesView: View {
    let entry: DeparturesEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            if let departure = entry.nextDeparture {
                VStack(spacing: 1) {
                    LineBadge(line: departure.line, size: 12)
                    Text(departure.shortRemaining)
                        .font(.headline)
                        .monospacedDigit()
                        .minimumScaleFactor(0.6)
                }
                .padding(4)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(departure.spokenText)
            } else {
                StatusSymbol(state: entry.state)
            }
        }
    }
}

private struct CornerDeparturesView: View {
    let entry: DeparturesEntry

    var body: some View {
        if let departure = entry.nextDeparture {
            Text(departure.shortRemaining)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .widgetAccentable()
                .widgetLabel {
                    Text("\(departure.line) · \(departure.headsign)")
                }
                .accessibilityLabel(departure.spokenText)
        } else {
            StatusSymbol(state: entry.state)
                .widgetLabel { entry.state.message }
        }
    }
}

private struct InlineDeparturesView: View {
    let entry: DeparturesEntry

    var body: some View {
        if let departure = entry.nextDeparture {
            Text("\(departure.line) · \(departure.remaining) · \(departure.headsign)")
                .accessibilityLabel(departure.spokenText)
        } else {
            entry.state.message
        }
    }
}

// MARK: - Pieces

/// The line badge in full colour; on accented and vibrant faces, an outlined number the face can tint.
private struct LineBadge: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let line: String
    let size: CGFloat

    var body: some View {
        if renderingMode == .fullColor {
            LineText(line, size)
        } else {
            Text(line)
                .font(.system(size: size, weight: .bold))
                .lineLimit(1)
                .padding(.horizontal, size * 0.21)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(lineWidth: 1))
                .widgetAccentable()
        }
    }
}

/// What the compact families show without a departure.
private struct StatusSymbol: View {
    let state: DeparturesEntry.State

    var body: some View {
        Image(systemName: symbol)
            .font(.title3)
            .widgetAccentable()
            .accessibilityLabel(state.message)
    }

    private var symbol: String {
        switch state {
        case .noStop: "location.slash"
        case .failed: "exclamationmark.triangle"
        case .departures: "moon.zzz"
        }
    }
}

extension DeparturesEntry {
    var nextDeparture: WidgetDeparture? {
        if case let .departures(departures) = state { return departures.first }
        return nil
    }
}

extension DeparturesEntry.State {
    /// Why there is no departure to show.
    var message: Text {
        switch self {
        case .noStop: Text("Open Transi to find stops near you")
        case .failed: Text("Couldn't load departures")
        case .departures: Text("No departures soon")
        }
    }
}

extension WidgetDeparture {
    /// "Line 72 to Stn. Vrakuňa, 3 min, platform A".
    var spokenText: Text {
        // "~" reads as "tilde"; ", scheduled" says it instead.
        var text = Text("Line \(line) to \(headsign), \(remaining.replacingOccurrences(of: "~", with: ""))")
        if !platform.isEmpty { text = text + Text(", platform \(platform)") }
        if !isLive { text = text + Text(", scheduled") }
        return text
    }
}

#Preview(as: .accessoryRectangular) {
    DeparturesWidget()
} timeline: {
    DeparturesEntry.example
    DeparturesEntry(date: .now, stopName: "Hronská", state: .failed)
    DeparturesEntry(date: .now, state: .noStop)
}
