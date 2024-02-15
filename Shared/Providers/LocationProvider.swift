//
//  LocationProvider.swift
//  Transi
//
//  Created by magic_sk on 10/02/2024.
//

import Foundation
import CoreLocation

class LocationProvider: NSObject, CLLocationManagerDelegate {
    public let locationManager = CLLocationManager()
    static var lastLocation: CLLocation? = nil

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.requestWhenInUseAuthorization()
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        print("got new location")
        LocationProvider.lastLocation = location
        GlobalController.stopsListProvider.sortStops(coordinates: location.coordinate)
        if GlobalController.tripPlanner.from == .empty { GlobalController.tripPlanner.from = .actualLocation }
    }

    func startUpdatingLocation() {
        locationManager.startUpdatingLocation()
    }
}
