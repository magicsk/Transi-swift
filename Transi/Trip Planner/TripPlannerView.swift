//
//  TripPlannerView.swift
//  Transi
//
//  Created by magic_sk on 08/05/2023.
//

import SwiftUI

struct TripPlannerView: View {
    @Environment(\.openURL) var openURL
    @StateObject var tripPlannerController = GlobalController.tripPlanner
    @State private var stop: Stop = .example
    @State private var lastField = ""
    @State private var showStopList = false
    @State private var dateDialog = false
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .rigid)
    private let updateTabBarApperance: () -> Void

    init(_ updateTabBarApperance: @escaping () -> Void) {
        self.updateTabBarApperance = updateTabBarApperance
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.systemGroupedBackground.edgesIgnoringSafeArea(.all)
                VStack(spacing: .zero) {
                    TripPlannerSearchInputs(
                        from: $tripPlannerController.from,
                        to: $tripPlannerController.to,
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
                        TripPlannerDateButton($tripPlannerController.arrivalDepartureDate, dateDialog: $dateDialog, customDate: tripPlannerController.arrivalDepartureCustomDate)
                    }
                    .padding(.horizontal, 24.0)
                    .padding(.top, -10.0)
                    .padding(.bottom, 10.0)
                    ZStack {
                        VStack {
                            if tripPlannerController.trip.journey != nil {
                                TripPlannerList(tripPlannerController.trip, tripPlannerController.loading, tripPlannerController.loadingMore) { journey in
                                    tripPlannerController.loadMoreTripsIfNeeded(journey)
                                }
                            } else {
                                Image(systemName: "signpost.right.and.left").font(.system(size: 96.0, weight: .light)).foregroundColor(.tertiaryLabel)
                                    .padding(.bottom, 2.5)
                                Text("Plan your first trip.").foregroundColor(.secondaryLabel)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .backgroundFill(.systemGroupedBackground)
                        LoadingView($tripPlannerController.loading)
                    }
                }
                .padding(.top, -20.0)
                .navigationTitle(Text("Trip planner"))
                .toolbar {
                    Button("Settings") {
                        openURL(URL(string: UIApplication.openSettingsURLString)!)
                    }
                }
            }
            .sheet(isPresented: $dateDialog) {
                TripPlannerDatePicker($dateDialog)
            }
            .sheet(isPresented: $showStopList) {
                StopListView(stop: self.$stop, isPresented: self.$showStopList)
            }
            .alert(isPresented: $tripPlannerController.error.isNotNil(), error: tripPlannerController.error) { _ in } message: { error in
                if let message = error.failureReason {
                    Text(message)
                }
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
                feedbackGenerator.impactOccurred()
                tripPlannerController.fetchTrip()
            }
            .onAppear {
                updateTabBarApperance()
            }
        }
    }
}
