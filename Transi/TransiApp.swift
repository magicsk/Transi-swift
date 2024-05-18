//
//  TransiApp.swift
//  Transi
//
//  Created by magic_sk on 05/11/2022.
//

import SwiftUI

@main
struct TransiApp: App {
    @Environment(\.scenePhase) private var scenePhase

    init() {
        GlobalController.appLaunch()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _ in
            GlobalController.scenePhaseChange(scenePhase)
        }
    }
}
