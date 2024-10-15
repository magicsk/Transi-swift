//
//  VirtualTableActivityLiveViewSmall.swift
//  Transi
//
//  Created by magic_sk on 13/06/2024.
//

import SwiftUI
import WidgetKit

struct VirtualTableActivityLiveViewSmall: View {
    var context: ActivityViewContext<VirtualTableActivityAttributes>

    var body: some View {
        let tab = context.state.tab
        VStack(spacing: 2.5) {
            HStack {
                LineText(tab.line, 18.0).padding(-2.0)
                Text(tab.headsign).font(.system(size: 14.0, weight: .semibold)).lineLimit(1)
                Spacer()
            }.padding(.bottom, 1.5)
            HStack {
                if tab.type == "online" {
                    HStack {
                        StopIcon(.accent)
                        Text(tab.lastStopName).font(.system(size: 12.0)).lineLimit(1)
                    }
                } else {
                    Text(tab.departureTime).font(.system(size: 12.0)).lineLimit(1)
                }
                Spacer()
                Text(tab.departureTimeRemaining)
                    .contentTransition(.numericText(countsDown: true))
                    .font(.system(size: 14.0, weight: .bold))
            }
            HStack(alignment: .bottom) {
                if tab.type == "online" {
                    if let vehicleInfo = context.state.vehicleInfo {
                        HStack(spacing: 2.0) {
                            Text("\(vehicleInfo.type)")
                                .font(.system(size: 6.0, weight: .thin))
                                .lineLimit(1)
                            Image(systemName: vehicleInfo.ac ? "snowflake" : "snowflake.slash")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(vehicleInfo.ac ? Color.accent : Color.red, Color.gray)
                                .font(.system(size: 6.5))
                        }
                    }
                }
                Spacer()
                HStack(alignment: .center, spacing: 5.0) {
                    Image(systemName: "circle.fill")
                        .foregroundColor(getDelayColor(tab.delay, tab.type))
                        .font(.system(size: 12.0))
                    Text(tab.delayText).font(.system(size: 12.0)).lineLimit(1).fixedSize(horizontal: true, vertical: false)
                }
            }
        }.padding(10.0)
    }
}
