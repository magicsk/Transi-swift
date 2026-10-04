//
//  TripDetailSheet.swift
//  Transi
//
//  Created by magic_sk on 04/10/2026.
//

import SwiftUI

/// The summary and steps (medium detent) and every stop (large detent) of the journey on the map.
struct TripDetailSheet: View {
    @ObservedObject var model: TripDetailModel
    @State private var expanded = Set<Int>()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var badgeSize = 17.0

    var body: some View {
        let journey = model.journey
        let parts = journey.parts ?? []
        let steps = journey.steps
        let buffers = model.transferBuffers
        List {
            Section {
                Button {
                    model.focus(.route)
                } label: {
                    TripSummaryView(model: model)
                }
                .foregroundColor(.primary)
                .accessibilityHint("Shows the whole route on the map")
            }
            Section("Steps") {
                ForEach(steps, id: \.self) { step in
                    stepRow(step, parts: parts, buffers: buffers)
                }
            }
            Section("Stops") {
                ForEach(steps, id: \.self) { step in
                    timelineRows(step, parts: parts, buffers: buffers, isLast: step == steps.last)
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.defaultMinListRowHeight, 0)
        .modifier(SheetListBackground())
    }

    // MARK: Steps

    @ViewBuilder
    private func stepRow(_ step: JourneyStep, parts: [Part], buffers: [Int: TransferBuffer]) -> some View {
        switch step {
        case .ride(let index):
            let part = parts[index]
            Button {
                model.focus(.part(index))
            } label: {
                stepLayout {
                    LineText(part.routeShortName ?? "?", badgeSize)
                        .frame(minWidth: iconWidth)
                    VStack(alignment: .leading, spacing: 3) {
                        besideOrStacked(HStackLayout(alignment: .firstTextBaseline)) {
                            Text(part.tripHeadsign ?? "").font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                            if !dynamicTypeSize.isAccessibilitySize {
                                Spacer(minLength: 4)
                            }
                            DelayText(seconds: model.delaySeconds(index))
                        }
                        (stopText(part.startStopName, part.startStopCode) + Text(verbatim: " → ")
                            + stopText(part.endStopName, part.endStopCode))
                            .font(.subheadline)
                        (Text("\(timeStringFromDate(part.startDeparture)) – \(timeStringFromDate(part.endArrival))")
                            + stopCountText(part))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .foregroundColor(.primary)
            .accessibilityLabel(rideLabel(part, delaySeconds: model.delaySeconds(index)))
            .accessibilityHint("Shows this leg on the map")
        case .walk(let walks, let to):
            if let first = walks.first, let last = walks.last {
                Button {
                    model.focus(to.map { .change(to: $0) } ?? .part(first))
                } label: {
                    changeRow(
                        icon: "figure.walk",
                        title: walkText(
                            walks.reduce(0) { $0 + parts[$1].minutes }, from: parts[first], to: parts[last],
                            ride: to.map { parts[$0] }
                        ),
                        buffer: to.flatMap { buffers[$0] }
                    )
                }
                .foregroundColor(.primary)
                .accessibilityHint("Shows this walk on the map")
            }
        case .change(let to):
            Button {
                model.focus(.change(to: to))
            } label: {
                changeRow(icon: "arrow.triangle.swap", title: changeText(parts[to]), buffer: buffers[to])
            }
            .foregroundColor(.primary)
            .accessibilityHint("Shows this change on the map")
        }
    }

    /// Side by side, or stacked at accessibility text sizes so the text keeps the full width.
    private var stepLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
    }

    private var iconWidth: CGFloat? {
        dynamicTypeSize.isAccessibilitySize ? nil : badgeSize * 2.6
    }

    private func changeRow(icon: String, title: Text, buffer: TransferBuffer?) -> some View {
        stepLayout {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(minWidth: iconWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                title
                if let buffer {
                    BufferText(buffer: buffer)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .padding(.vertical, 4)
    }

    // MARK: Stops

    @ViewBuilder
    private func timelineRows(
        _ step: JourneyStep, parts: [Part], buffers: [Int: TransferBuffer], isLast: Bool
    ) -> some View {
        switch step {
        case .ride(let index):
            let part = parts[index]
            let line = part.routeShortName ?? "?"
            let color = colorFromLineNum(line) ?? .gray
            let stops = Self.legStops(part)
            let board = stops[0]
            let alight = stops[stops.count - 1]
            let middle = Array(stops.dropFirst().dropLast())
            let zoneChanges = stops.zoneChanges
            let isExpanded = expanded.contains(index)

            tappable(board.gps) {
                TimelineRow(time: board.time, bottom: color, node: .stop(color)) {
                    VStack(alignment: .leading, spacing: 4) {
                        stopText(board.name, board.platform).font(.body.weight(.semibold))
                        besideOrStacked(HStackLayout(spacing: 6)) {
                            LineText(line, badgeSize * 0.8)
                            Text("to \(part.tripHeadsign ?? "")").font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                            DelayText(seconds: model.delaySeconds(index))
                        }
                    }
                }
            }
            .accessibilityLabel(
                Text("Board line \(line) to \(part.tripHeadsign ?? "") at \(timeStringFromDate(board.time)) from \(board.name)")
                    + platformSpoken(board.platform) + delaySpoken(model.delaySeconds(index))
            )

            switch model.stopsState[index] {
            case .loading:
                TimelineRow(time: nil, top: color, bottom: color) {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading stops").foregroundColor(.secondary)
                    }
                    .font(.subheadline)
                }
                .timelineRow()
            case .failed:
                TimelineRow(time: nil, top: color, bottom: color) {
                    HStack {
                        Text("Couldn't load the stops").foregroundColor(.secondary)
                        Spacer(minLength: 8)
                        Button("Retry") { model.loadStops(index) }
                            .buttonStyle(.borderless)
                    }
                    .font(.subheadline)
                }
                .timelineRow()
            case nil:
                if !middle.isEmpty {
                    Button {
                        withAnimation(reduceMotion ? nil : .default) {
                            expanded.formSymmetricDifference([index])
                        }
                    } label: {
                        TimelineRow(time: nil, top: color, bottom: color) {
                            HStack(spacing: 6) {
                                Text("^[\(middle.count) stop](inflect: true) · \(part.minutes) min")
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.footnote.weight(.semibold))
                                    .accessibilityHidden(true)
                            }
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        }
                    }
                    .timelineRow()
                    .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))
                    .accessibilityHint(isExpanded ? Text("Hides the stops in between") : Text("Shows the stops in between"))
                }
            }

            if isExpanded {
                ForEach(Array(middle.enumerated()), id: \.offset) { offset, stop in
                    if let change = zoneChanges.first(where: { $0.index == offset + 1 }) {
                        zoneRow(change, color: color)
                    }
                    tappable(stop.gps) {
                        TimelineRow(time: stop.time, top: color, bottom: color, node: .middle(color)) {
                            stopText(stop.name, stop.platform).font(.subheadline)
                        }
                    }
                    .accessibilityLabel(
                        Text("\(timeStringFromDate(stop.time)), \(stop.name)") + platformSpoken(stop.platform)
                    )
                }
                if let change = zoneChanges.first(where: { $0.index == stops.count - 1 }) {
                    zoneRow(change, color: color)
                }
            }

            tappable(alight.gps) {
                TimelineRow(time: alight.time, top: color, node: .stop(color)) {
                    VStack(alignment: .leading, spacing: 4) {
                        stopText(alight.name, alight.platform).font(.body.weight(.semibold))
                        (isLast ? Text("Arrive") : Text("Get off")).font(.subheadline).foregroundColor(.secondary)
                    }
                }
            }
            .accessibilityLabel(
                (isLast ? Text("Arrive at \(timeStringFromDate(alight.time)) at \(alight.name)")
                    : Text("Get off at \(timeStringFromDate(alight.time)) at \(alight.name)"))
                    + platformSpoken(alight.platform)
            )
        case .walk(let walks, let to):
            if let first = walks.first, let last = walks.last {
                TimelineRow(time: nil, node: .walk) {
                    VStack(alignment: .leading, spacing: 3) {
                        walkText(
                            walks.reduce(0) { $0 + parts[$1].minutes }, from: parts[first], to: parts[last],
                            ride: to.map { parts[$0] }
                        )
                        if let buffer = to.flatMap({ buffers[$0] }) {
                            BufferText(buffer: buffer)
                        }
                    }
                    .font(.subheadline)
                    .accessibilityElement(children: .combine)
                }
                .timelineRow()
                if to == nil {
                    let end = parts[last]
                    tappable(end.endStopGps) {
                        TimelineRow(time: end.endArrival, top: nil, node: .stop(.systemGray)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(end.endStopName ?? "").font(.body.weight(.semibold))
                                Text("Arrive").font(.subheadline).foregroundColor(.secondary)
                            }
                        }
                    }
                    .accessibilityLabel(
                        Text("Arrive at \(timeStringFromDate(end.endArrival)) at \(end.endStopName ?? "")")
                    )
                }
            }
        case .change(let to):
            TimelineRow(time: nil, node: .walk) {
                VStack(alignment: .leading, spacing: 3) {
                    changeText(parts[to])
                    if let buffer = buffers[to] {
                        BufferText(buffer: buffer)
                    }
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
            }
            .timelineRow()
        }
    }

    /// A ride's headsign and delay side by side, or stacked at accessibility text sizes so the headsign wraps
    /// by words and the delay is not truncated. Give the headsign a fixed vertical size, or the stack truncates it.
    private func besideOrStacked<Content: View>(
        _ beside: HStackLayout, @ViewBuilder content: () -> Content
    ) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(beside)
        return layout(content)
    }

    private func zoneRow(_ change: ZoneChange, color: Color) -> some View {
        TimelineRow(time: nil, top: color, bottom: color) {
            Text("Zone \(change.from) → \(change.to)")
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.tertiarySystemFill))
                .accessibilityLabel(Text("Zone border, \(change.from) to \(change.to)"))
        }
        .timelineRow()
    }

