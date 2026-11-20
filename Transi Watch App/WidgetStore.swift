//
//  WidgetStore.swift
//  Transi Watch App
//
//  Created by magic_sk on 19/11/2026.
//

import Foundation

/// What the watch app leaves for its widget in their shared App Group: the stops the widget can show.
enum WidgetStore {
    static let appGroup = "group.eu.magicsk.Transi"
    /// The departures widget's kind, for reloading its timelines.
    static let departuresKind = "Departures"

    private static let defaults = UserDefaults(suiteName: appGroup) ?? .standard
    private static let nearestStopKey = "widget_nearest_stop"
    private static let nearestStopDateKey = "widget_nearest_stop_date"
    private static let favoriteStopsKey = "widget_favorite_stops"

    /// The stop nearest the watch at the app's last location fix; nil before one, and once that fix is too old to
    /// trust that the wearer is still there.
    static var nearestStop: Stop? {
        // ponytail: watchOS gives widgets no location of their own, so trust the app's fix for a fixed 2 h; the
        // widget then asks to open Transi rather than show a stop the wearer likely left.
        let age = Date().timeIntervalSince1970 - defaults.double(forKey: nearestStopDateKey)
        return age < 2 * 60 * 60 ? defaults.retrieve(object: Stop.self, forKey: nearestStopKey) : nil
    }

    /// Saves the stop nearest the location fix taken at `date`.
    static func setNearestStop(_ stop: Stop, seenAt date: Date) {
        defaults.save(customObject: stop, forKey: nearestStopKey)
        defaults.set(date.timeIntervalSince1970, forKey: nearestStopDateKey)
    }

    /// The favorite stops, in the order the user added them.
    static var favoriteStops: [Stop] {
        get { defaults.retrieve(object: [Stop].self, forKey: favoriteStopsKey) ?? [] }
        set { defaults.save(customObject: newValue, forKey: favoriteStopsKey) }
    }
}
