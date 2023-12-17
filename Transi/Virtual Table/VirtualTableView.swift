//
//  VirtualTableView.swift
//  Transi
//
//  Created by magic_sk on 08/05/2023.
//

import SwiftUI

struct VirtualTableView: View {
    @ObservedObject var dataProvider: DataProvider
    @State var date = Date()
    @AppStorage(Stored.displaySocketStatus) var displaySocketStatus = false
    @AppStorage(Stored.displayClockOnTable) var displayClock = true

    init(_ dataProvider: DataProvider) {
        self.dataProvider = dataProvider
    }

    var body: some View {
        NavigationView {
            VirtualTableList(dataProvider)
                .navigationTitle(Text(dataProvider.currentStop.name ?? "Loading..."))
                .navigationBarItems(leading: Text(displaySocketStatus ? dataProvider.socketStatus : ""), trailing: Text(displayClock ? clockStringFromDate(date) : ""))
        }.ifCondition(displayClock) { navView in
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
