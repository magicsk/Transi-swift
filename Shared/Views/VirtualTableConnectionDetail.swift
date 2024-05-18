//
//  VirtualTableConnectionDetail.swift
//  Transi
//
//  Created by magic_sk on 01/03/2024.
//

import SwiftUI

struct VirtualTableConnectionDetail: View {
    var tab: Tab
    var vehicleInfo: VehicleInfo?
    var virtualTable: Bool

    init(_ tab: Tab, _ vehicleInfo: VehicleInfo?, _ virtualTable: Bool = false) {
        self.tab = tab
        self.vehicleInfo = vehicleInfo
        self.virtualTable = virtualTable
    }

    var body: some View {
        let busID = String(tab.busID.dropFirst(2))
        VStack {
            HStack(alignment: .bottom) {
                if tab.type == "online" && vehicleInfo != nil {
                    Image("\(vehicleInfo!.imgt)-\(String(vehicleInfo!.img).leftPadding(toLength: 4, withPad: "0"))")
                        .resizable()
                        .scaledToFit()
                        .maxHeight(virtualTable ? 40.0 : 55.0)
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text("Expected departure: \(tab.departureTime)")
                        .lineLimit(1)
                        .frame(minWidth: 180.0, alignment: .trailing)
                    if tab.type == "online" {
                        HStack {
                            StopIcon(.accent).scaleEffect(1.3)
                            Text(tab.lastStopName)
                        }
                    }
                }
                .padding(.bottom, 3.0)
            }
            .font(.system(size: virtualTable ? 12.0 : 14.0))
            HStack {
                if tab.type == "online" {
                    if let vehicleInfo = vehicleInfo {
                        HStack(spacing: 2.0) {
                            Text("\(vehicleInfo.type) #\(busID)")
                                .font(.system(size: 12.0, weight: .thin))
                                .lineLimit(1)
                            Image(systemName: vehicleInfo.ac ? "snowflake" : "snowflake.slash")
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(vehicleInfo.ac ? Color.accent : Color.red, Color.gray)
                                .font(.system(size: 12.0))
                        }
                    }
                }
                Spacer()
                HStack(alignment: .center, spacing: 5.0) {
                    Image(systemName: "circle.fill")
                        .foregroundColor(getDelayColor(tab.delay, tab.type))
                        .font(.system(size: 12.0))
                    Text(tab.delayText).font(.system(size: virtualTable ? 12.0 : 14.0))
                }
            }
        }
    }
}

#Preview {
    VStack {
        VirtualTableConnectionDetail(Tab.example, VehicleInfo.example, true)
        Divider()
        VirtualTableConnectionDetail(Tab.example2, VehicleInfo.example2, false)
        Divider()
        VirtualTableConnectionDetail(Tab.example3, VehicleInfo.example, true)
    }
}
