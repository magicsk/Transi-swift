//
//  TripPlannerView.swift
//  Transi
//
//  Created by magic_sk on 08/05/2023.
//

import SwiftUI

struct TripPlannerView: View {
    @StateObject var tripPlannerController = GlobalController.tripPlanner
    @State private var showSettings = false
    @State private var stop: Stop = .example
    @State private var lastField = ""
    @State private var showStopList = false
    @State private var dateDialog = false
    @State private var path = [Journey]()
    /// A journey to show once the planner's sheets have gone, so the detail can present its own.
    @State private var journeyAfterSheets: Journey?
    private static let feedbackGenerator: UIImpactFeedbackGenerator = {
        let gen = UIImpactFeedbackGenerator(style: .rigid)
        gen.prepare()
        return gen
    }()

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Color.systemGroupedBackground.edgesIgnoringSafeArea(.all)
                VStack(spacing: .zero) {
                    TripPlannerSearchInputs(
                        lastField: $lastField,
                        showStopList: $showStopList
                    )
                    HStack {
                        Picker(selection: $tripPlannerController.arrivalDeparture) {
                            Text("Departure").tag(ArrivalDeparture.departure)
                            Text("Arrival").tag(ArrivalDeparture.arrival)
                        }
                        .pickerStyle(.segmented)
                        .width(175.0)
                        Spacer()
                        TripPlannerDateButton(
                            $tripPlannerController.arrivalDepartureDate, dateDialog: $dateDialog,
                            customDate: tripPlannerController.arrivalDepartureCustomDate)
                    }
                    .padding(.horizontal, 24.0)
                    .padding(.top, -10.0)
                    .padding(.bottom, 10.0)
                    CurrentTripButton(show: show)
                    ZStack {
                        VStack(spacing: .zero) {
                            if tripPlannerController.recentSearches.count > 1 {
                                recentSearchIndicator
                            }

                            if tripPlannerController.recentSearches.isEmpty {
                                currentTripResults
                            } else {
                                TabView(selection: selectedSearchID) {
                                    ForEach(pagedSearches) { search in
                                        tripResults(for: search)
                                            .tag(search.id)
                                    }
                                }
                                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .backgroundFill(.systemGroupedBackground)
                        LoadingView($tripPlannerController.loading)
                    }
                }
                .padding(.top, -16.0)
                .navigationTitle(Text("Trip planner"))
                .navigationDestination(for: Journey.self) { journey in
                    TripDetailView(journey: journey)
                }
                .toolbar {
                    Menu {
                        ForEach(tripPlannerController.recentSearches) { search in
                            Button {
                                tripPlannerController.showRecentSearch(search)
                            } label: {
                                Text(
                                    "\(search.from.name ?? "From") → \(search.to.name ?? "To")"
                                )
                            }
                        }
                        Divider()
                        Button("Clear Recents", role: .destructive) {
                            tripPlannerController.clearRecentSearches()
                        }
                    } label: {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .disabled(tripPlannerController.recentSearches.isEmpty)
                    .accessibilityLabel("Recent searches")

                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings, onDismiss: showJourneyAfterSheets) {
                SettingsView()
            }
            .sheet(isPresented: $dateDialog, onDismiss: showJourneyAfterSheets) {
                TripPlannerDatePicker($dateDialog)
            }
            .sheet(isPresented: $showStopList, onDismiss: showJourneyAfterSheets) {
                StopListView(stop: self.$stop, isPresented: self.$showStopList)
            }
            .alert(
                isPresented: $tripPlannerController.error.isNotNil(),
                error: tripPlannerController.error
            ) { _ in
            } message: { error in
                if let message = error.failureReason {
                    Text(message)
                }
            }
            .onReceive(GlobalController.appState.$pendingJourney.compactMap { $0 }) { journey in
                // Received as it is set, which would overwrite a nil set now.
                DispatchQueue.main.async {
                    if GlobalController.appState.pendingJourney == journey {
                        GlobalController.appState.pendingJourney = nil
                    }
                }
                guard showSettings || dateDialog || showStopList else {
                    show(journey)
                    return
                }
                // The detail presents its own sheet, which can't come up over these.
                journeyAfterSheets = journey
                showSettings = false
                dateDialog = false
                showStopList = false
            }
            .onChange(of: stop) { stop in
                if lastField == "from" {
                    tripPlannerController.from = stop
                } else {
                    tripPlannerController.to = stop
                }
                tripPlannerController.fetchTrip()
            }
            .onChange(of: tripPlannerController.arrivalDeparture) { _ in
                Self.feedbackGenerator.impactOccurred()
                if !tripPlannerController.currentSearchMatchesCriteria() {
                    tripPlannerController.fetchTrip()
                }
            }
        }
    }

    /// Replaces another journey's detail, but not this one's.
    private func show(_ journey: Journey) {
        if path.last != journey {
            path = [journey]
        }
    }

    private func showJourneyAfterSheets() {
        guard let journey = journeyAfterSheets else { return }
        journeyAfterSheets = nil
        show(journey)
    }

    private var currentSearchID: RecentTripSearch.ID {
        RecentTripSearch(
            from: tripPlannerController.from,
            to: tripPlannerController.to,
            trip: nil
        ).id
    }

    private var pagedSearches: [RecentTripSearch] {
        Array(tripPlannerController.recentSearches.reversed())
    }

    private var selectedSearchID: Binding<RecentTripSearch.ID> {
        Binding {
            currentSearchID
        } set: { id in
            guard let search = tripPlannerController.recentSearches.first(where: {
                $0.id == id
            }) else { return }
            tripPlannerController.showRecentSearch(search)
        }
    }

    private var recentSearchIndicator: some View {
        HStack(spacing: 7.0) {
            ForEach(pagedSearches) { search in
                Capsule()
                    .fill(search.id == currentSearchID ? Color.accentColor : Color.secondary)
                    .opacity(search.id == currentSearchID ? 1.0 : 0.3)
                    .frame(width: search.id == currentSearchID ? 16.0 : 6.0, height: 6.0)
            }
        }
        .padding(.vertical, 7.0)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "Recent search \(currentSearchIndex + 1) of \(tripPlannerController.recentSearches.count)"
        )
    }

