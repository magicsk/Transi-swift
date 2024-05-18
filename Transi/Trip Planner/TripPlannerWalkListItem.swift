//
//  TripPlannerWalkListItem.swift
//  Transi
//
//  Created by magic_sk on 14/05/2023.
//

import SwiftUI

struct TripPlannerWalkListItem: View {
    private let part: Part

    init(_ part: Part) {
        self.part = part
    }

    var body: some View {
        let sameStop = part.startStopName == part.endStopName
        HStack {
            Image(systemName: "figure.walk")
                .font(.system(size: 25.0))
                .foregroundColor(.accent)
                .frame(minWidth: 36.0)
            Text("\(timeDiffFromUtc(part.startDeparture, part.endArrival)) min to \(sameStop ? "platform \(part.endStopCode ?? "X")" : part.endStopName ?? "Error")")
        }.padding(.vertical, 3.0)
    }
}

 struct TripPlannerWalkListItem_Previews: PreviewProvider {
    static var previews: some View {
        TripPlannerWalkListItem(Part.example)
    }
 }
