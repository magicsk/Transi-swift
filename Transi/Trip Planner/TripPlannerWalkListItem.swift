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
            Text(Self.text(for: part))
            .padding(.leading, 7.0)
            if !(sameStop || last) {
                TripPlannerStopCodeView(code: part.endStopCode)
            }
        }.padding(.vertical, 3.0)
    }

    /// "3 min to Záluhy", shown in the row and read in the journey's VoiceOver label.
    static func text(for part: Part) -> String {
        let sameStop = part.startStopName == part.endStopName
        return "\(walkingMinutes(part)) min to \(sameStop ? "platform \(part.endStopCode ?? "X")" : part.endStopName ?? "Error")"
    }

    private static func walkingMinutes(_ part: Part) -> Int {
        let minutes = max(0, Int(part.endArrival.timeIntervalSince(part.startDeparture) / 60))
        if isDifferentWalkingEndpoint(part) && minutes < 1 {
            return 1
        }
        return minutes
    }

    private static func isDifferentWalkingEndpoint(_ part: Part) -> Bool {
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
