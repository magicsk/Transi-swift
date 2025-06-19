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
                        Text(virtualTableController.currentStop.name ?? "Loading...").font(.system(size: 32.0, weight: .bold))
                        Spacer()
                        Button(action: {
                            changeTab(1)
                            dismiss()
                            GlobalController.tripPlanner.fetchTripToActualStop()
                        }) {
                            Image(systemName: "arrow.triangle.turn.up.right.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(Color.secondaryLabel, Color.tertiarySystemBackground)
                                .cornerRadius(1000)
                        }
                        Button(action: {
                            dismiss()
                        }) {
                            Image(systemName: "xmark").fontWeight(.bold)
                                .padding(7.5)
                                .foregroundColor(.secondaryLabel)
                                .background(.tertiarySystemBackground)
                                .cornerRadius(1000)
                        }
                    }
                    .padding(.top, 14.0)
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
