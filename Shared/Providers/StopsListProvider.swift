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
                                    }
                                    self.addUtilsToStopList()
                                    Self.saveCachedStops(newStops)
                                    if let location = LocationProvider.lastLocation {
                                        self.sortStops(coordinates: location.coordinate)
                                    }
                                case .failure:
                                    DispatchQueue.main.async {
                                        self.fetchError = true
                                        self.fetchLoading = true
                                    }
                            }
                        }
                        UserDefaults.standard.set(stopsVersion.version, forKey: Stored.stopsVersion)
                    }
                    GlobalController.locationProvider.startUpdatingLocation()

                case .failure:
                    DispatchQueue.main.async {
                        self.fetchError = true
                        self.fetchLoading = true
                    }
            }
        }
    }

    private func addUtilsToStopList() {
        DispatchQueue.main.async {
            if self.stops.first?.id != Stop.actualLocation.id {
                self.stops.insert(Stop.actualLocation, at: 0)
            }
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
                self.addUtilsToStopList()
                if GlobalController.virtualTable.changeLocation {
                    GlobalController.virtualTable.changeStop(
                        GlobalController.getNearestStopId(), switchOnly: true)
                }
            }
        }
    }

    func getStopIdFromName(_ stopName: String) -> Int? {
        return stops.first(where: { stop in
            stop.name == stopName
        })?.id
    }
}
