//
//  VirtualTableList.swift
//  Transi
//
//  Created by magic_sk on 31/01/2023.
//

import SwiftUI
import SwipeActions

struct VirtualTableList: View {
    @Environment(\.openURL) var openURL
    @StateObject var virtualTableController = GlobalController.virtualTable

    private var vehicleInfoByIssi: [String: VehicleInfo] {
        Dictionary(uniqueKeysWithValues: virtualTableController.vehicleInfo.map { ($0.issi, $0) })
    }

    var body: some View {
        ZStack {
            if !virtualTableController.connections.isEmpty {
                ScrollView {
                    HStack(alignment: .center) {
                        Text(virtualTableController.currentStop.name ?? "Loading...")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Spacer()
                        Button {
                            openURL(URL(string: "transi://map/\(virtualTableController.currentStop.id)")!)
                        } label: {
                            Image(systemName: "map")
                                .font(.title2)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    LazyVStack(spacing: .zero) {
                        SwipeViewGroup {
                            ForEach(virtualTableController.connections) { connection in
                                let vehicleInfo = vehicleInfoByIssi[connection.busID]
                                let isLast = virtualTableController.connections.last?.id == connection.id
                                VirtualTableListItem(
                                    connection,
                                    virtualTableController.currentStop.platformLabels,
                                    vehicleInfo,
                                    isLast: isLast
                                ).id(connection.id)
                            }
                        }
                    }
                    .animation(.default, value: virtualTableController.connections.map(\.id))
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
            } else if virtualTableController.socketStatus != .connected {
                VStack {
                    Spacer()
                    LoadingIndicator()
                    Spacer()
                }
            } else if virtualTableController.connectionsEmpty {
                VStack {
                    Spacer()
                    NoDeparturesIcon()
                    Text("There are no departures at this time.").foregroundColor(.secondaryLabel)
                    Spacer()
                }
            }
        }
        .animation(.easeInOut, value: virtualTableController.connections.isEmpty)
    }
}
