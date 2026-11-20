//
//  TransiWatchApp.swift
//  Transi Watch App
//
//  Created by magic_sk on 22/03/2023.
//

import Combine
import SwiftUI
import WidgetKit

@main
struct TransiWatchApp: App {
    @Environment(\.scenePhase) private var scenePhase
    private static var widgetSubscription: AnyCancellable?

    init() {
        GlobalController.appLaunch()
        Self.widgetSubscription = Self.updateWidget()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .onChange(of: scenePhase) { _, phase in
            GlobalController.scenePhaseChange(phase)
        }
    }

    /// Leaves the nearest and favorite stops for the widget, and reloads it when either changes.
    private static func updateWidget() -> AnyCancellable {
        let provider = GlobalController.stopsListProvider
        return provider.$stops.combineLatest(provider.$favoriteStopIds)
            .debounce(for: .seconds(2), scheduler: DispatchQueue.main)
            .sink { stops, favoriteIds in
                // Without the list, every favorite would look gone.
                guard !provider.unmodifiedStops.isEmpty else { return }
                // The widget can't locate itself on watchOS, so this fix is its nearest stop until WidgetStore expires it.
                let nearest = LocationProvider.lastLocation == nil ? nil : stops.first { $0.id > 0 }
                let favorites = favoriteIds.compactMap { id in provider.unmodifiedStops.first { $0.id == id } }
                // An expired nearest stop reads as nil, so coming back to it also counts as a change.
                let nearestChanged = nearest.map { $0.id != WidgetStore.nearestStop?.id } ?? false
                let favoritesChanged = favorites.map(\.id) != WidgetStore.favoriteStops.map(\.id)
                // Stamped with the fix's own time, so a later favorites change can't make an old fix look new.
                if let nearest, let fix = LocationProvider.lastLocation {
                    WidgetStore.setNearestStop(nearest, seenAt: fix.timestamp)
                }
                if favoritesChanged {
                    WidgetStore.favoriteStops = favorites
                    // The widget offers a configuration per favorite.
                    WidgetCenter.shared.invalidateConfigurationRecommendations()
                }
                if nearestChanged || favoritesChanged {
                    WidgetCenter.shared.reloadTimelines(ofKind: WidgetStore.departuresKind)
                }
            }
    }
}
