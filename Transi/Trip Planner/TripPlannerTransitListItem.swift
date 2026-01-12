//
//  TripPlannerTransitListItem.swift
//  Transi
//
//  Created by magic_sk on 14/05/2023.
//

import MarqueeText
import SwiftUI

struct TripPlannerTransitListItem: View {
    let part: Part

    init(_ part: Part) {
        self.part = part
    }

    var body: some View {
        Label {
            VStack(alignment: .leading) {
                MarqueeText(
                    text: part.tripHeadsign ?? "Error",
                    font: UIFont.preferredFont(forTextStyle: .headline),
                    leftFade: 16,
                    rightFade: 16,
                    startDelay: 0
                )
                .padding(.leading, 20.0)
                VStack(alignment: .leading) {
                    HStack(alignment: .bottom) {
                        Text(timeStringFromDate(part.startDeparture)).frame(
                            width: 47.5, alignment: .leading)
                        Text(part.startStopName ?? "Error")
                        TripPlannerStopCodeView(code: part.startStopCode)
                    }
                    HStack(alignment: .bottom) {
                        Text(timeStringFromDate(part.endArrival)).frame(
                            width: 47.5, alignment: .leading)
                        Text(part.endStopName ?? "Error")
                        TripPlannerStopCodeView(code: part.endStopCode)
                    }
                }.padding(.leading, 25.5)
            }
        } icon: {
            VStack(spacing: .zero) {
                LineText(part.routeShortName ?? "Error", 20.0).frame(minWidth: 50.0)
                Rectangle()
                    .frame(width: 2.5, height: 40.0)
                    .foregroundColor(colorFromLineNum(part.routeShortName ?? "Error")!)
            }.padding(.leading, 20.0)
        }
    }
}

struct TripPlannerStopCodeView: View {
    let code: String?

    var body: some View {
        if let stopCode = code {
            HStack(alignment: .bottom, spacing: -2.0) {
                Image("stop")
                    .scaledToFit()
                    .foregroundColor(.systemGray)
                Text(stopCode)
                    .font(.system(size: 15.0, weight: .medium))
                    .foregroundColor(.systemGray)
            }
        } else {
            EmptyView()
        }
    }
}

#Preview {
    TripPlannerTransitListItem(Part.example)
    Spacer()
}
