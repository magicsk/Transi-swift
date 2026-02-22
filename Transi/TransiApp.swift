//
//  TransiApp.swift
//  Transi
//
//  Created by magic_sk on 05/11/2022.
//

import SwiftUI

@main
struct TransiApp: App {
    @State private var selection = 1
    @State private var urlErrorAlert = false
    @Environment(\.scenePhase) private var scenePhase

    init() {
        GlobalController.appLaunch()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(selectedIndex: $selection)
                .ignoresSafeArea()
                .onReceive(GlobalController.appState.$pendingNavigation.compactMap { $0 }) { dest in
                    GlobalController.appState.pendingNavigation = nil
                    switch dest {
                    case .trip:
                        selection = 0
                    case .table(let stopId, let expandConnection):
                        selection = 1
                        if let exp = expandConnection {
                            GlobalController.virtualTable.changeStop(stopId, expandConnection: exp)
                        } else {
                            GlobalController.virtualTable.changeStop(stopId)
                        }
                    case .timetable(let line):
                        selection = 2
                        GlobalController.appState.pendingTimetableLine = line
                    case .map(let stopId):
                        selection = 3
                        GlobalController.appState.openedURL = URL(string: "transi://map/\(stopId)")
                    }
                }
                .onOpenURL { url in
                    switch url.host {
                    case "trip":
                        GlobalController.appState.pendingNavigation = .trip
                    case "table":
                        if url.pathComponents.endIndex >= 2, let stopId = Int(url.pathComponents[1]) {
                            let expandConnection = url.pathComponents.endIndex >= 3 ? url.pathComponents[2] : nil
                            GlobalController.appState.pendingNavigation = .table(stopId: stopId, expandConnection: expandConnection)
                        } else {
                            selection = 1
                        }
                    case "timetable":
                        let line = url.pathComponents.endIndex >= 2 ? url.pathComponents[1] : nil
                        GlobalController.appState.pendingNavigation = .timetable(line: line)
                    case "map":
                        selection = 3
                        GlobalController.appState.openedURL = url
                    default:
                        urlErrorAlert = true
                    }
                }
                .alert(
                    "Unable to navigate",
                    isPresented: $urlErrorAlert
                ) {} message: {
                    Text("Openned url is either expired or no longer supported.")
                }
        }
        .onChange(of: scenePhase) { phase in
            GlobalController.scenePhaseChange(phase)
        }
    }
}
