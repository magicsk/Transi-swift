//
//  VirtualTableView.swift
//  Transi
//
//  Created by magic_sk on 08/05/2023.
//

import SwiftUI

struct VirtualTableView: View {
    @StateObject var virtualTableController = GlobalController.virtualTable
    @State private var showInfoTexts = false
    @AppStorage(Stored.displayClockOnTable) var displayClock = true
    @Namespace private var namespace

    var body: some View {
        NavigationStack {
            ZStack {
                Color.systemGroupedBackground.edgesIgnoringSafeArea(.all)
                VirtualTableList()
            }
            .navigationTitle(virtualTableController.currentStop.name ?? "Loading...")
            .toolbar {
                if displayClock {
                    ToolbarItem(placement: .topBarLeading) {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(clockStringFromDate(context.date))
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 5.0)
                        .onTapGesture {
                            virtualTableController.disconnect(reconnect: true)
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    HStack {
                        let infoTextButton = Button {
                            virtualTableController.markInfoTextsRead()
                            showInfoTexts = true
                        } label: {
                            // Filled while there is news, so it doesn't rely on colour alone.
                            let unread = virtualTableController.unreadInfoCount > 0
                            Image(systemName: unread ? "exclamationmark.triangle.fill" : "exclamationmark.triangle")
                                .foregroundColor(unread ? .orange : .gray)
                        }
                        .padding(.horizontal, 5.0)
                        .accessibilityLabel("Service information")
                        .accessibilityValue(
                            virtualTableController.unreadInfoCount > 0 ? "\(virtualTableController.unreadInfoCount) unread" : ""
                        )
                        if #available(iOS 18.0, *) {
                            infoTextButton
                                .matchedTransitionSource(id: "infoTexts", in: namespace)
                        } else {
                            infoTextButton
                        }
                        Divider()
                            .frame(height: 16)
                        Button {
                            GlobalController.appState.pendingNavigation = .map(stopId: virtualTableController.currentStop.id)
                        } label: {
                            Image(systemName: "map")
                        }
                        .padding(.horizontal, 5.0)
                        .accessibilityLabel("Show stop on map")
                    }
                }
            }
            .sheet(isPresented: $showInfoTexts) {
                let infoTextSheet = NavigationStack {
                    Group {
                        if virtualTableController.infoTexts.isEmpty {
                            VStack {
                                Spacer()
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.largeTitle)
                                    .foregroundColor(.gray)
                                    .padding(.bottom, 8)
                                Text("There is no service information right now.")
                                    .foregroundColor(.secondaryLabel)
                                    .multilineTextAlignment(.center)
                                Spacer()
                            }
                            .padding()
                        } else {
                            List {
                                ForEach(virtualTableController.infoTexts, id: \.self) { text in
                                    Label {
                                        Text(text)
                                    } icon: {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
                        }
                    }
                    .navigationTitle("Service Info")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("Done") {
                                showInfoTexts = false
                            }
                        }
                    }
                }
                .presentationDetents([.medium, .large])
                if #available(iOS 18.0, *) {
                    infoTextSheet
                        .navigationTransition(.zoom(sourceID: "infoTexts", in: namespace))
                } else {
                    infoTextSheet
                }
            }
        }
    }
}
