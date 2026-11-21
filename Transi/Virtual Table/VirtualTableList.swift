//
//  VirtualTableList.swift
//  Transi
//
//  Created by magic_sk on 31/01/2023.
//

import SocketIO
import SwiftUI

struct VirtualTableList: View {
    @StateObject var virtualTableController = GlobalController.virtualTable
    @AppStorage(Stored.displaySocketStatus) var displaySocketStatus = true
    @State private var expandedIds: Set<Connection.ID> = []

    private var vehicleInfoByIssi: [String: VehicleInfo] {
        Dictionary(uniqueKeysWithValues: virtualTableController.vehicleInfo.map { ($0.issi, $0) })
    }

    var body: some View {
        ZStack {
            if !virtualTableController.connections.isEmpty {
                List {
                    Section {
                        ForEach(virtualTableController.connections) { connection in
                            let vehicleInfo = vehicleInfoByIssi[connection.busID]
                            let isLast = virtualTableController.connections.last?.id == connection.id
                            let expanded = Binding(
                                get: { expandedIds.contains(connection.id) },
                                set: { if $0 { expandedIds.insert(connection.id) } else { expandedIds.remove(connection.id) } }
                            )
                            VirtualTableListItem(
                                connection,
                                virtualTableController.currentStop.platformLabels,
                                vehicleInfo,
                                isLast: isLast,
                                expanded: expanded
                            ).id(connection.id)
                            // A row of its own: inserting a row animates, but on iOS 27 a row growing in place jumps.
                            if expanded.wrappedValue {
                                VirtualTableConnectionDetail(connection, vehicleInfo, true)
                                    .contentShape(Rectangle())
                                    .onTapGesture { withAnimation { expanded.wrappedValue = false } }
                            }
                        }
                    } header: {
                        // In the list's content: behind the opaque list it can't be seen, and as a safe area inset
                        // its height changes make the large title blink.
                        if displaySocketStatus {
                            ConnectionStatusBar(status: virtualTableController.socketStatus)
                                .textCase(nil)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                // Reorders snap while details are open, since iOS 27 animates a departure and its details apart.
                .animation(
                    virtualTableController.connections.contains { expandedIds.contains($0.id) } ? nil : .default,
                    value: virtualTableController.connections.map(\.id)
                )
                .refreshable {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        virtualTableController.disconnect(reconnect: true)
                    }
                }
            } else if virtualTableController.socketStatus == .connected && virtualTableController.connectionsEmpty {
                VStack {
                    Spacer()
                    NoDeparturesIcon()
                    Text("There are no departures at this time.").foregroundColor(.secondaryLabel)
                    Spacer()
                }
            } else {
                // Also while connected and the departures are still loading, which used to leave the board blank.
                VStack {
                    Spacer()
                    // Offline this never ends, so say what it waits for.
                    LoadingIndicator(text: virtualTableController.socketStatus == .connected ? "Loading…" : "Connecting…")
                    Spacer()
                }
            }
        }
        .background(Color.systemGroupedBackground.ignoresSafeArea())
        .animation(.easeInOut, value: virtualTableController.connections.isEmpty)
        // Another stop starts collapsed, as it did when each row kept its own state.
        .onChange(of: virtualTableController.currentStop.id) { _ in expandedIds = [] }
    }
}

private struct ConnectionStatusBar: View {
    let status: SocketIOStatus
    @State private var animating = false
    @State private var showText: Bool
    @State private var showLine: Bool
    /// The status now, for the delayed show and hide below to check.
    @State private var latestStatus: SocketIOStatus
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(status: SocketIOStatus) {
        self.status = status
        let visible = status != .connected
        _showText = State(initialValue: visible)
        _showLine = State(initialValue: visible)
        _latestStatus = State(initialValue: status)
    }

    var body: some View {
        Group {
            if showLine {
                VStack(spacing: 0) {
                    if showText {
                        Text(status == .connected ? "Connected" : status == .connecting ? "Connecting…" : "Disconnected")
                            .font(.caption2)
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
                                    // Started here, not when the status changes: the bar shows a second later, and a
                                    // segment inserted after its animation began stays parked at the end.
                                    .onAppear {
                                        guard !reduceMotion else { return }
                                        withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                                            animating = true
                                        }
                                    }
                                    .onDisappear { animating = false }
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
            latestStatus = newStatus
            if newStatus == .connected {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showText = false
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // Dropped again meanwhile: keep the bar.
                    guard latestStatus == .connected else { return }
                    withAnimation(.easeInOut(duration: 0.3)) {
                        showLine = false
                    }
                }
            } else {
                // A quick reconnect, like a pull to refresh, shouldn't push the list down and back up.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    guard latestStatus != .connected else { return }
                    withAnimation {
                        showLine = true
                        showText = true
                    }
                }
            }
        }
    }
}
