//
//  TripPlannerView.swift
//  Transi Watch App
//
//  Created by magic_sk on 19/11/2026.
//

import SwiftUI

/// Where from, where to and when, plus the recent searches from the watch and the paired iPhone.
struct TripPlannerView: View {
    @StateObject private var planner = GlobalController.tripPlanner
    /// Re-renders when a location fix re-sorts the stops, which can make Current Location usable.
    @StateObject private var stopsList = GlobalController.stopsListProvider
    @State private var leavesNow = true
    @State private var showsResults = false
    /// Opening Plan Trip starts at Depart · Now; returning from a stop picker keeps what was set.
    @State private var hasAppeared = false

    /// Arriving "now" finds nothing useful, so an arrival always has a time.
    private var usesNow: Bool { leavesNow && planner.arrivalDeparture == .departure }

    private var canSearch: Bool {
        canSearch(from: planner.from, to: planner.to)
    }

    /// Without a fix, Current Location would resolve to whichever stop the list starts with.
    private func canSearch(from: Stop, to: Stop) -> Bool {
        let needsFix = from.id == Stop.actualLocation.id || to.id == Stop.actualLocation.id
        // A stop without a station can't be searched; the planner would wait for routes that never come.
        return from.name?.isEmpty == false && to.name?.isEmpty == false && from.id != to.id
            && from.stationId != nil && to.stationId != nil
            && (!needsFix || LocationProvider.lastLocation != nil)
    }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    StopsView(title: "From") { planner.from = $0 }
                } label: {
                    endpoint("From", planner.from)
                }
                NavigationLink {
                    StopsView(title: "To") { planner.to = $0 }
                } label: {
                    endpoint("To", planner.to)
                }
            }
            // Right under the stops, so a picked destination is one tap from its routes.
            Section {
                Button(action: search) {
                    Label("Find Routes", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSearch)
                .listRowBackground(Color.clear)
            } footer: {
                // The When rows sit below the fold; a time that isn't now is spelled out by the button.
                if !usesNow {
                    let time = planner.arrivalDepartureDate.formatted(date: .omitted, time: .shortened)
                    let day = dayStringUnlessToday(planner.arrivalDepartureDate).map { "\($0) " } ?? ""
                    Text(planner.arrivalDeparture == .arrival ? "Arrive by \(day)\(time)" : "Depart at \(day)\(time)")
                }
            }
            Section {
                Picker("When", selection: $planner.arrivalDeparture) {
                    Text("Depart").tag(ArrivalDeparture.departure)
                    Text("Arrive").tag(ArrivalDeparture.arrival)
                }
                if planner.arrivalDeparture == .departure {
                    Toggle("Now", isOn: $leavesNow)
                }
                if !usesNow {
                    DatePicker("Time", selection: $planner.arrivalDepartureDate, in: Date.now...)
                }
            }
            if !planner.recentSearches.isEmpty {
                Section("Recent") {
                    ForEach(planner.recentSearches) { recent in
                        Button {
                            planner.from = recent.from
                            planner.to = recent.to
                            planner.arrivalDeparture = .departure
                            leavesNow = true
                            search()
                        } label: {
                            VStack(alignment: .leading, spacing: 1.0) {
                                Text(name(of: recent.to)).font(.headline).lineLimit(2)
                                Text("from \(name(of: recent.from))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .disabled(!canSearch(from: recent.from, to: recent.to))
                        .accessibilityLabel("\(name(of: recent.from)) to \(name(of: recent.to))")
                    }
                }
            }
        }
        .navigationTitle("Plan Trip")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    let from = planner.from
                    planner.from = planner.to
                    planner.to = from
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }
                .accessibilityLabel("Swap From and To")
                .disabled(planner.from == .empty && planner.to == .empty)
            }
        }
        .onAppear {
            // The mode and time may come from an earlier search, even one restored at launch.
            if !hasAppeared {
                hasAppeared = true
                planner.arrivalDeparture = .departure
                leavesNow = true
            }
            freshenTime()
        }
        .onChange(of: usesNow) { freshenTime() }
        .onChange(of: planner.arrivalDeparture) { freshenTime() }
        .navigationDestination(isPresented: $showsResults) {
            TripResultsView()
        }
    }

    private func endpoint(_ title: LocalizedStringKey, _ stop: Stop) -> some View {
        VStack(alignment: .leading, spacing: 1.0) {
            Text(title).font(.footnote).foregroundStyle(.secondary)
            Text(stop == .empty ? "Choose a stop" : name(of: stop))
                .foregroundStyle(stop == .empty ? .secondary : .primary)
                .lineLimit(2)
            if stop.id == Stop.actualLocation.id && LocationProvider.lastLocation == nil {
                Text(LocationProvider.isLocationAvailable ? "Locating…" : "Location off")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func name(of stop: Stop) -> String {
        stop.id == Stop.actualLocation.id ? String(localized: "Current Location") : stop.name ?? ""
    }

    /// A time kept from an earlier search may be long past: depart from now, or arrive in half an hour.
    private func freshenTime() {
        guard !usesNow, planner.arrivalDepartureDate < .now else { return }
        planner.arrivalDepartureDate = .now + (planner.arrivalDeparture == .arrival ? 30 * 60 : 0)
    }

    private func search() {
        freshenTime()
        planner.arrivalDepartureCustomDate = !usesNow
        // The previous search's routes would show until the new ones arrive.
        planner.trip = Trip()
        planner.error = nil
        planner.fetchTrip()
        showsResults = true
    }
}

#Preview {
    NavigationStack {
        TripPlannerView()
    }
}
