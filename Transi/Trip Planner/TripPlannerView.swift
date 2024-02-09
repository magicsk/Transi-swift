//
//  TripPlannerView.swift
//  Transi
//
//  Created by magic_sk on 08/05/2023.
//

import SwiftUI

struct TripPlannerView: View {
    @ObservedObject var dataProvider: DataProvider
    @Environment(\.openURL) var openURL
    @State private var stop: Stop = .example
    @State private var lastField = ""
    @State private var showStopList = false
    @State private var dateDialog = false
    private let feedbackGenerator = UIImpactFeedbackGenerator(style: .rigid)

    init(_ dataProvider: DataProvider) {
        self.dataProvider = dataProvider
        feedbackGenerator.prepare()
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.systemGroupedBackground.edgesIgnoringSafeArea(.all)
                VStack(spacing: .zero) {
                    TripPlannerSearchInputs(
                        from: $dataProvider.tripFrom,
                        to: $dataProvider.tripTo,
                        lastField: $lastField,
                        showStopList: $showStopList
                    )
                    HStack {
                        Picker(selection: $dataProvider.tripArrivalDeprature) {
                            Text("Departure").tag(ArrivalDeparture.departure)
                            Text("Arrival").tag(ArrivalDeparture.arrival)
                        }
                        .pickerStyle(.segmented)
                        .width(175.0)
                        .onChange(of: dataProvider.tripArrivalDeprature) { _ in
                            feedbackGenerator.impactOccurred()
                            dataProvider.fetchTrip()
                        }
                        Spacer()
                        TripPlannerDateButton($dataProvider.tripArrivalDepratureDate, dateDialog: $dateDialog, customDate: dataProvider.tripArrivalDepratureCustomDate)
                    }
                    .padding(.horizontal, 24.0)
                    .padding(.top, -10.0)
                    .padding(.bottom, 10.0)
                    ZStack {
                        VStack {
                            if dataProvider.trip.journey != nil {
                                TripPlannerList(dataProvider)
                            } else {
                                Image(systemName: "signpost.right.and.left").font(.system(size: 96.0, weight: .light)).foregroundColor(.tertiaryLabel)
                                    .padding(.bottom, 2.5)
                                Text("Plan your first trip.").foregroundColor(.secondaryLabel)
                            }
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .backgroundFill(.systemGroupedBackground)
                        VStack {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .padding(.bottom, 2.5)
                            Text("Loading...")
                                .foregroundColor(.secondaryLabel)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(
                            Color.clear
                                .background(.ultraThinMaterial)
                                .blur(radius: 10)
                        )
                        .visible(dataProvider.tripLoading)
                        .animation(.easeInOut(duration: 0.25), value: dataProvider.tripLoading)
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
                TripPlannerDatePicker(dataProvider, $dateDialog, $dataProvider.tripArrivalDepratureCustomDate)
            }
            .sheet(isPresented: $showStopList) {
                StopListView(stop: self.$stop, stopList: dataProvider.stops, isPresented: self.$showStopList)
            }
            .alert(isPresented: $dataProvider.tripError.isNotNil(), error: dataProvider.tripError) { _ in } message: { error in
                if let message = error.errorMessage {
                    Text(message)
                }
            }
            .onChange(of: stop) { stop in
                print(stop)
                if lastField == "from" {
                    self.dataProvider.tripFrom = stop
                } else {
                    self.dataProvider.tripTo = stop
                }
                dataProvider.fetchTrip()
            }
        }
    }
}

// struct TripPlannerView_Previews: PreviewProvider {
//    static var previews: some View {
//        @ObservedObject var dataProvider = DataProvider()
//        TripPlannerView(dataProvider)
//    }
// }
