//
//  TripPlannerList.swift
//  Transi
//
//  Created by magic_sk on 14/05/2023.
//

import SwiftUI

struct TripPlannerList: View {
    @ObservedObject var dataProvider: DataProvider
    init(_ dataProvider: DataProvider) {
        self.dataProvider = dataProvider
    }

    var body: some View {
        let journeys = dataProvider.trip.journey!
        ScrollViewReader { proxy in
            List(journeys, id: \.self) { journey in
                if let parts = journey.parts {
                    if journey.journeyGuid == journeys.first?.journeyGuid {
                        EmptyView().id("top")
                    }
                    Section {
                        ForEach(parts, id: \.self) { part in
                            if part.routeType == 64 {
                                TripPlannerWalkListItem(part)
                            } else if part.routeType != nil {
                                TripPlannerTransitListItem(part)
                            } else {
                                Text("Something went wrong")
                            }
                        }
                    } header: {
                        Text(getHeaderText(parts, journey.zones))
                    }
                    .onAppear {
                        dataProvider.loadMoreTripsIfNeeded(journey)
                    }
                    if journey.journeyGuid == journeys.last?.journeyGuid {
                        if dataProvider.tripLoadingMore {
                            Section {} header: {
                                HStack(alignment: .center) {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .padding(.vertical, 2.5)
                                }.width(1000.0)
                            }
                        }
                    }
                } else {
                    Text("Error")
                }
            }
            .listStyle(.insetGrouped)
            .onChange(of: dataProvider.tripLoading) {_ in
                proxy.scrollTo("top", anchor: .init(x: 0.0, y: -10.0))
            }
        }
    }
}

func getHeaderText(_ parts: [Part], _ zones: [Int]?) -> String {
    let first = parts.first
    let last = parts.last
    let startTime = timeStringFromUtc(first?.startDeparture)
    let duration = timeDiffFromUtc(first?.startDeparture, last?.endArrival)
    let numOfZones = zones?.count ?? 0
    return "\(startTime) | \(duration) min | \(numOfZones) zones"
}

// struct TripPlannerList_Previews: PreviewProvider {
//    static var previews: some View {
//        TripPlannerList([Journey.example])
//    }
// }
