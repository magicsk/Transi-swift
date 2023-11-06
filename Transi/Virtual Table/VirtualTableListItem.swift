//
//  VirtualTableListItem.swift
//  Transi
//
//  Created by magic_sk on 09/04/2023.
//

import SwiftUI

struct VirtualTableListItem: View {
    var tab: Tab
    var platformLabels: [PlatformLabel]?
    var vehicleInfo: VehicleInfo?

    init(_ tab: Tab, _ platformLabels: [PlatformLabel]?, _ vehicleInfo: VehicleInfo?) {
        self.tab = tab
        self.platformLabels = platformLabels
        self.vehicleInfo = vehicleInfo
    }

    var body: some View {
        Label {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(tab.headsign).font(.subheadline).lineLimit(1)
                    HStack(spacing: 4) {
                        Image("stop")
                            .resizable(resizingMode: .stretch)
                            .foregroundColor(Color(.displayP3, red: 0.611, green: 0.611, blue: 0.611))
                            .frame(width: 7.0, height: 10.0)
                        Text(tab.lastStopName).font(.custom("SF Pro", size: 10)).fontWeight(.light).foregroundColor(Color(.displayP3, red: 0.611, green: 0.611, blue: 0.611))
                    }
                }
                Spacer()
                HStack(spacing: 6.0) {
                    if (tab.stuck) {
                        Image("exclamationmark.triangle.fill").foregroundColor(.yellow)
                    }
                    Text(tab.departureTimeRemaining).font(.headline)
                    Text(getPlatformLabel(platformLabels, tab.platform)).font(.system(size: 16.0, weight: .light)).width(22.0)
                }
            }.padding(.trailing, -12.0)
        }
        icon: {
            HStack {
                LineText(tab.line, 20.0).offset(y: 6.0)
            }
            .padding(.leading, 6.0)
            .padding(.trailing, 12.0)
            .width(1000.0)
        }
        .overlay {
            NavigationLink(destination: VirtualTableDetail(tab, platformLabels, vehicleInfo),
                           label: { EmptyView() })
                .opacity(0)
        }
    }
}

struct VirtualTableListItem_Previews: PreviewProvider {
    static var previews: some View {
        VirtualTableListItem(Tab.example, [PlatformLabel.example], VehicleInfo.example)
    }
}
