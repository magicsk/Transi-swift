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
                .onOpenURL { url in
                    print(url)
                    switch url.host {
                    case "trip":
                        selection = 0
                    case "table":
                        selection = 1
                        if url.pathComponents.endIndex >= 2 {
                            if let stopId = Int(url.pathComponents[1]) {
                                if url.pathComponents.endIndex >= 3 {
                                    GlobalController.virtualTable.changeStop(stopId, expandConnection: url.pathComponents[2])
                                } else {
                                    GlobalController.virtualTable.changeStop(stopId)
                                }
                            }
                        }
                    case "timetable":
                        selection = 2
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
