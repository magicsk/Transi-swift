//
//  StopsListProvider.swift
//  Transi
//
//  Created by magic_sk on 12/02/2024.
//

import Foundation
import CoreLocation

class StopsListProvider: ObservableObject {
    @Published var stops = [Stop]()
    @Published var unmodifiedStops = [Stop]()

    static var mapPointsNeeded = false
    
    private let stopsVersion = UserDefaults.standard.string(forKey: Stored.stopsVersion) ?? ""
    private let jsonEncoder = JSONEncoder()
    
    init() {
        fetchStops()
    }
    
    private func fetchStops() {
        let cachedStops = UserDefaults.standard.retrieve(object: [Stop].self, forKey: Stored.stops)
        if cachedStops != nil {
            self.stops = cachedStops!
            self.unmodifiedStops = cachedStops!
        }
        GlobalController.fetchData(url: "\(GlobalController.magicApiBaseUrl)/stops?v", type: StopsVersion.self) { stopsVersion in
            print(stopsVersion.version)
            DispatchQueue.main.async {
                if self.stopsVersion == stopsVersion.version, cachedStops != nil {
                    print("using cached stops json")
                } else {
                    print("getting new stops json")
                    GlobalController.fetchData(url: "\(GlobalController.magicApiBaseUrl)/stops", type: [Stop].self) { newStops in
                        self.stops = newStops
                        self.unmodifiedStops = newStops
                        UserDefaults.standard.save(customObject: newStops, forKey: Stored.stops)
                    }
                }
                UserDefaults.standard.set(stopsVersion.version, forKey: Stored.stopsVersion)
                GlobalController.locationProvider.startUpdatingLocation()
            }
        }
    }
    
    private func addUtilsToStopList() {
        stops.insert(Stop.actualLocation, at: 0)
    }

    func sortStops(coordinates: CLLocationCoordinate2D) {
        if stops.count > 0 {
            DispatchQueue.main.async {
                self.stops = self.unmodifiedStops.sorted(by: { $0.distance(to: coordinates) < $1.distance(to: coordinates) })
                self.addUtilsToStopList()
                if GlobalController.virtualTable.changeLocation {
                    GlobalController.virtualTable.changeStop(GlobalController.getNearestStopId(), true)
                }
            }
        }
    }


}
