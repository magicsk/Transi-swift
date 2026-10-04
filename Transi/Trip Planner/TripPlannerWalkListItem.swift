//
//  TripPlannerWalkListItem.swift
//  Transi
//
//  Created by magic_sk on 14/05/2023.
//

import SwiftUI

struct TripPlannerWalkListItem: View {
    private let part: Part
    private let last: Bool

    init(_ part: Part, last: Bool = false) {
        self.part = part
        self.last = last
    }

    var body: some View {
        let sameStop = part.startStopName == part.endStopName
        HStack {
            Image(systemName: "figure.walk")
                .font(.system(size: 25.0))
                .foregroundColor(.accent)
                .frame(minWidth: 46.0)
            Text(
                "\(walkingMinutes) min to \(sameStop ? "platform \(part.endStopCode ?? "X")" : part.endStopName ?? "Error")"
            )
            .padding(.leading, 7.0)
            if !(sameStop || last) {
                TripPlannerStopCodeView(code: part.endStopCode)
            }
        }.padding(.vertical, 3.0)
    }

    private var walkingMinutes: Int {
        let minutes = max(0, Int(part.endArrival.timeIntervalSince(part.startDeparture) / 60))
        if isDifferentWalkingEndpoint && minutes < 1 {
            return 1
        }
        return minutes
    }

    private var isDifferentWalkingEndpoint: Bool {
        if part.startStopName != part.endStopName {
            return true
        }
        if part.startStopCode == part.endStopCode {
            return false
        }
        return part.startStopCode != nil || part.endStopCode != nil
    }
}

#Preview {
    //    TripPlannerList(Trip(journey: [Journey.example]), false, false) { _ in
    //    }
}