    /// A row that centres the map on the stop, when its position is known. Either way it is one
    /// accessibility element, so the caller's label is read once.
    @ViewBuilder
    private func tappable<Row: View>(_ gps: StopGps?, @ViewBuilder row: () -> Row) -> some View {
        if let gps {
            Button {
                model.focus(.stop(gps))
            } label: {
                row()
            }
            .foregroundColor(.primary)
            .timelineRow()
            .accessibilityHint("Shows this stop on the map")
        } else {
            row()
                .accessibilityElement(children: .combine)
                .timelineRow()
        }
    }

    /// The leg's stops, or its boarding and alighting stops while the rest are unknown.
    private static func legStops(_ part: Part) -> [PartStop] {
        if let stops = part.stops, stops.count > 1 {
            return stops
        }
        return [
            PartStop(name: part.startStopName ?? "", platform: part.startStopCode, time: part.startDeparture,
                     gps: part.startStopGps),
            PartStop(name: part.endStopName ?? "", platform: part.endStopCode, time: part.endArrival,
                     gps: part.endStopGps),
        ]
    }

    // MARK: Text

    private func stopCountText(_ part: Part) -> Text {
        guard let count = part.stops.map({ $0.count - 2 }), count > 0 else { return Text(verbatim: "") }
        return Text(" · ^[\(count) stop](inflect: true)")
    }

