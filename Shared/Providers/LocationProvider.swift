//
//  LocationProvider.swift
//  Transi
//
//  Created by magic_sk on 10/02/2024.
//

import CoreLocation
import Foundation

class LocationProvider: NSObject, CLLocationManagerDelegate {
    public let locationManager = CLLocationManager()
    static var lastLocation: CLLocation? = nil

    private var searchTimer: Timer?

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestAlwaysAuthorization()
        locationManager.distanceFilter = 50.0
        locationManager.showsBackgroundLocationIndicator = false
        locationManager.allowsBackgroundLocationUpdates = true
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        print("got new location")
        GlobalController.stopsListProvider.sortStops(coordinates: location.coordinate)
        LocationProvider.lastLocation = location
        if GlobalController.tripPlanner.from == .empty { GlobalController.tripPlanner.from = .actualLocation }
    }
    
    func decreaseAccuracy() {
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
    }

    func startUpdatingLocation() {
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.startUpdatingLocation()
    }
    
    func stopUpdatingLocation() {
        if GlobalController.appState.scene == .background {
            locationManager.stopUpdatingLocation()
        }
    }
}
