//
//  VirtualTableList.swift
//  Transi
//
//  Created by magic_sk on 31/01/2023.
//

import SwiftUI
import SwipeActions

struct VirtualTableList: View {
    @StateObject var virtualTableController = GlobalController.virtualTable
    @State var displayNoDeparture = false

    var body: some View {
        ZStack {
            if virtualTableController.tabs.isEmpty {
                if displayNoDeparture {
                    VStack {
                        Spacer()
                        NoDeparturesIcon()
                        Text("There are no departures at this time.").foregroundColor(.secondaryLabel)
                        Spacer()
                    }
                    .visible(displayNoDeparture)
                    .animation(.easeInOut(duration: 0.25), value: displayNoDeparture)
                } else {
                    VStack {
                        Spacer()
                        LoadingIndicator()
                        Spacer()
                        ForEach(virtualTableController.tabs) { tab in
                            let vehicleInfo = virtualTableController.vehicleInfo.first(where: { $0.issi == tab.busID })
                            VirtualTableListItem(tab, virtualTableController.currentStop.platformLabels, vehicleInfo).id(tab.id)
                        }
                    }
                    .animation(.default, value: virtualTableController.tabs)
                    .background(.secondarySystemGroupedBackground)
                    .cornerRadius(12.0)
                    Spacer().padding(.bottom, 60.0)
                }
                .refreshable {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        virtualTableController.disconnect(reconnect: true)
                    }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: .zero) {
                        SwipeViewGroup {
                            ForEach(virtualTableController.tabs) { tab in
                                let vehicleInfo = virtualTableController.vehicleInfo.first(where: { $0.issi == tab.busID })
                                VirtualTableListItem(
                                    tab,
                                    virtualTableController.currentStop.platformLabels,
                                    vehicleInfo
                                ).id(tab.id)
                            }
                        }
                    }
                    .animation(.default, value: virtualTableController.tabs)
                    .background(.secondarySystemGroupedBackground)
                    .cornerRadius(12.0)
                    .padding(.horizontal, 16.0)
                    Spacer().padding(.bottom, 60.0)
                }
                .refreshable {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        virtualTableController.disconnect(reconnect: true)
                    }
                }
            }
        }
        .animation(.easeInOut, value: virtualTableController.tabs.isEmpty)
        .onChange(of: [virtualTableController.socketStatus, String(virtualTableController.tabs.count)]) { _ in
            if virtualTableController.tabs.isEmpty && virtualTableController.socketStatus == "connected" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if virtualTableController.tabs.isEmpty && virtualTableController.socketStatus == "connected" {
                        displayNoDeparture = true
                    }
                }
            } else {
                displayNoDeparture = false
            }
        }
    }
}
