//
//  VirtualTableListItem.swift
//  Transi
//
//  Created by magic_sk on 09/04/2023.
//

import MarqueeText
import SwiftUI
import SwipeActions

struct VirtualTableListItem: View {
    @Environment(\.openURL) private var openURL

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
        SwipeView {
            VStack(spacing: 0) {
                DisclosureGroup(isExpanded: $expanded) {
                    VirtualTableConnectionDetail(connection, vehicleInfo, true)
                        .padding(.horizontal, 14.0)
                        .padding(.vertical, 10.0)
                } label: {
                    HStack {
                        VStack {
                            LineText(connection.line, 20.0)
                        }
                        .width(50.0)
                        .padding(.leading, 14.0)
                        VStack {
                            HStack {
                                VStack(alignment: .leading, spacing: .zero) {
                                    MarqueeText(
                                        text: connection.headsign,
                                        font: UIFont.systemFont(ofSize: 16.0, weight: .medium),
                                        leftFade: 16,
                                        rightFade: 16,
                                        startDelay: 1
                                    )
                                    if connection.lastStopName != "none" && !expanded {
                                        HStack(spacing: 4.0) {
                                            StopIcon()
                                            Text(connection.lastStopName)
                                                .font(.system(size: 10.0, weight: .light))
                                                .foregroundColor(.systemGray)
                                        }.padding(.leading, 1.5)
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
                                }.padding(.trailing, 15.0).buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    .padding(.top, 12.0)
                    .padding(.bottom, 10.7)
                    .foregroundColor(.label)
                }
                .disclosureGroupStyle(HideArrowDisclosureGroupStyle())
                .padding(.trailing, 0.0)
                .onAppear {
                    expanded = expanded ? true : connection.expanded
                }
                .padding(.bottom, -1.5)
                Divider().padding(.leading, expanded ? 0.0 : 65.0).opacity(
                    isLast ? 0.0 : 1.0)
            }
        } leadingActions: { context in
            SwipeAction(systemImage: "bell.fill") {
                DispatchQueue.main.asyncAfter(deadline: .now()) {
                    context.state.wrappedValue = .closed
                    try! VirtualTableLiveActivityController.startActivity(connection, vehicleInfo)
                }
            }
            .allowSwipeToTrigger()
            .background(.systemBlue)
            .foregroundStyle(.white)
        } trailingActions: { context in
            SwipeAction(systemImage: "square.and.arrow.up") {
                let url = URL(string: "transi://table/\(connection.stopId)/\(connection.id)")
                let av = UIActivityViewController(activityItems: [url!], applicationActivities: nil)
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    windowScene.windows.first?.rootViewController?.present(
                        av, animated: true, completion: nil)
                }
                context.state.wrappedValue = .closed
            }
            .allowSwipeToTrigger()
            .background(.systemYellow)
            .foregroundStyle(.white)
            SwipeAction(systemImage: "calendar") {
                openURL(URL(string: "transi://timetable/\(connection.line)")!)
                context.state.wrappedValue = .closed
            }
            .background(.systemGreen)
            .foregroundStyle(.white)
            SwipeAction(systemImage: "map.fill") {
                if let stopId = GlobalController.stopsListProvider.getStopIdFromName(
                    connection.lastStopName)
                {
                    openURL(URL(string: "transi://map/\(stopId)")!)
                }
                context.state.wrappedValue = .closed
            }
            .background(.systemRed)
            .foregroundStyle(.white)
        }
        .swipeActionCornerRadius(.zero)
        .swipeActionsMaskCornerRadius(.zero)
        .swipeSpacing(.zero)
        .swipeActionsStyle(.cascade)
        .swipeMinimumDistance(25.0)
        .swipeActionWidth(60.0)
        .swipeActionsVisibleEndPoint(60.0)
        .onChange(of: expanded) { expanded in
            if expanded == true {
                GlobalController.virtualTable.lastExpandedConnection = connection
            }
        }
        //        .overlay {
        //            if false { // TODO: option in settings
        //                NavigationLink(destination: VirtualTableDetail(tab, platformLabels, vehicleInfo),
        //                               label: { EmptyView() })
        //                    .opacity(0)
        //            }
        //        }
    }
}

#Preview {
    NavigationStack {
        ZStack {
            Color.systemGroupedBackground.edgesIgnoringSafeArea(.all)
            ScrollView {
                LazyVStack(spacing: .zero) {
                    SwipeViewGroup {
                        ForEach([Connection.example2, Connection.example, Connection.example3]) {
                            connection in
                            VirtualTableListItem(
                                connection, [PlatformLabel.example], VehicleInfo.example, isLast: false)
                        }
                    }
                }
                .background(.secondarySystemGroupedBackground)
                .cornerRadius(26.0)
                .padding(.horizontal, 15.9)
                Spacer().padding(.bottom, 60.0)
            }
        }
        .navigationTitle(Text("Loading..."))
    }
}
