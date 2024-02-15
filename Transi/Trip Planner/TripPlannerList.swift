//
//  TripPlannerList.swift
//  Transi
//
//  Created by magic_sk on 14/05/2023.
//

import SwiftUI

struct TripPlannerList: View {
    let trip: Trip
    let loading: Bool
    let loadingMore: Bool
    let loadMoreTripsIfNeeded: (_ journey: Journey) -> Void
    
    init(_ trip: Trip, _ loading: Bool, _ loadingMore: Bool, loadMoreTripsIfNeeded: @escaping (_ journey: Journey) -> Void) {
        self.trip = trip
        self.loading = loading
        self.loadingMore = loadingMore
        self.loadMoreTripsIfNeeded = loadMoreTripsIfNeeded
    }
    
    var body: some View {
        let journeys = trip.journey!
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
                        loadMoreTripsIfNeeded(journey)
                    }
                    if journey.journeyGuid == journeys.last?.journeyGuid {
                        if loadingMore {
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
            .onChange(of: loading) {_ in
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
