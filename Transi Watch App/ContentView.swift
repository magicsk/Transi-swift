//
//  ContentView.swift
//  Transi Watch App
//
//  Created by magic_sk on 22/03/2023.
//

import SwiftUI

struct ContentView: View {
    /// A new id drops whatever was pushed, so a link opens on the departures.
    @State private var navigationID = UUID()

    var body: some View {
        NavigationStack {
            DeparturesView()
        }
        .id(navigationID)
        .onOpenURL { url in
            // transi://table/<stop id>, from the widget; -1 follows the nearest stop.
            guard url.host == "table", url.pathComponents.count >= 2, let stopId = Int(url.pathComponents[1]) else {
                return
            }
            navigationID = UUID()
            GlobalController.virtualTable.changeStop(stopId)
        }
    }
}

#Preview {
    ContentView()
}
