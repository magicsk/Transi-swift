//
//  VirtualTableListItem.swift
//  Transi
//
//  Created by magic_sk on 09/04/2023.
//

import MarqueeText
import SwiftUI

struct VirtualTableListItem: View {
    var connection: Connection
    var platformLabels: [PlatformLabel]?
    var vehicleInfo: VehicleInfo?
    var isLast: Bool
    @State var date = Date()
    @State var expanded: Bool = false

    init(_ connection: Connection, _ platformLabels: [PlatformLabel]?, _ vehicleInfo: VehicleInfo?, isLast: Bool)
    {
        self.connection = connection
        self.platformLabels = platformLabels
        self.vehicleInfo = vehicleInfo
        self.isLast = isLast
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack {
                    LineText(connection.line, 20.0)
                }
                .width(50.0)
                VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: .zero) {
                            MarqueeText(
                                text: connection.headsign,
                                font: UIFont.systemFont(ofSize: 16.0, weight: .medium),
                                leftFade: 0,
                                rightFade: 0,
                                startDelay: 1
                            )
                            if connection.lastStopName != "none" && !expanded {
                                HStack(spacing: 4.0) {
                                    StopIcon()
                                    Text(connection.lastStopName)
                                        .font(.system(size: 10.0, weight: .light))
                                        .foregroundColor(.systemGray)
                                }
                                .padding(.leading, 1.5)
                            }
                        }
                        Spacer()
                        VStack {
                            Spacer()
                        }
                        HStack(spacing: 6.0) {
                            if connection.stuck {
                                Image("exclamationmark.triangle.fill").foregroundColor(
                                    .yellow)
                            }
                            RemainingTime(connection.departureTimeRemaining)
                            Text(getPlatformLabel(platformLabels, connection.platform))
                                .font(.system(size: 16.0, weight: .light)).width(22.0)
                        }
                    }
                }
            }
            .foregroundColor(.label)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation {
                    expanded.toggle()
                }
            }
        }
        .onAppear {
            expanded = expanded ? true : connection.expanded
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                try! VirtualTableLiveActivityController.startActivity(connection, vehicleInfo)
            } label: {
                Label("Notify", systemImage: "bell.fill")
            }
            .tint(.blue)
            .labelStyle(.iconOnly)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                let url = URL(string: "transi://table/\(connection.stopId)/\(connection.id)")
                let av = UIActivityViewController(activityItems: [url!], applicationActivities: nil)
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    windowScene.windows.first?.rootViewController?.present(
                        av, animated: true, completion: nil)
                }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .tint(.yellow)
            .labelStyle(.iconOnly)
            Button {
                if let stopId = GlobalController.stopsListProvider.getStopIdFromName(
                    connection.lastStopName)
                {
                    GlobalController.appState.pendingNavigation = .map(stopId: stopId)
                }
            } label: {
                Label("Map", systemImage: "map.fill")
            }
            .tint(.red)
            .labelStyle(.iconOnly)
            Button {
                GlobalController.appState.pendingNavigation = .timetable(line: connection.line)
            } label: {
                Label("Timetable", systemImage: "calendar")
            }
            .tint(.green)
            .labelStyle(.iconOnly)
        }
        .alignmentGuide(.listRowSeparatorLeading) { _ in
            55
        }
        .listRowSeparator(expanded ? .hidden : .automatic, edges: .bottom)
        .onChange(of: expanded) { expanded in
            if expanded == true {
                GlobalController.virtualTable.lastExpandedConnection = connection
            }
        }
        if expanded {
            VirtualTableConnectionDetail(connection, vehicleInfo, true)
        }
    }
}

@available(iOS 17.0, *)
#Preview {
    NavigationStack {
        List([Connection.example2, Connection.example, Connection.example3], id: \.self) {
            connection in
            VirtualTableListItem(
                connection, [PlatformLabel.example], VehicleInfo.example, isLast: false)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text("Preview"))
    }
}
