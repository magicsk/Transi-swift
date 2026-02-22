//
//  VirtualTableList.swift
//  Transi
//
//  Created by magic_sk on 31/01/2023.
//

import SocketIO
import SwiftUI
import SwipeActions

struct VirtualTableList: View {
    @StateObject var virtualTableController = GlobalController.virtualTable

    private var vehicleInfoByIssi: [String: VehicleInfo] {
        Dictionary(uniqueKeysWithValues: virtualTableController.vehicleInfo.map { ($0.issi, $0) })
    }

    var body: some View {
        ZStack {
            if !virtualTableController.connections.isEmpty {
                ScrollView {
                    ConnectionStatusBar(status: virtualTableController.socketStatus)
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
        .background(Color.systemGroupedBackground.ignoresSafeArea())
        .animation(.easeInOut, value: virtualTableController.connections.isEmpty)
    }
}

private struct ConnectionStatusBar: View {
    let status: SocketIOStatus
    @State private var animating = false
    @State private var showText: Bool
    @State private var showLine: Bool

    init(status: SocketIOStatus) {
        self.status = status
        let visible = status != .connected
        _showText = State(initialValue: visible)
        _showLine = State(initialValue: visible)
    }

    var body: some View {
        Group {
            if showLine {
                VStack(spacing: 0) {
                    if showText {
                        Text(status.description)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.bottom, 4)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Color.gray.opacity(0.2))
                            if status == .connecting {
                                Capsule()
                                    .fill(Color.gray.opacity(0.6))
                                    .frame(width: geo.size.width * 0.3)
                                    .offset(x: animating ? geo.size.width * 0.7 : 0)
                            } else if status != .connected {
                                Rectangle().fill(Color.red.opacity(0.5))
                            }
                        }
                        .clipShape(Capsule())
                    }
                    .frame(height: 2)
                }
                .padding(.bottom, 8)
                .transition(.opacity)
            }
        }
        .onChange(of: status) { newStatus in
            if newStatus == .connected {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showText = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showLine = false
                    }
                }
            } else {
                withAnimation {
                    showLine = true
                    showText = true
                }
                if newStatus == .connecting {
                    animating = false
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        animating = true
                    }
                } else {
                    withAnimation(.default) { animating = false }
                }
            }
        }
        .onAppear {
            if status == .connecting {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    animating = true
                }
            }
        }
    }
}
