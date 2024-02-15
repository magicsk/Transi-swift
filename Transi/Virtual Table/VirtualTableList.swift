//
//  VirtualTableList.swift
//  Transi
//
//  Created by magic_sk on 31/01/2023.
//

import SwiftUI

struct VirtualTableList: View {
    let tabs: [Tab]
    let currentStop: Stop
    let vehicleInfo: [VehicleInfo]
    
    init(_ tabs: [Tab], _ currentStop: Stop, _ vehicleInfo: [VehicleInfo]) {
        self.tabs = tabs
        self.currentStop = currentStop
        self.vehicleInfo = vehicleInfo
    }
    
    var body: some View {
        List(tabs) { tab in
            let vehicleInfo = vehicleInfo.first(where: { $0.issi == tab.busID })
            VirtualTableListItem(tab, currentStop.platformLabels, vehicleInfo )
            if (tab.id == tabs.last?.id) {
                Section{} header: {
                    Spacer()
                }
            }
        }
    }
}
