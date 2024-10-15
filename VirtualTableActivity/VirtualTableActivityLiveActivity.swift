//
//  VirtualTableActivityLiveActivity.swift
//  VirtualTableActivity
//
//  Created by magic_sk on 23/02/2024.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct VirtualTableActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var tab: Tab
        var vehicleInfo: VehicleInfo?
    }
}

struct VirtualTableActivityLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: VirtualTableActivityAttributes.self) { context in
            VirtualTableActivityLiveView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    LineText(context.state.tab.line, 20.0).padding(.leading, 10.0)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.tab.departureTimeRemaining)
                        .font(.headline)
                        .padding(.top, 3.5).padding(.trailing, 10.0)
                        .contentTransition(.numericText(countsDown: true))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 5.0) {
                        Text(context.state.tab.headsign).font(.headline).lineLimit(1).padding(.top, -20.0)
                        VirtualTableConnectionDetail(context.state.tab, context.state.vehicleInfo).padding(.all, 3.0)
                    }
                }
            } compactLeading: {
                LineText(context.state.tab.line, 16.0).padding(.leading, 7.5)
            } compactTrailing: {
                Text(context.state.tab.departureTimeRemaining).font(.headline)
                    .padding(.trailing, 7.5)
                    .contentTransition(.numericText(countsDown: true))
            } minimal: {
                Text(context.state.tab.departureTimeRemainingShortened)
                    .font(.system(size: 16.0))
                    .contentTransition(.numericText(countsDown: true))
            }
            .widgetURL(URL(string: "transi://table/\(context.state.tab.stopId)/\(context.state.tab.id)"))
        }
        .supplementalActivityFamiliesIfAvailable()
//        .supplementalActivityFamilies([.small, .medium])
    }
}

extension ActivityConfiguration {
    func supplementalActivityFamiliesIfAvailable() -> some WidgetConfiguration {
        if #available(iOS 18.0, *) {
            return self.supplementalActivityFamilies([ActivityFamily.small, ActivityFamily.medium])
        } else {
            return self
        }
    }
}

private extension VirtualTableActivityAttributes {
    static var preview: VirtualTableActivityAttributes {
        VirtualTableActivityAttributes()
    }
}

private extension VirtualTableActivityAttributes.ContentState {
    static var online: VirtualTableActivityAttributes.ContentState {
        VirtualTableActivityAttributes.ContentState(tab: Tab.example, vehicleInfo: VehicleInfo.example)
    }

    static var offline: VirtualTableActivityAttributes.ContentState {
        VirtualTableActivityAttributes.ContentState(tab: Tab.example)
    }
}

//#Preview("Content", as: .content, using: VirtualTableActivityAttributes.preview) {
//    VirtualTableActivityLiveActivity()
//} contentStates: {
//    VirtualTableActivityAttributes.ContentState.online
//    VirtualTableActivityAttributes.ContentState.offline
//}
