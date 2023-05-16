//
//  TripPlannerTransitListItem.swift
//  Transi
//
//  Created by magic_sk on 14/05/2023.
//

import SwiftUI

struct TripPlannerTransitListItem: View {
    private let part: Part

    init(_ part: Part) {
        self.part = part
    }

    var body: some View {
        Label {
            VStack(alignment: .leading) {
                Text(part.tripHeadsign ?? "Error").font(.headline).lineLimit(1)
                VStack(alignment: .leading) {
                    HStack {
                        Text(timeStringFromUtc(part.startDeparture))
                        Text(part.startStopName ?? "Error")
                    }
                    HStack {
                        Text(timeStringFromUtc(part.endArrival))
                        Text(part.endStopName ?? "Error")
                    }
                }
            }
        }
        icon: {
            Text(part.routeShortName ?? "0").frame(minWidth: 50.0).foregroundColor(.accentColor)
        }
    }
}

// struct TripPlannerTransitListItem_Previews: PreviewProvider {
//    static var previews: some View {
//        TripPlannerTransitListItem()
//    }
// }