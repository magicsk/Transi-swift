//
//  ContentView.swift
//  Transi
//
//  Created by magic_sk on 05/11/2022.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject private var dataProvider = DataProvider()
    
    var body: some View {
        TabView {
            TripPlannerView(dataProvider)
                .tabItem {
                    Image(systemName: "tram")
                    Text("Trip planner")
                }
            VirtualTableView(dataProvider)
                .tabItem {
                    Image(systemName: "clock.arrow.2.circlepath")
                    Text("Virtual Table")
                }
            TimetablesView()
                .tabItem {
                    Image(systemName: "calendar")
                    Text("Timetables")
                }
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
