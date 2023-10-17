//
//  ContentView.swift
//  Transi
//
//  Created by magic_sk on 05/11/2022.
//

import SwiftUI
import SwiftUIX

struct ContentView: View {
    @ObservedObject private var dataProvider = DataProvider()
    @State private var selection = 2
    @State private var showStopList = false
    @State private var stop: Stop = .example

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selection) {
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
            
            if selection == 2 {
                CocoaTextField("Search", text: $stop.name)
                    .disabled(true)
                    .padding(.vertical, 10.0)
                    .padding(.horizontal, 16.0)
                    .background(.ultraThinMaterial)
                    .cornerRadius(14.0, style: .circular)
                    .padding(.horizontal, 24.0)
                    .offset(y: -64)
                    .onPress {
                        self.showStopList = true
                    }
                    .sheet(isPresented: $showStopList) {
                        StopListView(stop: self.$stop, stopList: dataProvider.stops, isPresented: self.$showStopList)
                    }.onChange(of: stop) {stop in
                        dataProvider.changeStop(stop.id ?? 0)
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
