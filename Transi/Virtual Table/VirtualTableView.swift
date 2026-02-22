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
                            Button {
                                virtualTableController.markInfoTextsRead()
                                showInfoTexts = true
                            } label: {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(
                                        virtualTableController.unreadInfoCount > 0 ? .orange : .gray
                                    )
                            }
                            .padding(.horizontal, 5.0)
                            Divider()
                                .frame(height: 16)
                            Button {
                                GlobalController.appState.pendingNavigation = .map(stopId: virtualTableController.currentStop.id)
                            } label: {
                                Image(systemName: "map")
                            }
                            .padding(.horizontal, 5.0)
                        }
                    }
                }
                .sheet(isPresented: $showInfoTexts) {
                    NavigationStack {
                        Group {
                            if virtualTableController.infoTexts.isEmpty {
                                VStack {
                                    Spacer()
                                    Image(systemName: "exclamationmark.triangle")
                                        .font(.largeTitle)
                                        .foregroundColor(.gray)
                                        .padding(.bottom, 8)
                                    Text("There are no service information available now.")
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
                }
        }
    }
}
