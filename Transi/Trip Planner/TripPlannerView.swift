//
//  TripPlannerView.swift
//  Transi
//
//  Created by magic_sk on 08/05/2023.
//

import SwiftUI
import SwiftUIX

struct TripPlannerView: View {
    @ObservedObject var dataProvider: DataProvider
    @State private var from = Stop(name: "")
    @State private var to = Stop(name: "")
    @State private var showStopList = false
    @State private var stop: Stop = .example
    @State private var lastField = ""
    @State private var loading = false

    init(_ dataProvider: DataProvider) {
        self.dataProvider = dataProvider
    }

    var body: some View {
        NavigationView {
            VStack(spacing: .zero) {
                VStack {
                    CocoaTextField(text: $from.name.toUnwrapped(defaultValue: "")) {
                        Text("From").foregroundColor(.placeholderText)
                    }
                    .disabled(true)
                    .onTapGestureOnBackground {
                        lastField = "from"
                        self.showStopList = true
                    }
                    .onPress {
                        lastField = "from"
                        self.showStopList = true
                    }
                    Divider().padding(.bottom, 5.0)
                    CocoaTextField(text: $to.name.toUnwrapped(defaultValue: "")) {
                        Text("To").foregroundColor(.placeholderText)
                    }
                    .disabled(true)
                    .onTapGestureOnBackground {
                        lastField = "to"
                        self.showStopList = true
                    }
                    .onPress {
                        lastField = "to"
                        self.showStopList = true
                    }
                }.modifier(ListStackModifier())
                if let journey = dataProvider.trip.journey {
                    if journey.isEmpty {
                        VStack {
                            Text("Trip not found")
                        }.frame(maxHeight: .infinity)
                    } else {
                        TripPlannerList(journey)
                    }
                } else {
                    VStack {
                        if loading {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .padding(.bottom, 2.5)
                            Text("Loading...")
                                .foregroundColor(.secondaryLabel)
                        } else {
                            Image(systemName: "signpost.right.and.left").font(.system(size: 96.0, weight: .light)).foregroundColor(.tertiaryLabel)
                                .padding(.bottom, 2.5)
                            Text("Plan your first trip.").foregroundColor(.secondaryLabel)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .backgroundFill(.systemGroupedBackground)
                }
            }
            .padding(.top, -20.0)
            .navigationTitle(Text("Trip planner"))
        }
        .sheet(isPresented: $showStopList) {
            StopListView(stop: self.$stop, stopList: dataProvider.stops, isPresented: self.$showStopList)
        }
        .onChange(of: stop) { stop in
            print(stop)
            if lastField == "from" {
                self.from = stop
            } else {
                self.to = stop
            }
            print("from \(self.from.stationId ?? 0)")
            print("to \(self.to.stationId ?? 0)")
            if self.from.stationId != nil && self.to.stationId != nil {
                self.loading = true
                let fromId = from.stationId == -1 ? dataProvider.getNearestStationId() : from.stationId!
                let toId = to.stationId == -1 ? dataProvider.getNearestStationId() : to.stationId!
                print("both not null")
                dataProvider.fetchTrip(from: fromId, to: toId)
            }
        }
        .onChange(of: dataProvider.trip) { _ in
            if (dataProvider.trip.journey != nil) {
                self.loading = false
            }
        }
        .onChange(of: dataProvider.lastLocation) { lastLocation in
            if (lastLocation != nil && self.from.name == "") {
                self.from = dataProvider.actualLocationStop
            }
        }
    }
}

struct TripPlannerView_Previews: PreviewProvider {
    static var previews: some View {
        @ObservedObject var dataProvider = DataProvider()
        TripPlannerView(dataProvider)
    }
}
