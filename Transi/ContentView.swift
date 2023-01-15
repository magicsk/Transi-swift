//
//  ContentView.swift
//  Transi
//
//  Created by magic_sk on 05/11/2022.
//

import SwiftUI

struct ContentView: View {

    @ObservedObject var dataProvider = DataProvider()
    @State private var showStopList = false
    @State private var stopId = 94
    var body: some View {
        NavigationView {
            List(dataProvider.tabs) { tab in
                let departureTime = tab.departureTime - Int(NSDate().timeIntervalSince1970)
                let departureTimeText = departureTime > 60 ? "\(departureTime / 60) min" : departureTime > 0 ? "<1 min" : "now"
                Label {
                    Text(tab.headsign).font(.subheadline)
                    Spacer()
                    Text(departureTimeText).font(.headline)
                }
                icon: {
                    Text(tab.line).font(.headline).frame(width: 40)
                }
            }
                .navigationBarTitle(Text(dataProvider.stops.first(where: { $0.id == dataProvider.stopId })?.name ?? "Hronská"))

                .toolbar { Button("Change") {
                    self.showStopList = true
                }.sheet(isPresented: $showStopList) {
                    StopListView(stopId: self.$stopId, stopList: dataProvider, isPresented: self.$showStopList)
                }
            }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
