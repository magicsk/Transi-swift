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
    @Environment(\.self) var environment
    @Environment(\.isLuminanceReduced) var isLuminanceReduced

    var context: ActivityViewContext<VirtualTableActivityAttributes>

    var body: some View {
        VStack {
            if #available(iOS 18.0, *) {
                VirtualTableActivityLiveDynamicView(context: context)
            } else {
                VirtualTableActivityLiveViewLarge(context: context)
            }
        }
        .widgetURL(URL(string: "transi://table/\(context.state.tab.stopId)/\(context.state.tab.id)"))
        .activityBackgroundTint(Color(uiColor: UIColor.systemBackground).opacity(0.43))
    }
}