    private func walkText(_ minutes: Int, from first: Part, to last: Part, ride: Part?) -> Text {
        let name = ride?.startStopName ?? last.endStopName ?? ""
        let platform = ride?.startStopCode ?? last.endStopCode
        if first.startStopName == name, let platform {
            return Text("Walk \(minutes) min to platform \(platform)")
        }
        return Text("Walk \(minutes) min to \(name)") + Text(verbatim: " ") + platformText(platform)
    }

    private func changeText(_ ride: Part) -> Text {
        Text("Change at \(ride.startStopName ?? "")") + Text(verbatim: " ") + platformText(ride.startStopCode)
    }

    private func rideLabel(_ part: Part, delaySeconds: Int?) -> Text {
        var label = Text("Line \(part.routeShortName ?? "") to \(part.tripHeadsign ?? ""), departs \(timeStringFromDate(part.startDeparture)) from \(part.startStopName ?? "")")
            + platformSpoken(part.startStopCode)
            + Text(", arrives \(timeStringFromDate(part.endArrival)) at \(part.endStopName ?? "")")
            + platformSpoken(part.endStopCode)
        if let count = part.stops.map({ $0.count - 2 }), count > 0 {
            label = label + Text(", ^[\(count) stop](inflect: true)")
        }
        return label + delaySpoken(delaySeconds)
    }
}

