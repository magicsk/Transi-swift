//
//  CLLocationCoordinate2D.swift
//  Transi
//
//  Created by magic_sk on 19/11/2023.
//

import CoreLocation

extension CLLocationCoordinate2D {
    func toLocation() -> CLLocation {
        return CLLocation(latitude: self.latitude, longitude: self.longitude)
    }
    
    func distance(to: CLLocationCoordinate2D) -> CLLocationDistance {
        return to.toLocation().distance(from: self.toLocation())
    }
}
