//
//  VirtualTableList.swift
//  Transi
//
//  Created by magic_sk on 31/01/2023.
//

import SwiftUI

struct VirtualTableList: View {
    @StateObject var virtualTableController = GlobalController.virtualTable
    @State var displayNoDeparture = false

    var body: some View {
        ZStack {
            if displayNoDeparture {
                VStack {
                    NoDeparturesIcon()
                    Text("There are no departures at this time.").foregroundColor(.secondaryLabel)
                }
                .visible(displayNoDeparture)
                .animation(.easeInOut(duration: 0.25), value: displayNoDeparture)
            } else {
                LoadingIndicator()
            }
            List(virtualTableController.tabs) { tab in
                let vehicleInfo = virtualTableController.vehicleInfo.first(where: { $0.issi == tab.busID })
                VirtualTableListItem(tab, virtualTableController.currentStop.platformLabels, vehicleInfo)
                if tab.id == virtualTableController.tabs.last?.id {
                    Section {} header: {
                        Spacer()
                    }
                }
            }
        }.onChange(of: [virtualTableController.socketStatus, virtualTableController.tabs.isEmpty.description]) { _ in
            print(virtualTableController.socketStatus)
            if virtualTableController.tabs.isEmpty && virtualTableController.socketStatus == "connected" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    displayNoDeparture = true
                }
            } else {
                displayNoDeparture = false
            }
        }
    }
    
}
