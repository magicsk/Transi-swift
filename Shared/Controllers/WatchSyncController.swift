//
//  WatchSyncController.swift
//  Transi
//
//  Created by magic_sk on 19/11/2026.
//

import Foundation
import WatchConnectivity

/// Keeps the iPhone and the watch in step. Each side sends its whole state as the application context, so only the
/// latest one is delivered. Favorites go both ways and the more recently changed list wins; the default stop, the
/// trip settings and the recent trip searches go from the iPhone to the watch.
final class WatchSyncController: NSObject, WCSessionDelegate {
    func activate() {
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    /// Main thread.
    func sendState() {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        #if os(iOS)
        guard session.isPaired, session.isWatchAppInstalled else { return }
        #endif
        let defaults = UserDefaults.standard
        var context: [String: Any] = [
            Stored.favoriteStopIds: GlobalController.stopsListProvider.favoriteStopIds,
            Stored.favoriteStopIdsUpdatedAt: defaults.double(forKey: Stored.favoriteStopIdsUpdatedAt),
        ]
        #if os(iOS)
        for key in [Stored.defaultStopId, Stored.tripMaxTransfers, Stored.tripMaxWalkDuration] {
            context[key] = defaults.integer(forKey: key)
        }
        // From the defaults, which the planner may not have loaded yet at launch, and without their cached results,
        // which the watch fetches again for the current time.
        let saved = defaults.retrieve(object: [RecentTripSearch].self, forKey: Stored.tripRecentSearches) ?? []
        let searches = saved.map {
            RecentTripSearch(
                from: $0.from, to: $0.to, arrivalDeparture: $0.arrivalDeparture,
                arrivalDepartureDate: $0.arrivalDepartureDate, arrivalDepartureCustomDate: $0.arrivalDepartureCustomDate,
                tripSavedAt: $0.tripSavedAt, searchedAt: $0.searchedAt
            )
        }
        context[Stored.tripRecentSearches] = try? JSONEncoder().encode(searches)
        #endif
        do {
            try session.updateApplicationContext(context)
        } catch {
            #if DEBUG
            print("Watch sync failed: \(error)")
            #endif
        }
    }

    /// Main thread.
    private func apply(_ context: [String: Any]) {
        let defaults = UserDefaults.standard
        let provider = GlobalController.stopsListProvider
        if let ids = context[Stored.favoriteStopIds] as? [Int],
           let updatedAt = context[Stored.favoriteStopIdsUpdatedAt] as? TimeInterval
        {
            if !defaults.bool(forKey: Stored.favoriteStopIdsSynced) {
                // The first exchange keeps both lists whatever their edit times, so it drops no favorite.
                defaults.set(true, forKey: Stored.favoriteStopIdsSynced)
                // The iPhone's order leads on both sides, so its list doesn't reorder when the watch's extras come back.
                #if os(iOS)
                let merged = provider.favoriteStopIds + ids.filter { !provider.favoriteStopIds.contains($0) }
                #else
                let merged = ids + provider.favoriteStopIds.filter { !ids.contains($0) }
                #endif
                // Adding nothing keeps the other side's edit time, so a newer edit there (a removal) still wins.
                let addsNothing = Set(merged) == Set(ids)
                provider.setFavorites(merged, updatedAt: addsNothing ? updatedAt : Date().timeIntervalSince1970)
                if !addsNothing { sendState() }
            } else if updatedAt > defaults.double(forKey: Stored.favoriteStopIdsUpdatedAt) {
                provider.setFavorites(ids, updatedAt: updatedAt)
            } else if updatedAt < defaults.double(forKey: Stored.favoriteStopIdsUpdatedAt) {
                // The other side is behind, say a watch app installed after the iPhone last sent; it takes ours.
                sendState()
            }
        }
        #if os(watchOS)
        let previousDefaultStopId = defaults.integer(forKey: Stored.defaultStopId)
        for key in [Stored.defaultStopId, Stored.tripMaxTransfers, Stored.tripMaxWalkDuration] {
            if let value = context[key] as? Int { defaults.set(value, forKey: key) }
        }
        // A default stop arriving after the board picked one on its own (first launch) takes over, as it would at
        // launch; a stop the rider chose stays.
        let defaultStopId = defaults.integer(forKey: Stored.defaultStopId)
        if defaultStopId > 0, defaultStopId != previousDefaultStopId, GlobalController.virtualTable.changeLocation,
           GlobalController.getStopById(defaultStopId) != nil
        {
            GlobalController.virtualTable.changeStop(defaultStopId)
        }
        if let data = context[Stored.tripRecentSearches] as? Data,
           let searches = try? JSONDecoder().decode([RecentTripSearch].self, from: data)
        {
            GlobalController.tripPlanner.mergeRecentSearches(searches)
        }
        #endif
    }

    func session(_ session: WCSession, activationDidCompleteWith state: WCSessionActivationState, error: Error?) {
        guard state == .activated else { return }
        let context = session.receivedApplicationContext
        DispatchQueue.main.async {
            self.apply(context)
            self.sendState()
        }
    }

    func session(_: WCSession, didReceiveApplicationContext context: [String: Any]) {
        DispatchQueue.main.async { self.apply(context) }
    }

    #if os(iOS)
    /// The watch app was installed or the watch was paired.
    func sessionWatchStateDidChange(_: WCSession) {
        DispatchQueue.main.async { self.sendState() }
    }

    func sessionDidBecomeInactive(_: WCSession) {}

    /// After the user switches to another watch.
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif
}
