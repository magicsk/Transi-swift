//
//  MapKitView.swift
//  Transi
//
//  Created by magic_sk on 18/11/2023.
//

import MapKit
import SwiftUI
import UIKit

struct MapKitView: UIViewControllerRepresentable {
    private let updateTabBarApperance: () -> Void
    private let changeTab: (Int) -> Void

    init(_ updateTabBarApperance: @escaping () -> Void, _ changeTab: @escaping (Int) -> Void) {
        self.updateTabBarApperance = updateTabBarApperance
        self.changeTab = changeTab
    }

    func makeUIViewController(context: Context) -> MapViewController {
        return MapViewController(updateTabBarApperance, changeTab)
    }

    func updateUIViewController(_ uiViewController: MapViewController, context: Context) {}
}

class MapViewController: UIViewController, MKMapViewDelegate, UISheetPresentationControllerDelegate {
    @StateObject var stopListProvider = GlobalController.stopsListProvider
    private let updateTabBarApperance: () -> Void
    private var tileLightOverlay: MKTileOverlay?
    private var tileDarkOverlay: MKTileOverlay?
    private var sheetViewController: MapBottomSheetView?
    private var sheetNavController: UIHostingController<MapBottomSheetView>?
    private var mapView: MKMapView!
    private let changeTab: (Int) -> Void

