//
//  VirtualTableView.swift
//  Transi
//
//  Created by magic_sk on 08/05/2023.
//

import SwiftUI
import SwiftUIX

struct VirtualTableView: View {
    @StateObject var virtualTableController = GlobalController.virtualTable
    @StateObject var stopListProvider = GlobalController.stopsListProvider
    @State var date = Date()
    @State private var showStopList = false
    @State private var stop: Stop = .example
    @AppStorage(Stored.displaySocketStatus) var displaySocketStatus = false
    @AppStorage(Stored.displayClockOnTable) var displayClock = true

    private let updateTabBarApperance: () -> Void

    init(_ updateTabBarApperance: @escaping () -> Void) {
        self.updateTabBarApperance = updateTabBarApperance
    }

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                VirtualTableList(virtualTableController.tabs, virtualTableController.currentStop, virtualTableController.vehicleInfo)
                CocoaTextField("Search", text: $stop.name)
                    .disabled(true)
                    .padding(.vertical, 10.0)
                    .padding(.horizontal, 16.0)
                    .background(.ultraThinMaterial)
                    .cornerRadius(14.0, style: .circular)
                    .padding(.horizontal, 24.0)
                    .offset(y: -16.0)
                    .onPress {
                        self.showStopList = true
                    }
                    .sheet(isPresented: $showStopList) {
                        StopListView(stop: self.$stop, stopList: stopListProvider.stops, isPresented: self.$showStopList)
                    }.onChange(of: stop) { stop in
                        virtualTableController.changeStop(stop.id)
                    }
            }
            .navigationTitle(Text(virtualTableController.currentStop.name ?? "Loading..."))
            .navigationBarItems(
                leading: Text(displaySocketStatus ? virtualTableController.socketStatus : "").onPress {
                    virtualTableController.connect()
                },
                trailing: Text(displayClock ? clockStringFromDate(date) : "")
            )
        }
        .ifCondition(displayClock) { navView in
            navView.onAppear {
                Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
                    self.date = Date()
                }
            }
        }
        .onAppear {
            updateTabBarApperance()
        }
    }
}

// struct VirtualTableView_Previews: PreviewProvider {
//    static var previews: some View {
//        VirtualTableView()
//    }
// }
