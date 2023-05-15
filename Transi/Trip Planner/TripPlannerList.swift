//
//  TripPlannerList.swift
//  Transi
//
//  Created by magic_sk on 14/05/2023.
//

import SwiftUI

struct TripPlannerList: View {
    private var journeys: [Journey]
    init(_ journeys: [Journey]) {
        self.journeys = journeys
    }

    var body: some View {
        List(journeys, id: \.self) { journey in
            if let parts = journey.parts {
                Section(header: Text(getHeaderText(parts, journey.zones))) {
                    ForEach(parts, id: \.self) { part in
                        if part.routeType == 64 {
                            TripPlannerWalkListItem(part)
                        } else if part.routeType != nil {
                            TripPlannerTransitListItem(part)
                        } else {
                            Text("Something went wrong")
                        }
                    }
                }
            } else {
                Text("Error")
            }
        }
        .listStyle(.insetGrouped)
        .padding(.top, -10)
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
//        TripPlannerList()
//    }
// }
