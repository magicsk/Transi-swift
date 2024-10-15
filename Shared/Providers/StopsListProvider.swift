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
    @Published var unmodifiedStops = [Stop]()
    @Published var fetchError = false
    @Published var fetchLoading = false

    static var mapPointsNeeded = false

    let cachedStops = UserDefaults.standard.retrieve(object: [Stop].self, forKey: Stored.stops)
    private let stopsVersion = UserDefaults.standard.string(forKey: Stored.stopsVersion) ?? ""
    private let jsonEncoder = JSONEncoder()

    init() {
        if cachedStops != nil {
            stops = cachedStops!
            unmodifiedStops = cachedStops!
        }
        fetchStops()
    }

    func fetchStops() {
        fetchMagicApi(endpoint: "/stops?v", type: StopsVersion.self) { stopsVersionResult in
            switch stopsVersionResult {
                case .success(let stopsVersion):
                    print(stopsVersion.version)
                    if self.stopsVersion == stopsVersion.version, self.cachedStops != nil {
                        print("using cached stops json")
                    } else {
                        print("getting new stops json")
                        fetchMagicApi(endpoint: "/stops", type: [Stop].self) { stopsResult in
                            switch stopsResult {
                                case .success(let newStops):
                                    DispatchQueue.main.async {
                                        self.stops = newStops
                                        self.unmodifiedStops = newStops
                                        self.fetchLoading = false
                                    }
                                    self.addUtilsToStopList()
                                    UserDefaults.standard.save(customObject: newStops, forKey: Stored.stops)
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
        if stops.count > 0 {
            DispatchQueue.main.async {
                self.stops = self.unmodifiedStops.sorted(by: { $0.distance(to: coordinates) < $1.distance(to: coordinates) })
                self.addUtilsToStopList()
                if GlobalController.virtualTable.changeLocation {
                    GlobalController.virtualTable.changeStop(GlobalController.getNearestStopId(), switchOnly: true)
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
