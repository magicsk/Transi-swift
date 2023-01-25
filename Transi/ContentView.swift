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
                let timeInMins = departureTime / 60
                let departureTimeText = departureTime > 59 ?
                timeInMins > 59 ?
                (Date(timeIntervalSince1970: TimeInterval(departureTime)).formatted(date: .omitted, time: .shortened)) :
                "\(timeInMins) min" :
                departureTime > 0 ? "<1 min" : "now"
                let isDelay = tab.delay > 0
                let isInAdvance = tab.delay < 0
                let delay = isDelay ? "+\(tab.delay)" : isInAdvance ? "-\(tab.delay)" : ""
                Label {
                    HStack(alignment: .center){
                        VStack{
                            HStack {
                                Text(tab.headsign).font(.subheadline)
                                Spacer()
                            }
                            HStack {
                                Text(tab.lastStopName).font(.system(size: 10, weight: .light, design: .default))
                                Spacer()
                            }
                        }
                        Spacer()
                        Text(delay).font(.subheadline).foregroundColor(isDelay ? .red : .purple)
                        Text(departureTimeText).font(.headline)
                    }
                }
                icon: {
                    Text(tab.line).font(.headline).frame(width: 40).offset(y: 5)
                }
                }
                .navigationBarTitle(Text(dataProvider.stops.first(where: { $0.id == dataProvider.stopId })?.name ?? "Hronská"))

                .toolbar { Button("Change") {
                    self.showStopList = true
                }.sheet(isPresented: $showStopList) {
                    StopListView(stopId: self.$stopId, dataProviderProp: dataProvider, isPresented: self.$showStopList)
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
