//
//  VirtualTableListItem.swift
//  Transi
//
//  Created by magic_sk on 09/04/2023.
//

import SwiftUI
import SwipeActions

struct VirtualTableListItem: View {
    @Environment(\.openURL) private var openURL
    
    var tab: Tab
    var platformLabels: [PlatformLabel]?
    var vehicleInfo: VehicleInfo?
    @State var date = Date()
    @State var image: CGImage? = nil
    @State var loadedImage: UIImage? = nil
    @State var first: Bool = false
    @State var expanded: Bool = false

    init(_ tab: Tab, _ platformLabels: [PlatformLabel]?, _ vehicleInfo: VehicleInfo?, first: Bool = false) {
        self.tab = tab
        self.platformLabels = platformLabels
        self.vehicleInfo = vehicleInfo
        self.first = first
    }

    var body: some View {
        SwipeView {
            VStack(spacing: 0) {
                DisclosureGroup(isExpanded: $expanded) {
                    VirtualTableConnectionDetail(tab, vehicleInfo, true)
                        .padding(.trailing, 20.0)
                        .padding(.horizontal, 14.0)
                        .padding(.vertical, 10.0)
                } label: {
                    HStack {
                        VStack {
                            LineText(tab.line, 20.0)
                        }
                        .width(50.0)
                        .padding(.leading, 6.0)
                        VStack {
                            HStack {
                                VStack(alignment: .leading, spacing: .zero) {
                                    Text(tab.headsign).font(.system(size: 16.0, weight: .medium)).lineLimit(1)
                                    if tab.lastStopName != "none" && !expanded {
                                        HStack(spacing: 4.0) {
                                            StopIcon()
                                            Text(tab.lastStopName)
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
                                    if tab.stuck {
                                        Image("exclamationmark.triangle.fill").foregroundColor(.yellow)
                                    }
                                    RemainingTime(tab.departureTimeRemaining)
                                    Text(getPlatformLabel(platformLabels, tab.platform)).font(.system(size: 16.0, weight: .light)).width(22.0)
                                }.padding(.trailing, 10.0)
                            }
                        }
                    }
                    .padding(.top, 7.5)
                    .padding(.bottom, 2.5)
                    .foregroundColor(.label)
                }
                .accentColor(.clear)
                .padding(.trailing, -20.0)
                .onAppear {
                    expanded = expanded ? true : tab.expanded
                }
                .padding(.bottom, -1.5)
                Divider().padding(.leading, expanded ? 0.0 : 65.0)
            }
        } leadingActions: { context in
            SwipeAction(systemImage: "bell.fill") {
                DispatchQueue.main.asyncAfter(deadline: .now()) {
                    context.state.wrappedValue = .closed
                    let aid = try! VirtualTableLiveActivityController.startActivity(tab, vehicleInfo)
                    print(aid)
                }
            }
            .allowSwipeToTrigger()
            .background(.systemBlue)
            .foregroundStyle(.white)
        }
    trailingActions: { context in
            SwipeAction(systemImage: "square.and.arrow.up") {
                let url = URL(string: "transi://table/\(tab.stopId)/\(tab.id)")
                let av = UIActivityViewController(activityItems: [url!], applicationActivities: nil)
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    windowScene.windows.first?.rootViewController?.present(av, animated: true, completion: nil)
                }
                context.state.wrappedValue = .closed
            }
            .allowSwipeToTrigger()
            .background(.systemYellow)
            .foregroundStyle(.white)
            SwipeAction(systemImage: "calendar") {
                openURL(URL(string: "transi://timetable/\(tab.line)")!)
                context.state.wrappedValue = .closed
            }
            .background(.systemGreen)
            .foregroundStyle(.white)
            SwipeAction(systemImage: "map.fill") {
                if let stopId = GlobalController.stopsListProvider.getStopIdFromName(tab.lastStopName) {
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
        .onChange(of: expanded) { _ in
            if expanded == true {
                GlobalController.virtualTable.lastExpandedTab = tab
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
    ZStack {
        Color.systemGroupedBackground.edgesIgnoringSafeArea(.all)
        VStack {
            LazyVStack {
                Spacer()
                ForEach([Tab.example, Tab.example2, Tab.example3]) { tab in
                    VirtualTableListItem(tab, [PlatformLabel.example], VehicleInfo.example)
                }
            }
            .background(.secondarySystemGroupedBackground)
            .cornerRadius(12.0)
            Spacer()
        }.padding(.horizontal, 12.0)
    }
}
