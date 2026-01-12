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

    init(
        _ trip: Trip, _ loading: Bool, _ loadingMore: Bool,
        loadMoreTripsIfNeeded: @escaping (_ journey: Journey) -> Void
    ) {
        self.trip = trip
        self.loading = loading
        self.loadingMore = loadingMore
        self.loadMoreTripsIfNeeded = loadMoreTripsIfNeeded
    }

    var body: some View {
        let journeys = trip.journey!
        ScrollViewReader { proxy in
            List(journeys, id: \.id) { journey in
                if let parts = journey.parts {
                    if journey.id == journeys.first?.id {
                        EmptyView().id("top")
                    }
                    Section {
                        ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                            if part.routeType == 64 {
                                TripPlannerWalkListItem(part, last: index == parts.count - 1)
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
                    if journey.id == journeys.last?.id {
                        if loadingMore {
                            Section {
                            } header: {
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
            .onChange(of: loading) { _ in
                proxy.scrollTo("top", anchor: .init(x: 0.0, y: -10.0))
            }
        }
    }
}

func getHeaderText(_ parts: [Part], _ zones: [String]?) -> String {
    if let first = parts.first, let last = parts.last {
        let startTime = timeStringFromDate(first.startDeparture)
        let duration = timeDiffFromDates(first.startDeparture, last.endArrival)
        let numOfZones = zones?.count ?? 0
        var timeDateSection = "\(startTime)"
        if !Calendar.current.isDate(first.startDeparture, inSameDayAs: Date()) {
            let startDate = dateStringFromDate(first.startDeparture)
            timeDateSection = "\(startDate) \(startTime)"
        }
        return "\(timeDateSection) | \(duration) min | \(numOfZones) zones"
    } else {
        return "Error"
    }
}

// struct TripPlannerList_Previews: PreviewProvider {
//    static var previews: some View {
//        TripPlannerList([Journey.example])
//    }
// }
