//
//  StopsListProvider.swift
//  Transi
//
//  Created by magic_sk on 12/02/2024.
//

import CoreLocation
import Foundation

class StopsListProvider: ObservableObject {
    @Published var stops = [Stop]()
    var unmodifiedStops = [Stop]()
    @Published var fetchError = false
    @Published var fetchLoading = false
    @Published var favoriteStopIds = UserDefaults.standard.array(forKey: Stored.favoriteStopIds) as? [Int] ?? []

    static var mapPointsNeeded = false

    private static let stopsFileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("stops.json")
    }()

    private let cachedStops: [Stop]?
    private let stopsVersion = UserDefaults.standard.string(forKey: Stored.stopsVersion) ?? ""

    init() {
        cachedStops = Self.loadCachedStops()
        if let cachedStops = cachedStops {
            stops = cachedStops
            unmodifiedStops = cachedStops
        }
        fetchStops()
    }

    private static func loadCachedStops() -> [Stop]? {
        if let data = try? Data(contentsOf: stopsFileURL) {
            return try? JSONDecoder().decode([Stop].self, from: data)
        }
        // Migrate from UserDefaults if file cache doesn't exist yet
        if let stops = UserDefaults.standard.retrieve(object: [Stop].self, forKey: Stored.stops) {
            saveCachedStops(stops)
            UserDefaults.standard.removeObject(forKey: Stored.stops)
            return stops
        }
        return nil
    }

    private static func saveCachedStops(_ stops: [Stop]) {
        if let data = try? JSONEncoder().encode(stops) {
            try? data.write(to: stopsFileURL)
        }
    }

    func fetchStops() {
        fetchMagicApi(endpoint: "/stops?v", type: StopsVersion.self) { stopsVersionResult in
            switch stopsVersionResult {
                case .success(let stopsVersion):
                    #if DEBUG
                    print(stopsVersion.version)
                    #endif
                    if self.stopsVersion == stopsVersion.version, self.cachedStops != nil {
                        #if DEBUG
                        print("using cached stops json")
                        #endif
                    } else {
                        #if DEBUG
                        print("getting new stops json")
                        #endif
                        fetchMagicApi(endpoint: "/stops", type: [Stop].self) { stopsResult in
                            switch stopsResult {
                                case .success(let newStops):
                                    DispatchQueue.main.async {
                                        self.stops = newStops
                                        self.unmodifiedStops = newStops
                                        self.fetchLoading = false
                                        GlobalController.virtualTable.resolveCurrentStop()
                                        if let location = LocationProvider.lastLocation {
                                            self.sortStops(coordinates: location.coordinate)
                                        } else {
                                            self.setDefaultStopIfNeeded()
                                        }
                                    }
                                    self.updateActualLocationEntry()
                                    Self.saveCachedStops(newStops)
                                    // Saved only with the list, so a failed download is fetched again on next launch.
                                    UserDefaults.standard.set(stopsVersion.version, forKey: Stored.stopsVersion)
                                case .failure:
                                    DispatchQueue.main.async {
                                        self.fetchError = true
                                        self.fetchLoading = true
                                        self.retryIfNoStops()
                                    }
                            }
                        }
                    }
                    GlobalController.locationProvider.startUpdatingLocation()
                    if !LocationProvider.isLocationAvailable {
                        self.setDefaultStopIfNeeded()
                    }

                case .failure:
                    DispatchQueue.main.async {
                        self.fetchError = true
                        self.fetchLoading = true
                        self.retryIfNoStops()
                    }
            }
        }
    }

    // Main thread. Without a cached list nothing works, so keep trying until it loads.
    // Only a failure schedules the next try, so at most one fetch runs at a time.
    private func retryIfNoStops() {
        guard unmodifiedStops.isEmpty else { return }
        // ponytail: fixed 5 s interval, add backoff if the extra requests ever matter
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            // fetchStops starts location updates, which must stay off in the background.
            if GlobalController.appState.phase == .background { self.retryIfNoStops() } else { self.fetchStops() }
        }
    }

    func updateActualLocationEntry() {
        DispatchQueue.main.async {
            let hasIt = self.stops.first?.id == Stop.actualLocation.id
            if LocationProvider.isLocationAvailable {
                if !hasIt { self.stops.insert(Stop.actualLocation, at: 0) }
            } else {
                if hasIt { self.stops.removeFirst() }
            }
        }
    }

    // Waits for a stop list, so a fresh install never shows a placeholder stop. The /stops completion resolves the table.
    func setDefaultStopIfNeeded() {
        DispatchQueue.main.async {
            if GlobalController.virtualTable.currentStop.id == Stop.empty.id, !self.unmodifiedStops.isEmpty {
                self.showDefaultStop()
            }
        }
    }

    // Main thread. A valid default turns off nearest-stop following, so later location fixes keep it.
    private func showDefaultStop() {
        let defaultStopId = UserDefaults.standard.integer(forKey: Stored.defaultStopId)
        if defaultStopId > 0, GlobalController.getStopById(defaultStopId) != nil {
            GlobalController.virtualTable.changeStop(defaultStopId)
        } else {
            GlobalController.virtualTable.changeStop(GlobalController.getNearestStopId(), switchOnly: true)
        }
    }

    func sortStops(coordinates: CLLocationCoordinate2D) {
        guard !unmodifiedStops.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            let sorted = self.unmodifiedStops.sorted(by: {
                $0.distance(to: coordinates) < $1.distance(to: coordinates)
            })
            DispatchQueue.main.async {
                self.stops = sorted
                self.updateActualLocationEntry()
                // In the background the table stays disconnected; a followed trip keeps the location updating.
                if GlobalController.appState.phase != .background {
                    self.showNearestStop()
                }
            }
        }
    }

    // Main thread. While the table follows the location, shows the stop nearest it, or the default one before any.
    func showNearestStop() {
        guard GlobalController.virtualTable.changeLocation, !unmodifiedStops.isEmpty else { return }
        if GlobalController.virtualTable.currentStop.id == Stop.empty.id {
            showDefaultStop()
        } else {
            GlobalController.virtualTable.changeStop(GlobalController.getNearestStopId(), switchOnly: true)
        }
    }

    func toggleFavorite(_ stopId: Int) {
        if let index = favoriteStopIds.firstIndex(of: stopId) {
            favoriteStopIds.remove(at: index)
        } else {
            favoriteStopIds.append(stopId)
        }
        UserDefaults.standard.set(favoriteStopIds, forKey: Stored.favoriteStopIds)
    }

    func getStopIdFromName(_ stopName: String) -> Int? {
        return stops.first(where: { stop in
            stop.name == stopName
        })?.id
    }

    func getStopFromName(_ stopName: String) -> Stop? {
        return stops.first(where: { $0.name == stopName })
    }
}
