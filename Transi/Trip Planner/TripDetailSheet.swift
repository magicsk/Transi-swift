//
//  TripDetailSheet.swift
//  Transi
//
//  Created by magic_sk on 04/10/2026.
//

import SwiftUI

/// The summary (summary detent), steps (medium detent) and every stop (large detent) of the journey on the map.
struct TripDetailSheet: View {
    @ObservedObject var model: TripDetailModel
    @StateObject private var tripLiveActivity = GlobalController.tripLiveActivity
    @State private var expanded = Set<Int>()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var badgeSize = 17.0

    private static let summary = "summary"

    var body: some View {
        let journey = model.journey
        let parts = journey.parts ?? []
        let steps = journey.steps
        let buffers = model.transferBuffers
        // While the trip Live Activity follows this journey.
        let isFollowed = tripLiveActivity.journey == journey
        let currentStep = isFollowed ? tripLiveActivity.progress?.step(in: journey) : nil
        ScrollViewReader { proxy in
            List {
                Section {
                    Button {
                        model.focus(.route)
                    } label: {
                        TripSummaryView(
                            model: model, liveStep: isFollowed ? tripLiveActivity.state : nil, delays: delays
                        )
                            .background(GeometryReader { geometry in
                                // List rows don't see coordinate spaces named outside the list.
                                let frame = geometry.frame(in: .global)
                                Color.clear
                                    .onAppear { model.onSummaryFrame?(frame) }
                                    .onChange(of: frame) { model.onSummaryFrame?($0) }
                            })
                    }
                    .foregroundColor(.primary)
                    .accessibilityHint("Shows the whole route on the map")
                    .listRowBackground(cardBackground)
                    .id(Self.summary)
                    if isFollowed, let missed = tripLiveActivity.missed {
                        MissedRideView(missed: missed, journey: journey, badgeSize: badgeSize)
                            .listRowBackground(cardBackground)
                    }
                    if journey.rideCount > 0 {
                        // Journey actions, one full-width button per line. Checked every minute, so the start
                        // enables itself an hour before departure and the actions go once the journey arrives.
                        TimelineView(.everyMinute) { context in
                            let hasArrived = journey.progress(at: context.date, delays: delays).phase == .arrived
                            VStack(spacing: 12) {
                                if isFollowed || !hasArrived {
                                    StartTripButton(journey: journey, now: context.date)
                                }
                                if hasArrived {
                                    Text("This journey has already arrived.")
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                        .multilineTextAlignment(.center)
                                        .frame(maxWidth: .infinity)
                                } else {
                                    TripTicketButton(model: model)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .listRowBackground(cardBackground)
                    }
                }
                Section("Steps") {
                    ForEach(steps, id: \.self) { step in
                        stepRow(step, parts: parts, buffers: buffers)
                            .modifier(CurrentStep(isCurrent: step == currentStep))
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
            .onReceive(model.showSummary) {
                withAnimation(reduceMotion ? nil : .default) {
                    proxy.scrollTo(Self.summary, anchor: .top)
                }
            }
        }
    }

    /// Seconds late by part index while each leg is live: what the times shift by and the arrival counts from.
    private var delays: [Int: Int] {
        Dictionary(uniqueKeysWithValues: (model.journey.parts ?? []).indices.compactMap { index in
            model.delaySeconds(index).map { (index, $0) }
        })
    }

    // MARK: Steps

    @ViewBuilder
    private func stepRow(_ step: JourneyStep, parts: [Part], buffers: [Int: TransferBuffer]) -> some View {
        switch step {
        case .ride(let index):
            let part = parts[index]
            let delay = model.delaySeconds(index)
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
                            DelayText(seconds: delay)
                        }
                        (stopText(part.startStopName, part.startStopCode) + Text(verbatim: " → ")
                            + stopText(part.endStopName, part.endStopCode))
                            .font(.subheadline)
                        (Text("\(timeText(part.startDeparture, delaySeconds: delay)) – \(timeText(part.endArrival, delaySeconds: delay))")
                            + stopCountText(part))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            .foregroundColor(.primary)
            .accessibilityLabel(rideLabel(part, delaySeconds: delay))
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
            let delay = model.delaySeconds(index)

            tappable(board.gps) {
                TimelineRow(time: board.time, delaySeconds: delay, bottom: color, node: .stop(color)) {
                    VStack(alignment: .leading, spacing: 4) {
                        stopText(board.name, board.platform).font(.body.weight(.semibold))
                        besideOrStacked(HStackLayout(spacing: 6)) {
                            LineText(line, badgeSize * 0.8)
                            Text("to \(part.tripHeadsign ?? "")").font(.subheadline)
                                .fixedSize(horizontal: false, vertical: true)
                            DelayText(seconds: delay)
                        }
                    }
                }
            }
            .accessibilityLabel(
                Text("Board line \(line) to \(part.tripHeadsign ?? "") at \(spokenTime(board.time, delaySeconds: delay)) from \(board.name)")
                    + platformSpoken(board.platform) + delaySpoken(delay)
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
                        TimelineRow(
                            time: stop.time, delaySeconds: delay, top: color, bottom: color, node: .middle(color)
                        ) {
                            stopText(stop.name, stop.platform).font(.subheadline)
                        }
                    }
                    .accessibilityLabel(
                        Text("\(spokenTime(stop.time, delaySeconds: delay)), \(stop.name)") + platformSpoken(stop.platform)
                    )
                }
                if let change = zoneChanges.first(where: { $0.index == stops.count - 1 }) {
                    zoneRow(change, color: color)
                }
            }

            tappable(alight.gps) {
                TimelineRow(time: alight.time, delaySeconds: delay, top: color, node: .stop(color)) {
                    VStack(alignment: .leading, spacing: 4) {
                        stopText(alight.name, alight.platform).font(.body.weight(.semibold))
                        (isLast ? Text("Arrive") : Text("Get off")).font(.subheadline).foregroundColor(.secondary)
                    }
                }
            }
            .accessibilityLabel(
                (isLast ? Text("Arrive at \(spokenTime(alight.time, delaySeconds: delay)) at \(alight.name)")
                    : Text("Get off at \(spokenTime(alight.time, delaySeconds: delay)) at \(alight.name)"))
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
                    // As on the Live Activity, the walk ends as late as the last vehicle.
                    let delay = parts.lastIndex { $0.routeType != 64 }.flatMap(model.delaySeconds)
                    tappable(end.endStopGps) {
                        TimelineRow(time: end.endArrival, delaySeconds: delay, top: nil, node: .stop(.systemGray)) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(end.endStopName ?? "").font(.body.weight(.semibold))
                                Text("Arrive").font(.subheadline).foregroundColor(.secondary)
                            }
                        }
                    }
                    .accessibilityLabel(
                        Text("Arrive at \(spokenTime(end.endArrival, delaySeconds: delay)) at \(end.endStopName ?? "")")
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
        let platform = (ride?.startStopCode ?? last.endStopCode).nonEmpty
        if first.startStopName == name, let platform {
            return Text("Walk \(minutes) min to platform \(platform)")
        }
        return Text("Walk \(minutes) min to \(name)") + platformText(platform)
    }

    private func changeText(_ ride: Part) -> Text {
        Text("Change at \(ride.startStopName ?? "")") + platformText(ride.startStopCode)
    }

    private func rideLabel(_ part: Part, delaySeconds: Int?) -> Text {
        var label = Text("Line \(part.routeShortName ?? "") to \(part.tripHeadsign ?? ""), departs \(spokenTime(part.startDeparture, delaySeconds: delaySeconds)) from \(part.startStopName ?? "")")
            + platformSpoken(part.startStopCode)
            + Text(", arrives \(spokenTime(part.endArrival, delaySeconds: delaySeconds)) at \(part.endStopName ?? "")")
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
    /// The step the trip Live Activity shows while it follows this journey.
    let liveStep: TripActivityAttributes.ContentState?
    /// The sheet's `delays`, passed in so the times redraw when the trip Live Activity's live delays change while
    /// its step stays the same.
    let delays: [Int: Int]
    @ScaledMetric(relativeTo: .headline) private var badgeSize = 17.0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var journey: Journey { model.journey }

    var body: some View {
        let parts = journey.parts ?? []
        if let first = parts.first, let last = parts.last {
            // A late first vehicle moves the start; the last one moves the arrival, a walk after it included.
            let startDelay = first.routeType == 64 ? nil : delays[0]
            let endDelay = parts.lastIndex { $0.routeType != 64 }.flatMap { delays[$0] }
            let start = first.startDeparture.expected(delaySeconds: startDelay)
            let minutes = minutesBetween(start, last.endArrival.expected(delaySeconds: endDelay))
            // The day too, when it isn't today.
            let day = dayStringUnlessToday(start).map { "\($0) " } ?? ""
            let times = Text(verbatim: day) + timeText(first.startDeparture, delaySeconds: startDelay)
                + Text(verbatim: " → ") + timeText(last.endArrival, delaySeconds: endDelay)
            VStack(alignment: .leading, spacing: 10) {
                if let liveStep {
                    LiveStepView(state: liveStep, badgeSize: badgeSize)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(minutes) min").font(.title2.bold())
                        Spacer()
                        times.font(.headline).foregroundColor(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(minutes) min").font(.title2.bold())
                        times.font(.headline).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
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
                liveStepText
                    + Text("\(minutes) min, \(day)\(spokenTime(first.startDeparture, delaySeconds: startDelay)) to \(spokenTime(last.endArrival, delaySeconds: endDelay)), ")
                    + changesText + Text(", ") + walkText + Text(", ") + zonesText
            )
        }
    }

    private var liveStepText: Text {
        guard let liveStep else { return Text(verbatim: "") }
        return (liveStep.line.map { Text("Line \($0), ") } ?? Text(verbatim: ""))
            + Text(verbatim: "\(liveStep.title), \(liveStep.detail). ")
            + (liveStep.warningText.map { Text(verbatim: "\($0). ") } ?? Text(verbatim: ""))
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

    /// One line in a capsule; wrapped in a rounded rectangle at accessibility text sizes, so it is never cut off.
    private func chip(_ text: Text) -> some View {
        let wraps = dynamicTypeSize.isAccessibilitySize
        return text
            .font(.footnote.weight(.medium))
            .lineLimit(wraps ? nil : 1)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                (wraps ? AnyShape(RoundedRectangle(cornerRadius: 12, style: .continuous)) : AnyShape(Capsule()))
                    .fill(Color.tertiarySystemFill)
            )
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

/// The trip's current step, as on the Live Activity: "Board at Trnavské mýto" beside the 63, "Platform A · in 4 min".
private struct LiveStepView: View {
    let state: TripActivityAttributes.ContentState
    let badgeSize: CGFloat

    var body: some View {
        HStack(spacing: 10) {
            if let line = state.line {
                LineText(line, badgeSize)
            } else {
                Image(systemName: state.step == .arrived ? "checkmark.circle.fill"
                    : state.step == .missed ? "exclamationmark.triangle.fill" : "figure.walk")
                    .font(.title3.weight(.semibold))
                    .foregroundColor(state.step == .arrived ? .green : state.step == .missed ? .orange : .accentColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(state.title).font(.headline)
                Text(state.detail).font(.subheadline).foregroundColor(.secondary)
                if let warning = state.warningText {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(state.warning == .likelyMissedChange ? .red : .orange)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Once the location showed the traveller off a ride: the other connections from where they are, to follow one
/// instead, or keep following the trip.
private struct MissedRideView: View {
    let missed: TripMissed
    let journey: Journey
    let badgeSize: CGFloat
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let line = journey.parts?[missed.part].routeShortName ?? ""
        VStack(alignment: .leading, spacing: 12) {
            Text(
                missed.boarded
                    ? "You're away from the route of the \(line). Follow another connection from where you are:"
                    : "The \(line) left without you. Follow another connection from where you are:"
            )
            .font(.subheadline)
            .fixedSize(horizontal: false, vertical: true)
            if let alternatives = missed.alternatives {
                if alternatives.isEmpty {
                    Text("No other connections found.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                group("Same route", alternatives.sameRoute)
                group("Other routes", alternatives.others)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                    Text("Finding other connections…")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            Button {
                GlobalController.tripLiveActivity.keepFollowing()
            } label: {
                Text("Keep following this trip")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityHint("Goes on with this trip's steps.")
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private func group(_ title: LocalizedStringKey, _ journeys: [Journey]) -> some View {
        if !journeys.isEmpty {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundColor(.secondary)
                .accessibilityAddTraits(.isHeader)
            ForEach(journeys, id: \.id) { row($0) }
        }
    }

    @ViewBuilder
    private func row(_ alternative: Journey) -> some View {
        let parts = alternative.parts ?? []
        if let ride = parts.first(where: { $0.routeType != 64 }), let last = parts.last {
            let lines = alternative.lines().map { $0 ?? "?" }
            let lastDelay = parts.last { $0.routeType != 64 }?.delaySeconds
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
                : AnyLayout(HStackLayout(spacing: 10))
            Button {
                GlobalController.tripLiveActivity.start(alternative)
                GlobalController.appState.pendingJourney = alternative
            } label: {
                HStack {
                    layout {
                        HStack(spacing: 4) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { LineText($0.element, badgeSize) }
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            (timeText(ride.startDeparture, delaySeconds: ride.delaySeconds) + Text(verbatim: " → ")
                                + timeText(last.endArrival, delaySeconds: lastDelay))
                                .font(.headline)
                            stopText(ride.startStopName, ride.startStopCode)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.tertiaryLabel)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(
                Text("Line \(lines.joined(separator: ", then line ")), from \(ride.startStopName ?? "")")
                    + platformSpoken(ride.startStopCode) + Text(", ")
                    + spokenTime(ride.startDeparture, delaySeconds: ride.delaySeconds) + Text(" to ")
                    + spokenTime(last.endArrival, delaySeconds: lastDelay)
            )
            .accessibilityHint("Follows this connection instead.")
        }
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

        var diameter: CGFloat {
            switch self {
            case .stop: return 16
            case .middle: return 10
            case .none, .walk: return 0
            }
        }

        var ringWidth: CGFloat {
            switch self {
            case .stop: return 4
            case .middle: return 2.5
            case .none, .walk: return 0
            }
        }
    }

    let time: Date?
    /// Seconds late, which moves `time`.
    var delaySeconds: Int? = nil
    var top: Color?
    var bottom: Color?
    var node = Node.none
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .subheadline) private var timeWidth = 46.0
    /// Half a capital letter of the stop name: the node sits that far above its first baseline, centred on it.
    @ScaledMetric(relativeTo: .body) private var capHeightHalf = 6.0

    var body: some View {
        // At accessibility text sizes the time moves above the content, which keeps the full width.
        let isStacked = dynamicTypeSize.isAccessibilitySize
        // The time and the node line up with the first line of the content, however many lines it wraps to.
        HStack(alignment: .timelineFirstLine, spacing: 10) {
            if !isStacked {
                timeText(stacked: false)
                    .frame(width: timeWidth, alignment: .trailing)
            }
            nodeShape
                .frame(width: node.diameter, height: node.diameter)
                .frame(width: 18)
                .alignmentGuide(.timelineFirstLine) { $0[VerticalAlignment.center] + capHeightHalf }
                .anchorPreference(key: TimelineNodeCenter.self, value: .center) { $0 }
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                if isStacked, time != nil {
                    timeText(stacked: true)
                }
                content
                    .alignmentGuide(.timelineFirstLine) { $0[.firstTextBaseline] }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
        }
        .padding(.leading, isStacked ? 12 : 0)
        .fixedSize(horizontal: false, vertical: true)
        // The rail runs the row's full height, into the node from above and out of it below.
        .backgroundPreferenceValue(TimelineNodeCenter.self) { center in
            GeometryReader { geometry in
                if let center {
                    rail(at: geometry[center], height: geometry.size.height)
                }
            }
            .accessibilityHidden(true)
        }
    }

    /// The expected time, with the scheduled one struck through below it, or beside it when stacked.
    private func timeText(stacked: Bool) -> some View {
        let expected = time.map { timeStringFromDate($0.expected(delaySeconds: delaySeconds)) } ?? ""
        let scheduled = time.map(timeStringFromDate).flatMap { $0 == expected ? nil : $0 }
        let texts = Group {
            Text(expected).font(.subheadline.monospacedDigit())
            if let scheduled {
                Text(scheduled).font(.caption.monospacedDigit()).strikethrough()
            }
        }
        return Group {
            if stacked {
                HStack(alignment: .firstTextBaseline, spacing: 6) { texts }
            } else {
                VStack(alignment: .trailing, spacing: 0) { texts }
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .foregroundColor(.secondary)
    }

    @ViewBuilder
    private var nodeShape: some View {
        switch node {
        case .stop(let color), .middle(let color):
            Circle().strokeBorder(color, lineWidth: node.ringWidth)
        case .none, .walk:
            Color.clear
        }
    }

    @ViewBuilder
    private func rail(at center: CGPoint, height: CGFloat) -> some View {
        if case .walk = node {
            line(at: center.x, from: 0, to: height)
                .stroke(Color.systemGray, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [0.5, 8]))
        } else if node.diameter == 0, top == bottom {
            // One line, without a seam where two would meet.
            line(at: center.x, from: 0, to: height).stroke(top ?? .clear, lineWidth: 4)
        } else {
            // Into the node's ring, not its middle, which stays clear whatever the row's background.
            let stop = (node.diameter - node.ringWidth) / 2
            line(at: center.x, from: 0, to: center.y - stop).stroke(top ?? .clear, lineWidth: 4)
            line(at: center.x, from: center.y + stop, to: height).stroke(bottom ?? .clear, lineWidth: 4)
        }
    }

    private func line(at x: CGFloat, from y0: CGFloat, to y1: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: x, y: y0))
            path.addLine(to: CGPoint(x: x, y: max(y0, y1)))
        }
    }
}

private extension VerticalAlignment {
    /// A timeline row's content's first line.
    enum TimelineFirstLine: AlignmentID {
        static func defaultValue(in dimensions: ViewDimensions) -> CGFloat {
            dimensions[.firstTextBaseline]
        }
    }

    static let timelineFirstLine = VerticalAlignment(TimelineFirstLine.self)
}

/// Where a timeline row's node is.
private struct TimelineNodeCenter: PreferenceKey {
    static let defaultValue: Anchor<CGPoint>? = nil

    static func reduce(value: inout Anchor<CGPoint>?, nextValue: () -> Anchor<CGPoint>?) {
        value = value ?? nextValue()
    }
}

private extension View {
    /// Timeline rows touch each other so the rail looks continuous.
    func timelineRow() -> some View {
        listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 16))
            .listRowSeparator(.hidden)
            .listRowBackground(cardBackground)
    }
}

/// Worded as on the trip Live Activity (`getDelayText`).
private struct DelayText: View {
    let seconds: Int?

    var body: some View {
        if let seconds {
            let minutes = delayMinutes(seconds)
            Group {
                if minutes > 0 {
                    Text("\(minutes) min delay")
                } else if minutes < 0 {
                    Text("\(-minutes) min in advance")
                } else {
                    Text("no delay")
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(getDelayColor(minutes, "online"))
            // Before the headsign beside it, which wraps instead.
            .layoutPriority(1)
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

/// Tints the step the followed trip is at.
private struct CurrentStep: ViewModifier {
    let isCurrent: Bool

    func body(content: Content) -> some View {
        if isCurrent {
            content
                .listRowBackground(Color.accentColor.opacity(0.15).background(cardBackground))
                .accessibilityValue(Text("Current step"))
        } else {
            content
                .listRowBackground(cardBackground)
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

/// The platform sign and letter after a stop name, nothing without a platform. A no-break space and a word joiner
/// keep the sign and the letter on the line that ends the name.
private func platformText(_ platform: String?) -> Text {
    guard let platform = platform.nonEmpty else { return Text(verbatim: "") }
    return (Text(verbatim: "\u{00A0}") + Text(Image("stop")) + Text(verbatim: "\u{2060}\(platform)"))
        .foregroundColor(.secondary)
}

private func stopText(_ name: String?, _ platform: String?) -> Text {
    Text(name ?? "") + platformText(platform)
}

private func platformSpoken(_ platform: String?) -> Text {
    platform.nonEmpty.map { Text(", platform \($0)") } ?? Text(verbatim: "")
}

/// The expected time, then the scheduled one struck through while they show differently.
private func timeText(_ scheduled: Date, delaySeconds: Int?) -> Text {
    let expected = timeStringFromDate(scheduled.expected(delaySeconds: delaySeconds))
    let planned = timeStringFromDate(scheduled)
    guard expected != planned else { return Text(verbatim: planned) }
    return Text(verbatim: "\(expected) ") + Text(verbatim: planned).strikethrough()
}

/// The expected time, and the scheduled one while they show differently.
private func spokenTime(_ scheduled: Date, delaySeconds: Int?) -> Text {
    let expected = timeStringFromDate(scheduled.expected(delaySeconds: delaySeconds))
    let planned = timeStringFromDate(scheduled)
    return expected == planned ? Text(verbatim: planned) : Text("\(expected), scheduled \(planned)")
}

/// The sheet's cards. From iOS 26 the sheet is glass, and turns opaque at its large detent, white like the grouped
/// cards in light mode, so they take a fill that stands out from either.
private var cardBackground: Color {
    if #available(iOS 26.0, *) {
        return .tertiarySystemFill
    }
    return .secondarySystemGroupedBackground
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
