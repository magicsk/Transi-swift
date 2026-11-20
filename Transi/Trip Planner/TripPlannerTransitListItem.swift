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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// Keeps the times in a column; they never wrap or truncate, which a fixed width did above the default size.
    @ScaledMetric(relativeTo: .body) private var timeWidth = 47.5

    init(_ part: Part) {
        self.part = part
    }

    var body: some View {
        Label {
            VStack(alignment: .leading) {
                Group {
                    // Wraps where a scrolling marquee would be hard to read or move too much.
                    if reduceMotion || dynamicTypeSize.isAccessibilitySize {
                        Text(part.tripHeadsign ?? "Error")
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        MarqueeText(
                            text: part.tripHeadsign ?? "Error",
                            font: UIFont.preferredFont(forTextStyle: .headline),
                            leftFade: 16,
                            rightFade: 16,
                            startDelay: 0
                        )
                    }
                }
                .padding(.leading, 20.0)
                // Stacked at accessibility sizes, the boarding and alighting stops need a gap between them.
                VStack(alignment: .leading, spacing: dynamicTypeSize.isAccessibilitySize ? 8.0 : nil) {
                    stopLine(part.startDeparture, part.startStopName, part.startStopCode)
                    stopLine(part.endArrival, part.endStopName, part.endStopCode)
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
        // A list's automatic style flows a wrapped title under the badge at accessibility text sizes.
        .ifCondition(dynamicTypeSize.isAccessibilitySize) { $0.labelStyle(.titleAndIcon) }
    }

    /// A time, stop and platform side by side, or the time above the stop at accessibility text sizes, where the
    /// three don't fit beside the line badge and the time would wrap or overlap the stop.
    private func stopLine(_ time: Date, _ name: String?, _ code: String?) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2.0))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
        return layout {
            Text(timeStringFromDate(time))
                .monospacedDigit()
                .fixedSize()
                .frame(minWidth: timeWidth, alignment: .leading)
            HStack(alignment: .bottom) {
                Text(name ?? "Error")
                TripPlannerStopCodeView(code: code)
            }
        }
    }
}

struct TripPlannerStopCodeView: View {
    let code: String?

    var body: some View {
        if let stopCode = code, !stopCode.isEmpty {
            HStack(alignment: .bottom, spacing: -2.0) {
                Image("stop")
                    .scaledToFit()
                    .foregroundColor(.systemGray)
                Text(stopCode)
                    .font(.subheadline.weight(.medium))
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
