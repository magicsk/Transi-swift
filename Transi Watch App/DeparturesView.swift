//
//  DeparturesView.swift
//  Transi Watch App
//
//  Created by magic_sk on 19/11/2026.
//

import SwiftUI

/// The departure board of the nearest or the chosen stop, which the app opens on.
struct DeparturesView: View {
    @StateObject private var virtualTable = GlobalController.virtualTable
    @StateObject private var stopsList = GlobalController.stopsListProvider
    @State private var route: Route?
    /// Taps on the favorite star, for its haptic; the star also changes with the stop or a sync.
    @State private var favoriteTaps = 0

    private enum Route: Hashable {
        case stops, tripPlanner, serviceInfo
    }

    private var stop: Stop { virtualTable.currentStop }
    private var isFavorite: Bool { stopsList.favoriteStopIds.contains(stop.id) }

    var body: some View {
        List {
            if virtualTable.connections.isEmpty {
                // The header says why it's still loading: reconnecting, locating, or location off.
                Section {
                    status
                } header: {
                    header
                }
            } else {
                Section {
                    ForEach(virtualTable.connections) { connection in
                        NavigationLink {
                            DepartureDetailView(connection: connection)
                        } label: {
                            DepartureRow(
                                connection: connection,
                                platform: shownPlatformLabel(stop.platformLabels, connection.platform)
                            )
                        }
                    }
                } header: {
                    header
                }
            }
        }
        .navigationTitle(stop.name ?? "Transi")
        .containerBackground(Color.accentColor.gradient.opacity(0.35), for: .navigation)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { route = .stops } label: {
                    Image(systemName: "list.bullet")
                }
                .accessibilityLabel("Stops")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { route = .tripPlanner } label: {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond")
                }
                .accessibilityLabel("Plan Trip")
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button { route = .serviceInfo } label: {
                    Image(systemName: "exclamationmark.bubble")
                        .symbolVariant(virtualTable.unreadInfoCount > 0 ? .fill : .none)
                        .foregroundStyle(virtualTable.unreadInfoCount > 0 ? .orange : .primary)
                }
                .accessibilityLabel(
                    virtualTable.unreadInfoCount > 0
                        ? String(localized: "Service Info, \(virtualTable.unreadInfoCount) unread")
                        : String(localized: "Service Info")
                )
                Spacer()
                if stop.id > 0 {
                    Button {
                        stopsList.toggleFavorite(stop.id)
                        favoriteTaps += 1
                    } label: {
                        Image(systemName: isFavorite ? "star.fill" : "star")
                            .foregroundStyle(isFavorite ? .yellow : .primary)
                    }
                    .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
                    .sensoryFeedback(.success, trigger: favoriteTaps)
                }
            }
        }
        .navigationDestination(item: $route) { route in
            switch route {
            case .stops: StopsView()
            case .tripPlanner: TripPlannerView()
            case .serviceInfo: ServiceInfoView()
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        if virtualTable.socketStatus != .connected {
            Label("Connecting…", systemImage: "wifi.exclamationmark")
        } else if virtualTable.changeLocation {
            // Following the location, but without a fix the board shows a fallback stop, not the nearest one.
            if LocationProvider.lastLocation != nil {
                Label("Nearest stop", systemImage: "location.fill")
            } else if LocationProvider.isLocationAvailable {
                Label("Locating…", systemImage: "location")
            } else {
                Label("Location off", systemImage: "location.slash")
            }
        }
    }

    /// Loading, empty and offline states, before there are departures to show.
    @ViewBuilder
    private var status: some View {
        if stopsList.unmodifiedStops.isEmpty && stopsList.fetchError {
            ContentUnavailableView(
                "No Connection", systemImage: "wifi.slash",
                description: Text("Transi will try again in a moment.")
            )
        } else if virtualTable.connectionsEmpty {
            ContentUnavailableView(
                "No Departures", systemImage: "bus",
                description: Text("Nothing leaves this stop soon.")
            )
        } else {
            HStack {
                Spacer()
                ProgressView()
                Spacer()
            }
            .listRowBackground(Color.clear)
            .accessibilityLabel("Loading departures")
        }
    }
}

