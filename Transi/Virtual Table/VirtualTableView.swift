//
//  VirtualTableView.swift
//  Transi
//
//  Created by magic_sk on 08/05/2023.
//

import SwiftUI
import SwiftUIX

struct VirtualTableView: View {
    @ObservedObject var dataProvider: DataProvider
    @State var date = Date()
    @State private var showStopList = false
    @State private var stop: Stop = .example
    @AppStorage(Stored.displaySocketStatus) var displaySocketStatus = false
    @AppStorage(Stored.displayClockOnTable) var displayClock = true

    init(_ dataProvider: DataProvider) {
        self.dataProvider = dataProvider
    }

    var body: some View {
        NavigationView {
            ZStack(alignment: .bottom) {
                VirtualTableList(dataProvider)
                    .navigationTitle(Text(dataProvider.currentStop.name ?? "Loading..."))
                    .navigationBarItems(
                        leading: Text(displaySocketStatus ? dataProvider.socketStatus : ""),
                        trailing: Text(displayClock ? clockStringFromDate(date) : "")
                    )
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
                        StopListView(stop: self.$stop, stopList: dataProvider.stops, isPresented: self.$showStopList)
                    }.onChange(of: stop) { stop in
                        dataProvider.changeStop(stop.id ?? 0)
                    }
            }
        }
        .ifCondition(displayClock) { navView in
            navView.onReceive(Timer.publish(every: 1, on: .current, in: .common).autoconnect()) { _ in
                self.date = Date()
            }
        }
    }
}

// struct VirtualTableView_Previews: PreviewProvider {
//    static var previews: some View {
//        VirtualTableView()
//    }
// }