    private var mapLoaded = false
    private var selectedAnnotation: MKAnnotation? = nil
    private let defaultLocation = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 48.145, longitude: 17.107), latitudinalMeters: 500, longitudinalMeters: 500)
    private lazy var locationButton = UIButton(configuration: .filled())

    let sourceLightUrl = "https://tile.thunderforest.com/transport/{z}/{x}/{y}@2x.png?apikey=628502b3ae3a4c388efde8abb0577ca2"
    let sourceDarkUrl = "https://tile.thunderforest.com/transport-dark/{z}/{x}/{y}@2x.png?apikey=628502b3ae3a4c388efde8abb0577ca2" // TODO: env file

    init(_ updateTabBarApperance: @escaping () -> Void, _ changeTab: @escaping (Int) -> Void) {
        self.updateTabBarApperance = updateTabBarApperance
        self.changeTab = changeTab
        super.init(nibName: nil, bundle: nil)
        print("map view init")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        sheetViewController = MapBottomSheetView(sheetDismiss, changeTab)
        sheetNavController = UIHostingController(rootView: sheetViewController!)
        setupMapView()
        addLocationButton()
        addPoints()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        updateTabBarApperance()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if mapLoaded {
            mapView.removeOverlay(traitCollection.userInterfaceStyle == .dark ? tileLightOverlay! : tileDarkOverlay!)
            mapView.addOverlay(traitCollection.userInterfaceStyle == .dark ? tileDarkOverlay! : tileLightOverlay!)
        }
    }

    private func setupMapView() {
        mapView = MKMapView(frame: view.bounds)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.pointOfInterestFilter = .excludingAll
        mapView.delegate = self
        mapView.showsScale = true
        mapView.showsUserLocation = true
        mapView.region = defaultLocation
        mapView.mapType = .satellite
        mapView.userTrackingMode = .follow

        tileLightOverlay = MKTileOverlay(urlTemplate: sourceLightUrl)
        tileLightOverlay?.tileSize = .init(width: 512, height: 512)
        tileLightOverlay?.canReplaceMapContent = true
        tileDarkOverlay = MKTileOverlay(urlTemplate: sourceDarkUrl)
        tileDarkOverlay?.tileSize = .init(width: 512, height: 512)
        tileDarkOverlay?.canReplaceMapContent = true

        mapView.addOverlay(traitCollection.userInterfaceStyle == .dark ? tileDarkOverlay! : tileLightOverlay!)

        view.addSubview(mapView)

        mapLoaded = true

        mapView.register(
            StopAnnotationView.self,
            forAnnotationViewWithReuseIdentifier:
            MKMapViewDefaultAnnotationViewReuseIdentifier
        )

        mapView.register(
            ClusterAnnotationView.self,
            forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier
        )
    }

    private func addPoints() {
        DispatchQueue.global(qos: .userInitiated).async {
            let points = self.generatePoints()
            if points.isEmpty {
                sleep(1)
                self.addPoints()
            } else {
                DispatchQueue.main.async {
                    self.mapView.addAnnotations(points)
                }
            }
        }
    }

    private func generatePoints() -> [StopAnnotation] {
        // FIXME: what if stop are not fetched yet ?
        let points: [StopAnnotation] = stopListProvider.stops.map { stop in
            let pointAnnotation = StopAnnotation(latitude: stop.location.latitude, longitude: stop.location.longitude)
            pointAnnotation.title = stop.name
            pointAnnotation.subtitle = String(stop.id)
            return pointAnnotation
        }
        return points
    }

    private func presentBottomSheet() {
        if let sheet = sheetNavController?.sheetPresentationController {
            let customDent = UISheetPresentationController.Detent.custom(resolver: { context in 0.4 * context.maximumDetentValue })
            sheet.detents = [customDent, .large()]
            sheet.largestUndimmedDetentIdentifier = customDent.identifier
            sheet.prefersGrabberVisible = true
            sheet.delegate = self
        }
        if presented == nil {
            present(sheetNavController!, animated: true)
        }
    }

    func sheetDismiss() {
        sheetNavController!.dismiss(animated: true)
        mapView.deselectAnnotation(selectedAnnotation, animated: true)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        mapView.deselectAnnotation(selectedAnnotation, animated: true)
    }

    private func addLocationButton() {
        locationButton.clipsToBounds = true
        locationButton.configuration?.baseBackgroundColor = .clear
        locationButton.configuration?.background.visualEffect = UIBlurEffect(style: .systemMaterial)
        locationButton.configuration?.baseForegroundColor = .systemBlue
        locationButton.configuration?.contentInsets = NSDirectionalEdgeInsets(top: 16.0, leading: 16.0, bottom: 16.0, trailing: 16.0)

        locationButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(locationButton)

        locationButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20.0).isActive = true
        locationButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20.0).isActive = true

        updateButtonIcon()
        locationButton.addTarget(self, action: #selector(focusLocation), for: .touchUpInside)
    }

    private func updateButtonIcon() {
        locationButton.setImage(UIImage(systemName: mapView.userTrackingMode == .none ? "location" : "location.fill"), for: .normal)
    }

    @objc func focusLocation() {
        updateButtonIcon()
        if mapView.userTrackingMode == .none {
            mapView.setUserTrackingMode(.follow, animated: true)
        } else {
            mapView.userTrackingMode = .none
        }
    }

    func mapView(_ mapView: MKMapView, didChange mode: MKUserTrackingMode, animated: Bool) {
        updateButtonIcon()
    }

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        if view.annotation is MKUserLocation {
            // user location selected
        } else if view.annotation is MKClusterAnnotation {
            let coordinate = view.annotation?.coordinate
            let region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: coordinate!.latitude, longitude: coordinate!.longitude), span: MKCoordinateSpan(latitudeDelta: mapView.region.span.latitudeDelta * 0.6, longitudeDelta: mapView.region.span.longitudeDelta * 0.6))
            mapView.animatedZoom(region, 0.15)
            mapView.deselectAnnotation(view.annotation, animated: false)
        } else {
            selectedAnnotation = view.annotation
            GlobalController.virtualTable.changeStop(Int((view.annotation?.subtitle!)!) ?? 0)
            presentBottomSheet()
        }
    }

    func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
        selectedAnnotation = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if mapView.selectedAnnotations.count < 1 {
                self.sheetNavController!.dismiss(animated: true)
            }
        }
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        if overlay is MKTileOverlay {
            let renderer = MKTileOverlayRenderer(overlay: overlay)
            return renderer
        } else {
            return MKTileOverlayRenderer()
        }
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation {
            return nil
        } else if annotation is MKClusterAnnotation {
            return ClusterAnnotationView(annotation: annotation, reuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
        } else if annotation is StopAnnotation {
            guard let annotationView = mapView.dequeueReusableAnnotationView(withIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier) as? StopAnnotationView else {
                return StopAnnotationView(annotation: annotation, reuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier)
            }
            annotationView.annotation = annotation
            return annotationView
        } else {
            return MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier)
        }
    }
}

class StopAnnotation: MKPointAnnotation {
    init(latitude: Double, longitude: Double) {
        super.init()
        self.coordinate = CLLocationCoordinate2DMake(latitude, longitude)
    }
}

class StopAnnotationView: MKMarkerAnnotationView {
    override var annotation: MKAnnotation? {
        didSet {
            clusteringIdentifier = "stop"
            titleVisibility = .hidden
            subtitleVisibility = .hidden
        }
    }
}

class ClusterAnnotationView: MKMarkerAnnotationView {
    override var annotation: MKAnnotation? {
        didSet {
            displayPriority = .defaultHigh
            titleVisibility = .hidden
            subtitleVisibility = .hidden
            markerTintColor = nil
        }
    }
}
