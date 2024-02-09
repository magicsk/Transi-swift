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
                        Text(timeStringFromUtc(part.startDeparture)).frame(width: 47.5, alignment: .leading)
                        Text(part.startStopName ?? "Error")
                    }
                    HStack {
                        Text(timeStringFromUtc(part.endArrival)).frame(width: 47.5, alignment: .leading)
                        Text(part.endStopName ?? "Error")
                    }
                }.padding(.leading, 2.5)
            }
        }
        icon: {
            VStack(spacing: .zero) {
                LineText(part.routeShortName ?? "Error", 20.0).frame(minWidth: 50.0)
                Rectangle()
                    .frame(width: 2.5, height: 40.0)
                    .foregroundColor(colorFromLineNum(part.routeShortName ?? "Error")!)
            }
        }
//        .gesture(DragGesture(minimumDistance: 10, coordinateSpace: .global)
//            .onChanged { value in
//                print(value)
//                let draggedOffset = value.translation.height
//                if draggedOffset > 0 {
//                    offset = draggedOffset
//                } else {
//                    offset = 0
//                }
//            }
//            .onEnded { value in
//
//            })
    }
}

 struct TripPlannerTransitListItem_Previews: PreviewProvider {
    static var previews: some View {
        TripPlannerTransitListItem(Part.example)
    }
 }
