//
//  ContentView.swift
//  Transi
//
//  Created by magic_sk on 05/11/2022.
//

import SwiftUI
import SwiftUIIntrospect
import SwiftUIX

struct ContentView: View {
    @StateObject private var dataProvider = DataProvider()
    
    @State private var selection = 3
    @State private var tabView: UITabBarController? = nil
    private let tabBarAppearance = UITabBarAppearance()

    init() {
        tabBarAppearance.configureWithTransparentBackground()
    }

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
                    .environmentObject(dataProvider)
                    .tabItem {
                        Image(systemName: "calendar")
                        Text("Timetables")
                    }.tag(3)
                MapKitView(dataProvider, changeTab)
                    .ignoresSafeArea()
                    .tabItem {
                        Image(systemName: "map")
                        Text("Map")
                    }.tag(4)
            }
            .onChange(of: selection) { _ in
                updateTabBarApperance()
            }
            .introspect(.tabView, on: .iOS(.v15, .v16, .v17)) { tv in
                DispatchQueue.main.async {
                    tabView = tv
                }
            }
        }
    }

    func changeTab(_ tag: Int) {
        selection = tag
    }
    
    func updateTabBarApperance() {
        DispatchQueue.main.async {
            if selection == 4 {
                tabBarAppearance.backgroundEffect = UIBlurEffect(style: .systemMaterial)
            } else {
                tabBarAppearance.configureWithTransparentBackground()
            }
            tabView?.tabBar.scrollEdgeAppearance = tabBarAppearance
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
