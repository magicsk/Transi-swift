//
//  MapKitView.swift
//  Transi
//
//  Created by magic_sk on 18/11/2023.
//

import Combine
import MapCache
import MapKit
import SwiftUI
import UIKit

struct MapKitView: UIViewControllerRepresentable {
    private let changeTab: (Int) -> Void

    init(_ changeTab: @escaping (Int) -> Void) {
        self.changeTab = changeTab
    }

    func makeUIViewController(context _: Context) -> MapViewController {
        return MapViewController(changeTab)
    }

    func updateUIViewController(_: MapViewController, context _: Context) {}
}

class MapViewController: UIViewController, MKMapViewDelegate, UISheetPresentationControllerDelegate,
    UISceneDelegate
{
    let stopListProvider = GlobalController.stopsListProvider
    let appState = GlobalController.appState
    private let tiles = TransportTiles()
    private var sheetViewController: MapBottomSheetView?
    private var sheetNavController: UIHostingController<MapBottomSheetView>?
    private var mapView: MKMapView!
    private let changeTab: (Int) -> Void
    private var subscription: Cancellable?
    private var stopIdFromUrl: String?

    private var mapLoaded = false
    private var selectedAnnotation: MKAnnotation?
    private let defaultLocation = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 48.145, longitude: 17.107), latitudinalMeters: 500,
        longitudinalMeters: 500
    )
    private lazy var locationButton = UIButton(configuration: .filled())

    init(_ changeTab: @escaping (Int) -> Void) {
        self.changeTab = changeTab

        super.init(nibName: nil, bundle: nil)
        #if DEBUG
        print("map view init")
        #endif
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
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
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if mapLoaded {
            tiles.update(mapView, for: traitCollection.userInterfaceStyle)
        }
    }

    private func setupMapView() {
        mapView = MKMapView(frame: view.bounds)
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.delegate = self
        mapView.showsScale = true
        mapView.showsUserLocation = true
        mapView.region = defaultLocation
        mapView.userTrackingMode = .follow
        tiles.install(on: mapView, for: traitCollection.userInterfaceStyle)

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
                DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + 1) {
                    self.addPoints()
                }
            } else {
                DispatchQueue.main.sync {
                    self.mapView.addAnnotations(points)
                }
                self.subscription = self.appState.$openedURL.sink { optionalUrl in
                    if let url = optionalUrl {
                        if url.host == "map" {
                            if let stopId = Int(url.pathComponents[1]) {
                                if !self.mapView.annotations.isEmpty {
                                    if let foundStop = self.mapView.annotations.first(where: { annotation in
                                        annotation.subtitle == stopId.description
                                    }) {
                                        DispatchQueue.main.async {
                                            self.mapView.selectAnnotation(foundStop, animated: true)
                                            let region = MKCoordinateRegion(
                                                center: foundStop.coordinate, latitudinalMeters: 500,
                                                longitudinalMeters: 500
                                            )
                                            self.mapView.animatedZoom(region, 1.0)
                                        }
                                    }
                                }
                            }
                            self.appState.openedURL = nil
                        }
                    }
                }
            }
        }
    }

    private func generatePoints() -> [StopAnnotation] {
        let points: [StopAnnotation] = stopListProvider.stops.map { stop in
            let pointAnnotation = StopAnnotation(
                latitude: stop.location.latitude, longitude: stop.location.longitude
            )
            pointAnnotation.title = stop.name
            pointAnnotation.subtitle = String(stop.id)
            return pointAnnotation
        }
        return points
    }

    private func presentBottomSheet() {
        if let sheet = sheetNavController?.sheetPresentationController {
            let customDent = UISheetPresentationController.Detent.custom(resolver: { context in
                0.4 * context.maximumDetentValue
            })
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

    func presentationControllerDidDismiss(_: UIPresentationController) {
        mapView.deselectAnnotation(selectedAnnotation, animated: true)
    }

    private func addLocationButton() {
        locationButton.clipsToBounds = true
        locationButton.configuration?.baseBackgroundColor = .clear
        if #available(iOS 26.0, *) {
            locationButton.configuration?.background.visualEffect = UIGlassEffect(style: .regular)
            locationButton.configuration?.background.cornerRadius = 100.0
            locationButton.configuration?.contentInsets = NSDirectionalEdgeInsets(
                top: 22.0, leading: 22.0, bottom: 22.0, trailing: 22.0
            )
        } else {
            locationButton.configuration?.background.visualEffect = UIBlurEffect(style: .systemMaterial)
            locationButton.configuration?.contentInsets = NSDirectionalEdgeInsets(
                top: 16.0, leading: 16.0, bottom: 16.0, trailing: 16.0
            )
        }
        locationButton.configuration?.baseForegroundColor = .accent

        locationButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(locationButton)

        if #available(iOS 26.0, *) {
            locationButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -26.0)
                .isActive = true
        } else {
            locationButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20.0)
                .isActive = true
        }
        locationButton.bottomAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -20.0
        ).isActive = true

        updateButtonIcon()
        locationButton.addTarget(self, action: #selector(focusLocation), for: .touchUpInside)
    }

    private func updateButtonIcon() {
        locationButton.setImage(
            UIImage(systemName: mapView.userTrackingMode == .none ? "location" : "location.fill"),
            for: .normal
        )
    }

    @objc func focusLocation() {
        updateButtonIcon()
        if mapView.userTrackingMode == .none {
            mapView.setUserTrackingMode(.follow, animated: true)
        } else {
            mapView.userTrackingMode = .none
        }
    }

    func mapView(_: MKMapView, didChange _: MKUserTrackingMode, animated _: Bool) {
        updateButtonIcon()
    }

    func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
        if view.annotation is MKUserLocation {
            // user location selected
        } else if view.annotation is MKClusterAnnotation {
            let coordinate = view.annotation?.coordinate
            let region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(
                    latitude: coordinate!.latitude, longitude: coordinate!.longitude
                ),
                span: MKCoordinateSpan(
                    latitudeDelta: mapView.region.span.latitudeDelta * 0.6,
                    longitudeDelta: mapView.region.span.longitudeDelta * 0.6
                )
            )
            mapView.animatedZoom(region, 0.15)
            mapView.deselectAnnotation(view.annotation, animated: false)
        } else {
            selectedAnnotation = view.annotation
            GlobalController.virtualTable.changeStop(Int((view.annotation?.subtitle!)!) ?? 0)
            presentBottomSheet()
        }
    }

    func mapView(_ mapView: MKMapView, didDeselect _: MKAnnotationView) {
        selectedAnnotation = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if mapView.selectedAnnotations.count < 1 {
                self.sheetNavController!.dismiss(animated: true)
            }
        }
    }

    func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        return TileOverlayRenderer(overlay: overlay)
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        if annotation is MKUserLocation {
            return nil
        } else if annotation is MKClusterAnnotation {
            return ClusterAnnotationView(
                annotation: annotation,
                reuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier
            )
        } else if annotation is StopAnnotation {
            guard
                let annotationView = mapView.dequeueReusableAnnotationView(
                    withIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier) as? StopAnnotationView
            else {
                return StopAnnotationView(
                    annotation: annotation, reuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier
                )
            }
            annotationView.annotation = annotation
            return annotationView
        } else {
            return MKMarkerAnnotationView(
                annotation: annotation, reuseIdentifier: MKMapViewDefaultAnnotationViewReuseIdentifier
            )
        }
    }
}

