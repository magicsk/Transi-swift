//
//  StopsView.swift
//  Transi Watch App
//
//  Created by magic_sk on 19/11/2026.
//

import Fuse
import SwiftUI

/// Nearby and favorite stops with search. Picks the board's stop, or with `onSelect` a stop for the trip planner.
struct StopsView: View {
    var title: LocalizedStringKey = "Stops"
    /// Called with the picked stop; nil shows it on the departure board.
    var onSelect: ((Stop) -> Void)? = nil

    @StateObject private var stopsList = GlobalController.stopsListProvider
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results = [Stop]()

    /// The closest stops, while the location is known; the provider keeps `stops` sorted by distance.
    private var nearby: [Stop] {
        guard LocationProvider.lastLocation != nil else { return [] }
        let favoriteIds = Set(stopsList.favoriteStopIds)
        return Array(stopsList.stops.lazy.filter { $0.id > 0 && !favoriteIds.contains($0.id) }.prefix(10))
    }

    var body: some View {
        let favorites = stopsList.favoriteStopIds.compactMap { id in stopsList.unmodifiedStops.first { $0.id == id } }
        List {
            if !query.isEmpty {
                if results.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ForEach(results) { row($0) }
                }
            } else {
                if LocationProvider.isLocationAvailable {
                    row(.actualLocation)
                }
                if !favorites.isEmpty {
                    Section("Favorites") {
                        ForEach(favorites) { row($0) }
                    }
                }
                if !nearby.isEmpty {
                    Section("Nearby") {
                        ForEach(nearby) { row($0) }
                    }
                }
                if favorites.isEmpty && nearby.isEmpty {
                    ContentUnavailableView(
                        "Find a Stop", systemImage: "magnifyingglass",
                        description: Text("Search, or allow location access to see stops nearby.")
                    )
                }
            }
        }
        .searchable(text: $query, prompt: "Search stops")
        .navigationTitle(title)
        // Also when the list arrives, which a fresh install downloads while the user may already be typing.
        .task(id: "\(query)|\(stopsList.unmodifiedStops.count)") {
            let query = query
            let stops = stopsList.unmodifiedStops
            let found = query.isEmpty ? [] : await Task.detached(priority: .userInitiated) {
                Self.search(query, in: stops)
            }.value
            // A newer query cancelled this task, but not the detached search; its results would overwrite the new ones.
            guard !Task.isCancelled else { return }
            results = found
        }
    }

    private func row(_ stop: Stop) -> some View {
        let isFavorite = stopsList.favoriteStopIds.contains(stop.id)
        return Button {
            if let onSelect {
                onSelect(stop)
            } else {
                GlobalController.virtualTable.changeStop(stop.id)
            }
            dismiss()
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 1.0) {
                    if stop.id == Stop.actualLocation.id {
                        Text(onSelect == nil ? "Nearest Stop" : "Current Location")
                    } else {
                        Text(stop.name ?? "").lineLimit(2)
                    }
                    if stop.id > 0, let distance = distance(to: stop) {
                        Text(distance).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } icon: {
                StopListIcon(stop.type)
            }
        }
        .swipeActions {
            if stop.id > 0 {
                Button {
                    stopsList.toggleFavorite(stop.id)
                } label: {
                    Label(
                        isFavorite ? "Remove Favorite" : "Favorite",
                        systemImage: isFavorite ? "star.slash" : "star"
                    )
                }
                .tint(isFavorite ? .red : .yellow)
            }
        }
    }

    private func distance(to stop: Stop) -> String? {
        guard let location = LocationProvider.lastLocation else { return nil }
        return Measurement(value: stop.distance(to: location.coordinate), unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road))
    }

    /// The stops matching `query` best first, by the same fuzzy search as the iPhone's stop list.
    nonisolated private static func search(_ query: String, in stops: [Stop]) -> [Stop] {
        let fuse = Fuse()
        let pattern = fuse.createPattern(from: query.normalize())
        let scored = stops.compactMap { stop in
            fuse.search(pattern, in: stop.normalizedName).map { (stop: stop, score: $0.score) }
        }
        return scored.sorted { $0.score < $1.score }.prefix(25).map(\.stop)
    }
}

#Preview {
    NavigationStack {
        StopsView()
    }
}
