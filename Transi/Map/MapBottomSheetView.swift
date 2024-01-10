//
//  MapBottomSheetView.swift
//  Transi
//
//  Created by magic_sk on 26/11/2023.
//

import SwiftUI

struct MapBottomSheetView: View {
    @ObservedObject private var dataProvider = DataProvider()

    private let dismiss: () -> Void
    private let changeTab: (Int) -> Void

    init(_ dataProvider: DataProvider, _ dismiss: @escaping () -> Void, _ changeTab: @escaping (Int) -> Void) {
        self.dataProvider = dataProvider
        self.dismiss = dismiss
        self.changeTab = changeTab
    }

    var body: some View {
        NavigationView {
            ZStack {
                Color.systemGroupedBackground.edgesIgnoringSafeArea(.all)
                VStack(alignment: .leading, spacing: .zero) {
                    HStack(alignment: .center) {
                        Text(dataProvider.currentStop.name ?? "Loading...").font(.system(size: 32.0, weight: .bold))
                        Spacer()
                        Button(action: {
                            changeTab(1)
                            dismiss()
                            if dataProvider.lastLocation != nil {
                                dataProvider.tripFrom = .actualLocation
                            }
                            dataProvider.tripTo = dataProvider.currentStop
                            dataProvider.fetchTrip()
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
                    .padding(.top, 12.0)
                    .padding(.horizontal, 20.0)
                    VirtualTableList(dataProvider)
                        .introspect(.list(style: .insetGrouped), on: .iOS(.v16, .v17)) { list in
                            list.contentInset.top = -25
                        }
                }
                .navigationBarHidden(true)
                .navigationTitle(Text(dataProvider.currentStop.name ?? "Loading..."))
            }
        }
    }
}

//#Preview {
//    MapBottomSheetView()
//}
