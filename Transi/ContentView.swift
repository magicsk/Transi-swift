//
//  ContentView.swift
//  Transi
//
//  Created by magic_sk on 05/11/2022.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject private var dataProvider = DataProvider()
    @State private var selection = 2
    
    var body: some View {
        TabView (selection: $selection) {
            TripPlannerView(dataProvider)
                .tabItem {
                    Image(systemName: "tram")
                    Text("Trip planner")
                }.tag(1)
            VirtualTableView(dataProvider)
                .tabItem {
                    Image(systemName: "clock.arrow.2.circlepath")
                    Text("Virtual Table")
                }.tag(2)
            TimetablesView()
                .tabItem {
                    Image(systemName: "calendar")
                    Text("Timetables")
                }.tag(3)
        }.onAppear {
            selection = 2
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
