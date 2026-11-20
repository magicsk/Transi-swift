//
//  MapBottomSheetView.swift
//  Transi
//
//  Created by magic_sk on 26/11/2023.
//

import SwiftUI

struct MapBottomSheetView: View {
    @StateObject var virtualTableController = GlobalController.virtualTable

    private let dismiss: () -> Void
    private let changeTab: (Int) -> Void

    init(_ dismiss: @escaping () -> Void, _ changeTab: @escaping (Int) -> Void) {
        self.dismiss = dismiss
        self.changeTab = changeTab
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.systemGroupedBackground.edgesIgnoringSafeArea(.all)
                VStack(alignment: .center, spacing: .zero) {
                    HStack(alignment: .center) {
                        Text(virtualTableController.currentStop.name ?? "Loading...").font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                        Spacer()
                        // The trailing padding takes back the margin the 44 pt target adds around the close glyph, so it
                        // lines up with the list as before; no spacing, so the two targets don't overlap.
                        HStack(spacing: 0.0) {
                            // The trip planner can't route to railway stations outside IDS BK.
                            if virtualTableController.currentStop.stationId != nil {
                                Button(action: {
                                    changeTab(0)
                                    dismiss()
                                    GlobalController.tripPlanner.fetchTripToActualStop()
                                }) {
                                    Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                        .font(.system(size: 32))
                                        .foregroundStyle(Color.secondaryLabel, Color.tertiarySystemBackground)
                                        .cornerRadius(1000)
                                        .frame(minWidth: 44.0, minHeight: 44.0)
                                        .contentShape(Rectangle())
                                }
                                .accessibilityLabel("Plan trip to this stop")
                            }
                            Button(action: {
                                dismiss()
                            }) {
                                Image(systemName: "xmark").fontWeight(.bold)
                                    .padding(7.5)
                                    .foregroundColor(.secondaryLabel)
                                    .background(.tertiarySystemBackground)
                                    .cornerRadius(1000)
                                    .frame(minWidth: 44.0, minHeight: 44.0)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Close")
                        }
                        .padding(.trailing, -6.0)
                    }
                    .padding(.top, 24.0)
                    .padding(.horizontal, 20.0)
                    Spacer()
                    VirtualTableList()
                }
                .navigationBarHidden(true)
                .navigationTitle(Text(virtualTableController.currentStop.name ?? "Loading..."))
            }
        }
    }
}

// #Preview {
//    MapBottomSheetView()
// }
