//
//  VirtualTableActivityLiveDynamicView.swift
//  Transi
//
//  Created by magic_sk on 14/10/2024.
//

import SwiftUI
import WidgetKit

@available(iOS 18.0, *)
struct VirtualTableActivityLiveDynamicView: View {
    @Environment(\.activityFamily) var activityFamily
    
    var context: ActivityViewContext<VirtualTableActivityAttributes>
    
    var body: some View {
        VStack {
            if activityFamily == .small {
                VirtualTableActivityLiveViewSmall(context: context)
            } else {
                VirtualTableActivityLiveViewLarge(context: context)
            }
        }
    }
}
