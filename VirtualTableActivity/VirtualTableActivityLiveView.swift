//
//  VirtualTableActivityLiveView.swift
//  VirtualTableActivityExtension
//
//  Created by magic_sk on 13/06/2024.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct VirtualTableActivityLiveView: View {
    @Environment(\.colorScheme) var colorScheme

    var context: ActivityViewContext<VirtualTableActivityAttributes>

    var body: some View {
        let liveActivity = VStack {
            if #available(iOS 18.0, *) {
                VirtualTableActivityLiveDynamicView(context: context)
            } else {
                VirtualTableActivityLiveViewLarge(context: context)
            }
        }
        .widgetURL(URL(string: "transi://table/\(context.state.connection.stopId)/\(context.state.connection.id)"))
        if #available(iOS 26.0, *) {
            liveActivity.activityBackgroundTint(Color.clear)
        } else {
            liveActivity.activityBackgroundTint(colorScheme == .dark ? Color.black.opacity(0.43) : Color.systemBackground.opacity(0.43))
        }
    }
}
