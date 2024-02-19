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
    private let globalController = GlobalController()
    @StateObject var stopsListProvider = GlobalController.stopsListProvider

    @State private var selection = 2
    @State private var tabView: UITabBarController? = nil
    private let tabBarAppearance = UITabBarAppearance()

    init() {
        tabBarAppearance.configureWithTransparentBackground()
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selection) {
                TripPlannerView(updateTabBarApperance)
                    .tabItem {
                        Label("Trip planner", systemImage: "tram")
                    }.tag(1)
                VirtualTableView(updateTabBarApperance)
                    .tabItem {
                        Image(systemName: "clock.arrow.2.circlepath")
                        Text("Virtual Table")
                    }.tag(2)
                TimetablesView(updateTabBarApperance)
                    .tabItem {
                        Label("Timetables", systemImage: "calendar")
                    }.tag(3)
                MapKitView(updateTabBarApperance, changeTab)
                    .ignoresSafeArea()
                    .tabItem {
                        Image(systemName: "map")
                        Text("Map")
                    }.tag(4)
            }
            .introspect(.tabView, on: .iOS(.v15, .v16, .v17)) { tv in
                DispatchQueue.main.async {
                    tabView = tv
                }
            }
            LoadingView($stopsListProvider.fetchLoading)
        }
        .alert(isPresented: $stopsListProvider.fetchError, error: StopsListError.basic) { _ in 
            Button("Retry") {
                stopsListProvider.fetchStops()
            }
            if (stopsListProvider.cachedStops != nil) {
                Button("Use cached") {
                    stopsListProvider.fetchLoading = false
                    GlobalController.locationProvider.startUpdatingLocation()
                }
            }
        } message: { error in
            if let message = error.failureReason {
                Text(message)
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

// struct ContentView_Previews: PreviewProvider {
//    static var previews: some View {
//        ContentView()
//    }
// }