// MARK: - Summary

private struct TripSummaryView: View {
    // Journey equality ignores stops, so observe the model to redraw once the zone names load.
    @ObservedObject var model: TripDetailModel

    private var journey: Journey { model.journey }

    var body: some View {
        let parts = journey.parts ?? []
        if let first = parts.first, let last = parts.last {
            let minutes = minutesBetween(first.startDeparture, last.endArrival)
            let times = "\(timeStringFromDate(first.startDeparture)) → \(timeStringFromDate(last.endArrival))"
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(minutes) min").font(.title2.bold())
                        Spacer()
                        Text(times).font(.headline).foregroundColor(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(minutes) min").font(.title2.bold())
                        Text(times).font(.headline).foregroundColor(.secondary)
                    }
                }
                LegBar(parts: parts)
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { chips }
                    VStack(alignment: .leading, spacing: 6) { chips }
                }
            }
            .padding(.vertical, 4)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Text("\(minutes) min, \(timeStringFromDate(first.startDeparture)) to \(timeStringFromDate(last.endArrival)), ")
                    + changesText + Text(", ") + walkText + Text(", ") + zonesText
            )
        }
    }

    @ViewBuilder
    private var chips: some View {
        chip(changesText)
        if journey.walkMinutes > 0 {
            chip(walkText)
        }
        if !journey.zoneNames.isEmpty || journey.zones?.isEmpty == false {
            chip(zonesText)
        }
    }

    private func chip(_ text: Text) -> some View {
        text
            .font(.footnote.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.tertiarySystemFill))
    }

    private var changesText: Text {
        let changes = max(journey.rideCount - 1, 0)
        return changes == 0 ? Text("No changes") : Text("^[\(changes) change](inflect: true)")
    }

    private var walkText: Text {
        journey.walkMinutes > 0 ? Text("\(journey.walkMinutes) min walk") : Text("No walking")
    }

    /// Zone names once the stops are known; R-API journeys only list numeric zone ids, so count them.
    private var zonesText: Text {
        let names = journey.zoneNames
        if names.count == 1 {
            return Text("Zone \(names[0])")
        }
        if !names.isEmpty {
            return Text("Zones \(names.joined(separator: " · "))")
        }
        return Text("^[\(journey.zones?.count ?? 0) zone](inflect: true)")
    }
}

/// Each leg's share of the journey, in its line colour; walks in grey.
private struct LegBar: View {
    let parts: [Part]
    @ScaledMetric(relativeTo: .caption2) private var height = 16.0

    var body: some View {
        // Every leg gets at least a minute so short walks stay visible.
        let durations = parts.map { max($0.endArrival.timeIntervalSince($0.startDeparture), 60) }
        let total = durations.reduce(0, +)
        GeometryReader { geometry in
            let width = max(geometry.size.width - CGFloat(parts.count - 1) * 2, 0)
            HStack(spacing: 2) {
                ForEach(parts.indices, id: \.self) { index in
                    let part = parts[index]
                    let line = part.routeShortName ?? ""
                    let segment = width * durations[index] / total
                    Capsule()
                        // The secondary label colour keeps 3:1 contrast with the sheet in light and dark.
                        .fill(part.routeType == 64 ? Color.secondaryLabel : colorFromLineNum(line) ?? .gray)
                        .overlay(
                            Text(line)
                                .font(.caption2.bold())
                                .foregroundColor(textColorFromLineNum(line))
                                .lineLimit(1)
                                .opacity(part.routeType != 64 && segment >= height * 2 ? 1 : 0)
                        )
                        .frame(width: segment)
                }
            }
        }
        .frame(height: height)
        .accessibilityHidden(true)
    }
}

