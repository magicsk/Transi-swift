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

    var body: some View {
        ZStack {
            if virtualTableController.socketStatus != .connected {
                VStack {
                    Spacer()
                    LoadingIndicator()
                    Spacer()
                }
            } else {
                if virtualTableController.connectionsEmpty {
                    VStack {
                        Spacer()
                        NoDeparturesIcon()
                        Text("There are no departures at this time.").foregroundColor(.secondaryLabel)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: .zero) {
                            SwipeViewGroup {
                                ForEach(virtualTableController.connections) { connection in
                                    let vehicleInfo = virtualTableController.vehicleInfo.first(where: {
                                        $0.issi == connection.busID
                                    })
                                    VirtualTableListItem(
                                        connection,
                                        virtualTableController.currentStop.platformLabels,
                                        vehicleInfo
                                    ).id(connection.id)
                                }
                            }
                        }
                        .animation(.default, value: virtualTableController.connections)
                        .background(.secondarySystemGroupedBackground)
                        .cornerRadius(26.0)
                        .padding(.horizontal, 15.9)
                        Spacer().padding(.bottom, 60.0)
                    }
                    .refreshable {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            virtualTableController.disconnect(reconnect: true)
                        }
                    }
                }
            }
        }
        .animation(.easeInOut, value: virtualTableController.connections.isEmpty)
    }
}