struct DepartureRow: View {
    let connection: Connection
    /// The platform letter, empty when unknown.
    let platform: String
    /// Wrist down, the dimmed app redraws at most once a minute, so a countdown would go stale.
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    var body: some View {
        VStack(alignment: .leading, spacing: 3.0) {
            HStack(spacing: 6.0) {
                LineText(connection.line, 15.0)
                Text(connection.headsign)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            HStack(spacing: 4.0) {
                // The delay in words, not just its colour, which not everyone can tell apart.
                if connection.type == "online" && connection.delay != 0 {
                    Text(connection.delay > 0 ? "+\(connection.delay)" : "\(connection.delay)")
                        .fontWeight(.semibold)
                        .foregroundStyle(getDelayColor(connection.delay, connection.type))
                } else {
                    Circle()
                        .fill(getDelayColor(connection.delay, connection.type))
                        .frame(width: 6.0, height: 6.0)
                }
                if !platform.isEmpty {
                    Text(platform).fontWeight(.semibold)
                }
                if connection.stuck {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
                }
                if hasLastStop {
                    // Where the vehicle is now, marked like on the iPhone so it doesn't read as a via stop.
                    StopIcon()
                    Text(connection.lastStopName).lineLimit(1)
                }
                Spacer(minLength: 4.0)
                Text(isLuminanceReduced ? clockTime(connection) : connection.departureTimeRemaining)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.primary)
                    .fixedSize()
                    .contentTransition(.numericText(countsDown: true))
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2.0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [
                String(localized: "Line \(connection.line) to \(connection.headsign)"),
                // "~" would be read as "tilde"; "scheduled" says it.
                connection.departureTimeRemaining.replacingOccurrences(of: "~", with: ""),
                platform.isEmpty ? nil : String(localized: "platform \(platform)"),
                connection.type == "online" ? connection.delayText : String(localized: "scheduled"),
                connection.stuck ? String(localized: "vehicle stuck") : nil,
                hasLastStop ? String(localized: "now at \(connection.lastStopName)") : nil,
            ].compactMap { $0 }.joined(separator: ", ")
        )
    }

    private var hasLastStop: Bool { connection.type == "online" && connection.lastStopName != "none" }
}

/// The operator's notices about closures and diversions.
struct ServiceInfoView: View {
    @StateObject private var virtualTable = GlobalController.virtualTable

    var body: some View {
        List {
            if virtualTable.infoTexts.isEmpty && virtualTable.socketStatus != .connected {
                // Offline, no notices have come yet; "everything runs as planned" would be a guess.
                ContentUnavailableView(
                    "Connecting…", systemImage: "wifi.exclamationmark",
                    description: Text("Notices load once Transi is online.")
                )
            } else if virtualTable.infoTexts.isEmpty {
                ContentUnavailableView(
                    "No Service Info", systemImage: "checkmark.circle",
                    description: Text("Everything runs as planned.")
                )
            } else {
                ForEach(virtualTable.infoTexts, id: \.self) { text in
                    Text(text).font(.footnote)
                }
            }
        }
        .navigationTitle("Service Info")
        .onAppear { virtualTable.markInfoTextsRead() }
        .onChange(of: virtualTable.infoTexts) { virtualTable.markInfoTextsRead() }
    }
}

/// The departure's clock time, which can't go stale like a countdown; "~" marks timetable-only ones like the board.
func clockTime(_ connection: Connection) -> String {
    connection.type == "online" ? connection.departureTime : "~" + connection.departureTime
}

#Preview {
    NavigationStack {
        List {
            DepartureRow(connection: .example, platform: "A")
            DepartureRow(connection: .example2, platform: "B")
            DepartureRow(connection: .example3, platform: "")
        }
    }
}
