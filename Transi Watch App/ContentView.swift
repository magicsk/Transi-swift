//
//  ContentView.swift
//  Transi Watch App
//
//  Created by magic_sk on 22/03/2023.
//

import SwiftUI

struct ContentView: View {
    
    @ObservedObject private var dataProvider = DataProvider()
    
    
    @State private var showStopList = false
    @State private var stopId = 94
    @State private var actualName = "Loading..."
     
    
    var body: some View {
        NavigationView {
            Text("TBD")
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
