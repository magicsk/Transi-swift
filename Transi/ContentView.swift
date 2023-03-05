//
//  ContentView.swift
//  Transi
//
//  Created by magic_sk on 05/11/2022.
//

import SwiftUI

struct ContentView: View {

    @ObservedObject private var dataProvider = DataProvider()
    @StateObject private var locationProvider = LocationProvider()
    
    @State private var showStopList = false
    @State private var stopId = 94  
    @State private var actualName = "Loading..."
    
    init() {
        dataProvider.connect()
        dataProvider.fetchStops()
    }
     
    var body: some View {
        NavigationView {
                TableView(dataProviderProp: dataProvider)
                .navigationBarTitle(Text(dataProvider.stops.first(where: { $0.id == dataProvider.stopId })?.name ?? "Loading..."))

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