class StopAnnotation: MKPointAnnotation {
    init(latitude: Double, longitude: Double) {
        super.init()
        coordinate = CLLocationCoordinate2DMake(latitude, longitude)
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

/// Thunderforest transport tiles drawn instead of Apple's map, swapped for the dark style in dark mode.
final class TransportTiles {
    private let light = TransportTiles.overlay(style: "transport")
    private let dark = TransportTiles.overlay(style: "transport-dark")

    func install(on mapView: MKMapView, for style: UIUserInterfaceStyle) {
        mapView.pointOfInterestFilter = .excludingAll
        mapView.mapType = .satellite
        // MapKit stops drawing overlays at its own closest zoom (~3.2 m camera distance).
        mapView.cameraZoomRange = MKMapView.CameraZoomRange(minCenterCoordinateDistance: 4)
        update(mapView, for: style)
    }

    /// Shows the tiles for `style` at the `.aboveRoads` level, so overlays at `.aboveLabels` draw on top.
    /// Render them with `TileOverlayRenderer`.
    func update(_ mapView: MKMapView, for style: UIUserInterfaceStyle) {
        let (shown, hidden) = style == .dark ? (dark, light) : (light, dark)
        mapView.removeOverlay(hidden)
        if !mapView.overlays.contains(where: { $0 === shown }) {
            mapView.insertOverlay(shown, at: 0, level: .aboveRoads)
        }
    }

    private static func overlay(style: String) -> MKTileOverlay {
        let url = "\(GlobalController.thunderforestApiUrl)/\(style)/{z}/{x}/{y}@2x.png?apikey=\(GlobalController.thunderforestApiKey)"
        let overlay = CachedTileOverlay(withCache: MapCache(withConfig: MapCacheConfig(withUrlTemplate: url)))
        overlay.tileSize = .init(width: 512, height: 512)
        overlay.canReplaceMapContent = true
        overlay.maximumZ = 22
        return overlay
    }
}

class TileOverlayRenderer: MKTileOverlayRenderer {
    private typealias Tile = (path: MKTileOverlayPath, rect: MKMapRect, key: NSString)

    private let images: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 100 // ponytail: ~1 MB per decoded tile, use totalCostLimit if memory shows up
        return cache
    }()

    private let loadingLock = NSLock()
    private var loading = Set<NSString>()

    override func canDraw(_ mapRect: MKMapRect, zoomScale: MKZoomScale) -> Bool {
        let tiles = tiles(for: mapRect, zoomScale)
        if let tile = tiles.first, images.object(forKey: tile.key) == nil { load(tile) }
        return tiles.contains { images.object(forKey: $0.key) != nil }
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let (tile, image) = tiles(for: mapRect, zoomScale).lazy
            .compactMap({ tile in self.images.object(forKey: tile.key).map { (tile, $0) } }).first
        else { return }
        context.saveGState()
        context.clip(to: rect(for: mapRect))
        UIGraphicsPushContext(context)
        image.draw(in: rect(for: tile.rect))
        UIGraphicsPopContext()
        context.restoreGState()
    }

    // MapKit asks for one tile per mapRect at z = log2(world width * zoomScale / tileSize)
    // (measured: zoomScale 8 -> z22 with 512 pt tiles). Returns that tile, capped at maximumZ,
    // followed by its ancestors, which are drawn upscaled until a sharper tile is loaded.
    private func tiles(for mapRect: MKMapRect, _ zoomScale: MKZoomScale) -> [Tile] {
        guard let overlay = overlay as? MKTileOverlay else { return [] }
        let z = Int(log2(MKMapSize.world.width * Double(zoomScale) / Double(overlay.tileSize.width)).rounded())
        return stride(from: min(z, overlay.maximumZ), through: overlay.minimumZ, by: -1).map { z in
            let size = MKMapSize.world.width / pow(2, Double(z))
            let x = Int(mapRect.midX / size), y = Int(mapRect.midY / size)
            return (
                MKTileOverlayPath(x: x, y: y, z: z, contentScaleFactor: contentScaleFactor),
                MKMapRect(x: Double(x) * size, y: Double(y) * size, width: size, height: size),
                "\(z)/\(x)/\(y)" as NSString
            )
        }
    }

    private func load(_ tile: Tile) {
        guard let overlay = overlay as? MKTileOverlay,
              loadingLock.withLock({ loading.insert(tile.key).inserted })
        else { return }
        overlay.loadTile(at: tile.path) { [weak self] data, _ in
            guard let self = self else { return }
            let image = data.flatMap { UIImage(data: $0) }
            if let image = image { self.images.setObject(image, forKey: tile.key) }
            self.loadingLock.withLock { _ = self.loading.remove(tile.key) }
            if image != nil { self.setNeedsDisplay(tile.rect) }
        }
    }
}
