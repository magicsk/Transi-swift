//
//  DepartureDetailView.swift
//  Transi Watch App
//
//  Created by magic_sk on 19/11/2026.
//

import SwiftUI

/// One departure, kept up to date while the board still lists it.
struct DepartureDetailView: View {
    let connection: Connection
    @StateObject private var virtualTable = GlobalController.virtualTable
    /// The board's last update of it, shown once it leaves the board.
    @State private var latest: Connection
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    init(connection: Connection) {
        self.connection = connection
        _latest = State(initialValue: connection)
    }

    /// The board's row for it: by id, or, once live tracking replaces a timetable row under a new id, the row on
    /// the exact same schedule at its stop, as the board itself matches them.
    private var onBoard: Connection? {
        virtualTable.connections.first { $0.id == latest.id }
            ?? virtualTable.connections.first {
                $0.stopId == latest.stopId && isSameDeparture($0, latest, within: 0)
            }
    }
    private var live: Connection { onBoard ?? latest }
    private var vehicle: VehicleInfo? { virtualTable.vehicleInfo.first { $0.issi == live.busID } }

    var body: some View {
        let live = live
        // Its own stop's labels: the board may have moved on to another stop.
        let platform = shownPlatformLabel(GlobalController.getStopById(live.stopId)?.platformLabels, live.platform)
        // Off the board the last update's countdown would freeze, so count down from its last estimate. Its "now" is
        // the board's "now"; leaving the board doesn't prove it departed, so it never says so.
        let countdown = onBoard?.departureTimeRemaining
            ?? getDepartureTimeRemainingText(live.departureTime, live.departureTimeRaw, live.type)
        // Wrist down the dimmed app redraws at most once a minute: the clock time can't go stale.
        let remaining = isLuminanceReduced ? clockTime(live) : countdown
        List {
            Section {
                HStack(spacing: 8.0) {
                    LineText(live.line, 20.0)
                    Text(live.headsign).font(.headline)
                }
                .accessibilityElement(children: .combine)
                .listRowBackground(Color.clear)
                // Its clock time once, when that is already the main value (wrist down, or over an hour away).
                let showsClock = remaining == clockTime(live) || remaining == live.departureTime
                LabeledContent("Departs") {
                    VStack(alignment: .trailing) {
                        Text(remaining).font(.headline.monospacedDigit()).foregroundStyle(.primary)
                        if !showsClock {
                            Text(live.departureTime).font(.footnote)
                        }
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    showsClock
                        ? String(localized: "Departs at \(remaining.replacingOccurrences(of: "~", with: ""))")
                        : String(localized: "Departs \(remaining.replacingOccurrences(of: "~", with: "")), at \(live.departureTime)")
                )
                if !platform.isEmpty {
                    LabeledContent("Platform", value: platform)
                }
                LabeledContent("Delay") {
                    Label {
                        Text(delayWords(live))
                    } icon: {
                        Image(systemName: "circle.fill")
                            .foregroundStyle(getDelayColor(live.delay, live.type))
                            .imageScale(.small)
                    }
                }
            }
            if onBoard == nil {
                Label("No longer on the board", systemImage: "clock.badge.xmark")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if live.stuck {
                Label("The vehicle is stuck", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
            }
            if live.type == "online" && live.lastStopName != "none" {
                Section("Now at") {
                    Label(live.lastStopName, systemImage: "mappin.and.ellipse")
                }
            }
            if live.type == "online", let vehicle {
                Section("Vehicle") {
                    Text(vehicle.type)
                    Label(
                        vehicle.ac ? "Air conditioning" : "No air conditioning",
                        systemImage: vehicle.ac ? "snowflake" : "snowflake.slash"
                    )
                    LabeledContent("Number", value: String(live.busID.dropFirst(2)))
                }
            }
        }
        .onChange(of: onBoard) { _, update in
            if let update { latest = update }
        }
    }
}

/// The delay as the value of a "Delay" row: "+2 min", "On time", "1 min early", or "scheduled" without live data.
private func delayWords(_ connection: Connection) -> String {
    guard connection.type == "online" else { return String(localized: "scheduled") }
    switch connection.delay {
    case 0: return String(localized: "On time")
    case 1...: return String(localized: "+\(connection.delay) min")
    default: return String(localized: "\(-connection.delay) min early")
    }
}

#Preview {
    NavigationStack {
        DepartureDetailView(connection: .example)
    }
}
