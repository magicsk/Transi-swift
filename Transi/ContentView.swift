//
//  ContentView.swift
//  Transi
//
//  Created by magic_sk on 05/11/2022.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TripPlannerView()
                .tabItem {
                    Image(systemName: "tram")
                    Text("Trip planner")
                }
            VirtualTableView()
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
