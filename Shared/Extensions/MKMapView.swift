//
//  MKMapView.swift
//  Transi
//
//  Created by magic_sk on 05/12/2023.
//

import MapKit

extension MKMapView {
    func animatedZoom(_ zoomRegion: MKCoordinateRegion, _ duration: TimeInterval) {
        MKMapView.animate(withDuration: duration, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 10, options: UIView.AnimationOptions.curveEaseIn, animations: {
            self.setRegion(zoomRegion, animated: true)
        }, completion: nil)
    }
}
