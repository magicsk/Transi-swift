//
//  VirtualTableView.swift
//  Transi
//
//  Created by magic_sk on 08/05/2023.
//

import SwiftUI

struct VirtualTableView: View {
    @StateObject var virtualTableController = GlobalController.virtualTable
    @State private var showStopList = false
    @State private var stop: Stop = .empty
    @AppStorage(Stored.displaySocketStatus) var displaySocketStatus = false
    @AppStorage(Stored.displayClockOnTable) var displayClock = true

    var body: some View {
        NavigationStack {
            ZStack {
                Color.systemGroupedBackground.edgesIgnoringSafeArea(.all)
                VirtualTableList()
            }
            .navigationTitle(Text(virtualTableController.currentStop.name ?? "Loading..."))
            .toolbar {
                if displaySocketStatus {
                    ToolbarItem(placement: .topBarLeading) {
                        Text(virtualTableController.socketStatus.description)
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 5.0)
                            .onTapGesture {
                                virtualTableController.disconnect(reconnect: true)
                            }
                    }
                }
                if displayClock {
                    ToolbarItem(placement: .topBarTrailing) {
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
            }
        }
    }
}

// struct VirtualTableView_Previews: PreviewProvider {
//    static var previews: some View {
//        VirtualTableView()
//    }
// }
