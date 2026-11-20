//
//  JourneyDetailView.swift
//  Transi Watch App
//
//  Created by magic_sk on 19/11/2026.
//

import SwiftUI

/// A route leg by leg: what to board where and when, the walks, and changes that are tight.
struct JourneyDetailView: View {
    let journey: Journey

    var body: some View {
        let parts = journey.parts ?? []
        // With the delays the legs show, so a change the late first ride misses is flagged.
        let delays = Dictionary(uniqueKeysWithValues: parts.indices.compactMap { index in
            parts[index].delaySeconds.map { (index, $0) }
        })
        let buffers = journey.transferBuffers(delays: delays)
        List {
            if let times = journey.expectedTimes {
                let (start, end) = times
                let zones = journey.zones?.count ?? 0
                // The leave time goes here, not in the title, which sits under the clock and reads as a second one.
                // With the day for a trip on another day, as the results row has it.
                let leave = dayStringUnlessToday(start).map { "\($0) \(timeStringFromDate(start))" }
                    ?? timeStringFromDate(start)
                let arrive = timeStringFromDate(end)
                let minutes = minutesBetween(start, end)
                let summary = Text("Leave \(leave) · Arrive \(arrive) · \(minutes) min")
                (zones > 0 ? summary + Text(verbatim: " · ") + Text("^[\(zones) zone](inflect: true)") : summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .listRowBackground(Color.clear)
            }
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                if part.routeType == 64 {
                    Label {
                        Text(walkText(part, last: index == parts.count - 1))
                    } icon: {
                        Image(systemName: "figure.walk")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                } else {
                    Section {
                        if let buffer = buffers[index], buffer.isTight {
                            Label(
                                buffer.isLikelyMissed ? "Change likely missed" : "Tight change, \(buffer.minutes) min",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.footnote)
                            .foregroundStyle(buffer.isLikelyMissed ? .red : .orange)
                        }
                        HStack(spacing: 6.0) {
                            LineText(part.routeShortName ?? "?", 16.0)
                            Text(part.tripHeadsign ?? "").font(.headline).lineLimit(2)
                        }
                        .accessibilityElement(children: .combine)
                        StopTimeRow(
                            time: part.startDeparture, name: part.startStopName, platform: part.startStopCode,
                            delaySeconds: part.delaySeconds
                        )
                        StopTimeRow(
                            time: part.endArrival, name: part.endStopName, platform: part.endStopCode,
                            delaySeconds: part.delaySeconds
                        )
                        if part.tripId != nil || part.stops != nil {
                            NavigationLink {
                                PartStopsView(part: part)
                            } label: {
                                Label("All Stops", systemImage: "list.bullet")
                            }
                        }
                    }
                }
            }
        }
        // So the first boarding time fits above the fold under the summary.
        .listSectionSpacing(.compact)
        .navigationTitle("Route")
    }

    private func walkText(_ part: Part, last: Bool) -> String {
        let minutes = minutesBetween(part.startDeparture, part.endArrival)
        let destination = last ? nil : part.endStopName
        return destination.map { "Walk \(minutes) min to \($0)" } ?? "Walk \(minutes) min"
    }
}

/// A boarding or alighting stop: the time, with the delay the search found, and the stop.
private struct StopTimeRow: View {
    let time: Date
    let name: String?
    let platform: String?
    let delaySeconds: Int?

    var body: some View {
        let delay = delaySeconds.map(delayMinutes) ?? 0
        HStack(alignment: .firstTextBaseline, spacing: 6.0) {
            Text(timeStringFromDate(time.expected(delaySeconds: delaySeconds)))
                .font(.headline.monospacedDigit())
                .foregroundStyle(delay == 0 ? Color.primary : getDelayColor(delay, "online"))
            if delay != 0 {
                // In words too, like the board, not only as the time's colour.
                Text(delay > 0 ? "+\(delay)" : "\(delay)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(getDelayColor(delay, "online"))
            }
            VStack(alignment: .leading, spacing: 1.0) {
                Text(name ?? "").lineLimit(2)
                if let platform, !platform.isEmpty {
                    Text("Platform \(platform)").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Every stop of a leg, loaded when it opens.
private struct PartStopsView: View {
    let part: Part
    @State private var stops: [PartStop]?
    /// The trip's delay in seconds, live when the stops were fetched, so the times match the leg's.
    @State private var delaySeconds: Int?
    @State private var failed = false

    var body: some View {
        List {
            if let stops {
                ForEach(Array(stops.enumerated()), id: \.offset) { index, stop in
                    HStack(alignment: .firstTextBaseline, spacing: 6.0) {
                        Text(timeStringFromDate(stop.time.expected(delaySeconds: delaySeconds)))
                            .font(.footnote.monospacedDigit())
                        Text(stop.name)
                            .fontWeight(index == 0 || index == stops.count - 1 ? .semibold : .regular)
                            .lineLimit(2)
                        if stop.isRequestStop {
                            Image(systemName: "hand.raised.fill")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .accessibilityLabel("Request stop")
                        }
                    }
                }
            } else if failed {
                ContentUnavailableView(
                    "Stops Unavailable", systemImage: "wifi.slash",
                    description: Text("Check the connection and try again.")
                )
            } else {
                ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
            }
        }
        .navigationTitle(part.routeShortName.map { String(localized: "Line \($0)") } ?? String(localized: "Stops"))
        .task {
            delaySeconds = part.delaySeconds
            if let known = part.stops {
                stops = known
                return
            }
            GlobalController.tripPlanner.fetchStops(for: part) { loaded, delay in
                stops = loaded
                // The B-API reports the run on the road now, whatever its date, so it is this leg's only while live.
                if part.isLive(delaySeconds: delay) { delaySeconds = delay }
                failed = loaded == nil
            }
        }
    }
}
