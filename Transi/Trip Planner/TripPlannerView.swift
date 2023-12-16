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
    @State private var showStopList = false
    @State private var stop: Stop = .example
    @State private var lastField = ""

    init(_ dataProvider: DataProvider) {
        self.dataProvider = dataProvider
    }

    var body: some View {
        NavigationView {
            VStack(spacing: .zero) {
                VStack {
                    CocoaTextField(text: $dataProvider.tripFrom.name.toUnwrapped(defaultValue: "")) {
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
                    CocoaTextField(text: $dataProvider.tripTo.name.toUnwrapped(defaultValue: "")) {
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
                ZStack {
                    VStack {
                        if let journey = dataProvider.trip.journey {
                            TripPlannerList(journey)
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
                    .background(.ultraThinMaterial)
                    .padding(.top, -10.0)
                    .visible(dataProvider.tripLoading)
                    .animation(.easeInOut(duration: 0.25), value: dataProvider.tripLoading)
                }
            }
            .padding(.top, -20.0)
            .navigationTitle(Text("Trip planner"))
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

//struct TripPlannerView_Previews: PreviewProvider {
//    static var previews: some View {
//        @ObservedObject var dataProvider = DataProvider()
//        TripPlannerView(dataProvider)
//    }
//}