// MARK: - Shared rows

private struct TimelineRow<Content: View>: View {
    enum Node {
        case none, stop(Color), middle(Color), walk
    }

    let time: Date?
    var top: Color?
    var bottom: Color?
    var node = Node.none
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var timeWidth = 46.0

    var body: some View {
        // At accessibility text sizes the time moves above the content, which keeps the full width.
        let isStacked = dynamicTypeSize.isAccessibilitySize
        let timeText = Text(time.map(timeStringFromDate) ?? "")
            .font(.subheadline.monospacedDigit())
            .foregroundColor(.secondary)
        HStack(spacing: 10) {
            if !isStacked {
                timeText
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: timeWidth, alignment: .trailing)
            }
            ZStack {
                if case .walk = node {
                    VerticalLine()
                        .stroke(Color.systemGray, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [0.5, 8]))
                } else {
                    VStack(spacing: 0) {
                        (top ?? .clear).frame(width: 4)
                        (bottom ?? .clear).frame(width: 4)
                    }
                }
                switch node {
                case .stop(let color):
                    Circle().strokeBorder(color, lineWidth: 4)
                        .background(Circle().fill(Color.secondarySystemGroupedBackground))
                        .frame(width: 16, height: 16)
                case .middle(let color):
                    Circle().strokeBorder(color, lineWidth: 2.5)
                        .background(Circle().fill(Color.secondarySystemGroupedBackground))
                        .frame(width: 10, height: 10)
                case .none, .walk:
                    EmptyView()
                }
            }
            .frame(width: 18)
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if isStacked, time != nil {
                    timeText
                }
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
        }
        .padding(.leading, isStacked ? 12 : 0)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct VerticalLine: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        }
    }
}

private extension View {
    /// Timeline rows touch each other so the rail looks continuous.
    func timelineRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
    }
}

private struct DelayText: View {
    let seconds: Int?

    var body: some View {
        if let seconds {
            let minutes = delayMinutes(seconds)
            Group {
                if minutes > 0 {
                    Text("+\(minutes) min")
                } else if minutes < 0 {
                    Text("\(-minutes) min early")
                } else {
                    Text("on time")
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(getDelayColor(minutes, "online"))
            .lineLimit(1)
        }
    }
}

private struct BufferText: View {
    let buffer: TransferBuffer

    var body: some View {
        if buffer.isLikelyMissed || buffer.isTight {
            // Not a Label: inside a list row it would take the row's icon column.
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(buffer.isLikelyMissed ? .red : .orange)
                    .accessibilityHidden(true)
                buffer.isLikelyMissed
                    ? Text("Likely missed by \(-buffer.minutes) min")
                    : Text("Tight change: \(buffer.minutes) min to spare")
            }
            .font(.subheadline.weight(.semibold))
        } else {
            Text("\(buffer.minutes) min to spare")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

private struct SheetListBackground: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            // Let the sheet's Liquid Glass show through.
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}

private func platformText(_ platform: String?) -> Text {
    guard let platform else { return Text(verbatim: "") }
    return Text("\(Image("stop"))\(platform)").foregroundColor(.secondary)
}

private func stopText(_ name: String?, _ platform: String?) -> Text {
    Text(name ?? "") + Text(verbatim: " ") + platformText(platform)
}

private func platformSpoken(_ platform: String?) -> Text {
    platform.map { Text(", platform \($0)") } ?? Text(verbatim: "")
}

private func delaySpoken(_ seconds: Int?) -> Text {
    guard let seconds else { return Text(verbatim: "") }
    let minutes = delayMinutes(seconds)
    if minutes > 0 {
        return Text(", ^[\(minutes) minute](inflect: true) late")
    }
    if minutes < 0 {
        return Text(", ^[\(-minutes) minute](inflect: true) early")
    }
    return Text(", on time")
}
