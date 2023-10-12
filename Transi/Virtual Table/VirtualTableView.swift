//
//  VirtualTableView.swift
//  Transi
//
//  Created by magic_sk on 08/05/2023.
//

import SwiftUI

struct VirtualTableView: View {

    @ObservedObject var dataProvider: DataProvider
    @State private var showStopList = false
    @State private var stop: Stop = .example
    @State private var actualName = "Loading..."
    
    init(_ dataProvider: DataProvider) {
        self.dataProvider = dataProvider
    }

    var body: some View {
        NavigationView {
            VirtualTableList(dataProvider)
            #if !os(macOS)
                .navigationTitle(Text(dataProvider.stops.first(where: { $0.id == dataProvider.stopId })?.name ?? "Loading..."))
            #endif
                .toolbar {
                    Button("Change") {
                        self.showStopList = true
                    }.sheet(isPresented: $showStopList) {
                        StopListView(stop: self.$stop, stopList: dataProvider.stops, isPresented: self.$showStopList)
                    }
                }
        }.onChange(of: stop) {stop in
            dataProvider.changeStop(stop.id ?? 0)
        }
    }
}

//struct VirtualTableView_Previews: PreviewProvider {
//    static var previews: some View {
//        VirtualTableView()
//    }
//}