    private var currentSearchIndex: Int {
        pagedSearches.firstIndex(where: {
            $0.id == currentSearchID
        }) ?? 0
    }

    @ViewBuilder
    private func tripResults(for search: RecentTripSearch) -> some View {
        if let trip = search.trip, trip.journey != nil {
            TripPlannerList(
                trip,
                search.id == currentSearchID && tripPlannerController.loading,
                search.id == currentSearchID && tripPlannerController.loadingMore
            ) { journey in
                guard search.id == currentSearchID else { return }
                tripPlannerController.loadMoreTripsIfNeeded(journey)
            }
        } else {
            emptyTripPlanner
        }
    }

    @ViewBuilder
    private var currentTripResults: some View {
        if tripPlannerController.trip.journey != nil {
            TripPlannerList(
                tripPlannerController.trip,
                tripPlannerController.loading,
                tripPlannerController.loadingMore,
                loadMoreTripsIfNeeded: tripPlannerController.loadMoreTripsIfNeeded
            )
        } else {
            emptyTripPlanner
        }
    }

    private var emptyTripPlanner: some View {
        VStack {
            Image(systemName: "signpost.right.and.left")
                .font(.system(size: 96.0, weight: .light))
                .foregroundColor(.tertiaryLabel)
                .padding(.bottom, 2.5)
            Text("Plan your first trip.").foregroundColor(.secondaryLabel)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The trip followed on the Lock Screen, which after a relaunch has no other way back in the app. It observes the trip
/// Live Activity itself, so the trip's refreshes redraw only this entry, not the whole planner.
private struct CurrentTripButton: View {
    @StateObject private var tripLiveActivity = GlobalController.tripLiveActivity
    let show: (Journey) -> Void

    var body: some View {
        if let journey = tripLiveActivity.journey {
            Button {
                show(journey)
            } label: {
                HStack(spacing: 12.0) {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(.accentColor)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2.0) {
                        Text("Current trip")
                            .font(.headline)
                        Text("\(journey.parts?.first?.startStopName ?? "Start") → \(journey.parts?.last?.endStopName ?? "End")")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8.0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.tertiaryLabel)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16.0)
                .padding(.vertical, 12.0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondarySystemGroupedBackground)
                .cornerRadius(26.0)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16.0)
            .padding(.bottom, 10.0)
            .accessibilityHint("Shows the trip on the map, step by step")
        }
    }
}

#Preview {
    TripPlannerView()
}
