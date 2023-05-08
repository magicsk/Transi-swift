//
//  View.swift
//  Transi
//
//  Created by magic_sk on 08/05/2023.
//

import SwiftUI

struct VirtualTableView: View {

    @ObservedObject private var dataProvider = DataProvider()
    
    @State private var showStopList = false
    @State private var stopId = 94
    @State private var actualName = "Loading..."
     
    var body: some View {
            NavigationView {
                VirtualTableList(dataProvider)
                    #if !os(macOS)
                    .navigationTitle(Text(dataProvider.stops.first(where: { $0.id == dataProvider.stopId })?.name ?? "Loading..."))
                    #endif
                    .toolbar { Button("Change") {
                        self.showStopList = true
                    }.sheet(isPresented: $showStopList) {
                        StopListView(stopId: self.$stopId, dataProviderProp: dataProvider, isPresented: self.$showStopList)
                    }
                    }
            }
    }
    
}

struct VirtualTableView_Previews: PreviewProvider {
    static var previews: some View {
        VirtualTableView()
    }
}
