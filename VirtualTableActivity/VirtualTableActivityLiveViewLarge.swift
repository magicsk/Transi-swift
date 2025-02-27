//
//  VirtualTableActivityLiveViewSmall.swift
//  Transi
//
//  Created by magic_sk on 13/06/2024.
//

import SwiftUI
import WidgetKit

struct VirtualTableActivityLiveViewLarge: View {
    var context: ActivityViewContext<VirtualTableActivityAttributes>

    var body: some View {
        VStack {
            HStack {
                LineText(context.state.tab.line, 20.0)
                Text(context.state.tab.headsign).font(.headline).lineLimit(1)
                Spacer()
                Text(context.state.tab.departureTimeRemaining)
                    .contentTransition(.numericText(countsDown: true))
                    .font(.headline)
            }
            VirtualTableConnectionDetail(context.state.tab, context.state.vehicleInfo)
        }
        .padding(.all, 15.0)
    }
}
