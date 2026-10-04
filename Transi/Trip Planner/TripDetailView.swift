//
//  TripDetailView.swift
//  Transi
//
//  Created by magic_sk on 04/10/2026.
//

import Combine
import MapKit
import SwiftUI

/// A journey on a full-screen map, with its summary, steps and stops in a sheet.
struct TripDetailView: View {
    @StateObject private var model: TripDetailModel

    init(journey: Journey) {
        _model = StateObject(wrappedValue: TripDetailModel(journey: journey))
    }

    var body: some View {
        let parts = model.journey.parts ?? []
        TripDetailMap(model: model)
            .ignoresSafeArea()
            .navigationTitle(Text("\(parts.first?.startStopName ?? "Start") → \(parts.last?.endStopName ?? "End")"))
            .navigationBarTitleDisplayMode(.inline)
            .modifier(MapNavigationBar())
    }
}

/// iOS 26 floats glass buttons over the map; earlier versions get a material bar so the title stays legible.
private struct MapNavigationBar: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
        } else {
            content.toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

private struct TripDetailMap: UIViewControllerRepresentable {
    let model: TripDetailModel

    func makeUIViewController(context _: Context) -> TripDetailMapViewController {
        TripDetailMapViewController(model: model)
    }

    func updateUIViewController(_: TripDetailMapViewController, context _: Context) {}
}

/// Presents the sheet while the map is on screen and dismisses it when the user goes back or leaves the tab.
/// In a regular width (iPad, Mac) a sheet becomes a dimmed form sheet over the back button and the tab bar,
/// so its content floats in a panel beside the map instead.
final class TripDetailMapViewController: UIViewController, MKMapViewDelegate {
    private let model: TripDetailModel
    private let tiles = TransportTiles()
    private let mapView = MKMapView()
    private let sheet: UIHostingController<TripDetailSheet>
    private let panel = UIVisualEffectView()
    private var subscriptions = Set<AnyCancellable>()
    private var focus = MapFocus.route
    private var fittedLayout: FittedLayout?
    /// How much of the height the sheet covers at the medium detent, a little over half; measured once there.
    private var mediumSheetShare: CGFloat = 0.5
    private var isOnScreen = false

    /// What the route overview was last fitted to.
    private struct FittedLayout: Equatable {
        let safeArea: UIEdgeInsets
        let size: CGSize
        let panel: CGRect?
    }

    init(model: TripDetailModel) {
        self.model = model
        sheet = UIHostingController(rootView: TripDetailSheet(model: model))
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        mapView.frame = view.bounds
        mapView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mapView.delegate = self
        mapView.showsUserLocation = true
        mapView.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 48.145, longitude: 17.107),
            latitudinalMeters: 5000, longitudinalMeters: 5000
        )
        tiles.install(on: mapView, for: traitCollection.userInterfaceStyle)
        view.addSubview(mapView)

        sheet.isModalInPresentation = true
        if #available(iOS 26.0, *) {
            sheet.view.backgroundColor = .clear
            panel.effect = UIGlassEffect()
            panel.cornerConfiguration = .corners(radius: .fixed(26))
        } else {
            panel.effect = UIBlurEffect(style: .systemMaterial)
            panel.layer.cornerRadius = 16
            panel.layer.cornerCurve = .continuous
            panel.clipsToBounds = true
        }
        panel.isHidden = true
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)
        let width = panel.widthAnchor.constraint(equalToConstant: 380)
        width.priority = .defaultHigh
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            panel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 16),
            panel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            panel.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor, multiplier: 0.5),
            width,
        ])

        model.onFocus = { [weak self] in self?.focusMap(on: $0) }
        // @Published emits before the property changes, so draw the emitted journey.
        model.$journey.dropFirst().sink { [weak self] journey in
            guard let self else { return }
            self.drawRoute(journey)
            if self.focus == .route {
                self.focusMap(on: .route, in: journey, animated: false)
            }
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.model.stop() }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                if self?.viewIfLoaded?.window != nil { self?.model.start() }
            }
            .store(in: &subscriptions)
        drawRoute(model.journey)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Fit the overview again once the bars' safe area, the size or the panel is known.
        let layout = FittedLayout(
            safeArea: mapView.safeAreaInsets, size: view.bounds.size, panel: sheet.parent == nil ? nil : panel.frame
        )
        if focus == .route, view.bounds.height > 0, fittedLayout != layout {
            fittedLayout = layout
            focusMap(on: .route, in: model.journey, animated: false)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isOnScreen = true
        placeSheet(animated: animated)
        model.start()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isOnScreen = false
        model.stop()
        if sheet.presentingViewController != nil, !sheet.isBeingDismissed {
            dismissSheet(animated: animated)
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        if previousTraitCollection?.horizontalSizeClass != traitCollection.horizontalSizeClass {
            placeSheet(animated: false)
        }
        guard previousTraitCollection?.userInterfaceStyle != traitCollection.userInterfaceStyle else { return }
        tiles.update(mapView, for: traitCollection.userInterfaceStyle)
        drawRoute(model.journey)
    }

    // MARK: Sheet

    /// Presents the sheet in a compact width and embeds it in the panel in a regular one, while on screen.
    private func placeSheet(animated: Bool) {
        // A dismissal places it again when it ends.
        guard isOnScreen, !sheet.isBeingDismissed else { return }
        let isRegular = traitCollection.horizontalSizeClass == .regular
        if isRegular, sheet.presentingViewController != nil {
            dismissSheet(animated: false)
        } else if isRegular, sheet.parent == nil {
            addChild(sheet)
            sheet.view.frame = panel.contentView.bounds
            sheet.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            panel.contentView.addSubview(sheet.view)
            sheet.didMove(toParent: self)
            panel.isHidden = false
            view.setNeedsLayout()
        } else if !isRegular {
            if sheet.parent != nil {
                sheet.willMove(toParent: nil)
                sheet.view.removeFromSuperview()
                sheet.removeFromParent()
                panel.isHidden = true
                view.setNeedsLayout()
            }
            if sheet.presentingViewController == nil {
                presentSheet(animated: animated)
            }
        }
    }

    private func presentSheet(animated: Bool) {
        if let controller = sheet.sheetPresentationController {
            controller.detents = [.medium(), .large()]
            controller.largestUndimmedDetentIdentifier = .medium
            controller.prefersGrabberVisible = true
            // Come back to the map, whatever detent the sheet was left at.
            controller.selectedDetentIdentifier = .medium
        }
        present(sheet, animated: animated) { [weak self] in
            guard let self else { return }
            // Fit the overview to where the sheet really ends.
            let share = self.mediumSheetShare
            self.measureMediumSheet()
            if self.focus == .route, self.mediumSheetShare != share {
                self.focusMap(on: .route)
            }
        }
    }

    private func dismissSheet(animated: Bool) {
        sheet.dismiss(animated: animated) { [weak self] in
            // Shows it again after a cancelled back swipe, or in the panel after a switch to a regular width.
            self?.placeSheet(animated: true)
        }
    }

    // MARK: Route

    private func drawRoute(_ journey: Journey) {
        mapView.removeOverlays(mapView.overlays.filter { $0 is RoutePolyline })
        mapView.removeAnnotations(mapView.annotations.filter { $0 is TripStopAnnotation })
        let parts = journey.parts ?? []
        let casing = UIColor.systemBackground.resolvedColor(with: traitCollection)
        for (index, part) in parts.enumerated() {
            let coordinates = Self.coordinates(of: index, in: parts)
            if part.routeType == 64 {
                if coordinates.count > 1 {
                    mapView.addOverlay(
                        RoutePolyline.make(coordinates, color: .systemGray, width: 5, dashed: true), level: .aboveLabels
                    )
                }
                continue
            }
            let line = part.routeShortName ?? ""
            let color = UIColor(colorFromLineNum(line) ?? .gray)
            if coordinates.count > 1 {
                // The tiles sit at .aboveRoads.
                mapView.addOverlay(RoutePolyline.make(coordinates, color: casing, width: 9), level: .aboveLabels)
                mapView.addOverlay(RoutePolyline.make(coordinates, color: color, width: 5), level: .aboveLabels)
            }
            for stop in (part.stops ?? []).dropFirst().dropLast() {
                if let gps = stop.gps {
                    mapView.addAnnotation(TripStopAnnotation(dotAt: gps.coordinate, name: stop.name, color: color))
                }
            }
            let glyphColor = UIColor(textColorFromLineNum(line) ?? .white)
            if let gps = part.startStopGps {
                let name = part.startStopName ?? ""
                mapView.addAnnotation(TripStopAnnotation(
                    pinAt: gps.coordinate, name: name, platform: part.startStopCode, color: color, glyphColor: glyphColor,
                    spokenLabel: Self.platformLabel(
                        String(localized: "Board line \(line) at \(name)"), part.startStopCode
                    )
                ))
            }
            if let gps = part.endStopGps {
                let name = part.endStopName ?? ""
                mapView.addAnnotation(TripStopAnnotation(
                    pinAt: gps.coordinate, name: name, platform: part.endStopCode, color: color, glyphColor: glyphColor,
                    spokenLabel: Self.platformLabel(
                        String(localized: "Get off line \(line) at \(name)"), part.endStopCode
                    )
                ))
            }
        }
    }

    private static func platformLabel(_ label: String, _ platform: String?) -> String {
        platform.map { label + String(localized: ", platform \($0)") } ?? label
    }

    /// A ride's stops, or its two ends until they load; a walk from where the previous part ends to where
    /// the next one starts.
    private static func coordinates(of index: Int, in parts: [Part]) -> [CLLocationCoordinate2D] {
        let part = parts[index]
        if part.routeType != 64, let stops = part.stops?.compactMap(\.gps), stops.count > 1 {
            return stops.map(\.coordinate)
        }
        let start = part.startStopGps ?? (index > 0 ? parts[index - 1].endStopGps : nil)
        let end = part.endStopGps ?? (index + 1 < parts.count ? parts[index + 1].startStopGps : nil)
        return [start, end].compactMap { $0?.coordinate }
    }

    // MARK: Focus

    private func focusMap(on target: MapFocus) {
        focusMap(on: target, in: model.journey, animated: !UIAccessibility.isReduceMotionEnabled)
    }

    /// Fits `target` into the map beside the panel, or above the sheet after lowering it to the medium detent.
    private func focusMap(on target: MapFocus, in journey: Journey, animated: Bool) {
        focus = target
        let parts = journey.parts ?? []
        let coordinates: [CLLocationCoordinate2D]
        switch target {
        case .route:
            coordinates = parts.indices.flatMap { Self.coordinates(of: $0, in: parts) }
        case .part(let index):
            coordinates = Self.coordinates(of: index, in: parts)
        case .change(let index):
            // From the previous ride's end, or the journey's start when the walk opens it.
            let from = parts[..<index].lastIndex { $0.routeType != 64 }
            coordinates = ((from ?? 0) ... index).flatMap { partIndex -> [CLLocationCoordinate2D] in
                let points = Self.coordinates(of: partIndex, in: parts)
                if partIndex == from { return points.suffix(1) }
                return partIndex == index ? Array(points.prefix(1)) : points
            }
        case .stop(let gps):
            coordinates = [gps.coordinate]
        }
        guard let first = coordinates.first else { return }

        if sheet.presentingViewController != nil, let controller = sheet.sheetPresentationController {
            if controller.selectedDetentIdentifier == .large {
                if animated {
                    controller.animateChanges { controller.selectedDetentIdentifier = .medium }
                } else {
                    controller.selectedDetentIdentifier = .medium
                }
            } else if sheet.transitionCoordinator == nil {
                measureMediumSheet()
            }
        }
        var rect = coordinates.reduce(MKMapRect.null) { rect, coordinate in
            rect.union(MKMapRect(origin: MKMapPoint(coordinate), size: MKMapSize(width: 0, height: 0)))
        }
        // Keep at least ~300 m around a stop or a short change.
        let minimum = 300 * MKMapPointsPerMeterAtLatitude(first.latitude)
        rect = rect.insetBy(dx: -max(0, minimum - rect.width) / 2, dy: -max(0, minimum - rect.height) / 2)
        // MapKit adds the map's safe area (navigation and tab bars) to the padding. Room for the pins: the
        // marker rises about 30 pt above its stop and the name label hangs below it, centred.
        // ponytail: fits labels up to ~100 pt wide; measure the edge pins' titles if longer names clip.
        var insets = UIEdgeInsets(top: 40, left: 56, bottom: 36, right: 56)
        if sheet.parent != nil {
            // The panel covers the map's leading side.
            if panel.frame.midX < view.bounds.midX {
                insets.left += max(panel.frame.maxX - mapView.safeAreaInsets.left, 0)
            } else {
                insets.right += max(view.bounds.maxX - panel.frame.minX - mapView.safeAreaInsets.right, 0)
            }
        } else {
            // The sheet rests at the medium detent, a little over half the screen, and covers the tab bar.
            insets.bottom += max(view.bounds.height * mediumSheetShare - mapView.safeAreaInsets.bottom, 0)
        }
        mapView.setVisibleMapRect(rect, edgePadding: insets, animated: animated)
    }

    /// Call while the sheet rests at the medium detent.
    private func measureMediumSheet() {
        guard view.bounds.height > 0 else { return }
        let top = view.convert(sheet.view.bounds, from: sheet.view).minY
        mediumSheetShare = (view.bounds.maxY - top) / view.bounds.height
    }

    // MARK: MKMapViewDelegate

    func mapView(_: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
        guard let line = overlay as? RoutePolyline else { return TileOverlayRenderer(overlay: overlay) }
        let renderer = MKPolylineRenderer(polyline: line)
        renderer.strokeColor = line.color
        renderer.lineWidth = line.width
        renderer.lineCap = .round
        renderer.lineJoin = .round
        if line.isDashed {
            renderer.lineDashPattern = [0.5, 9]
        }
        return renderer
    }

    func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
        guard let stop = annotation as? TripStopAnnotation else { return nil }
        guard stop.isPin else {
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: "dot")
                ?? MKAnnotationView(annotation: stop, reuseIdentifier: "dot")
            view.annotation = stop
            view.image = Self.dot(stop.color, fill: UIColor.systemBackground.resolvedColor(with: traitCollection))
            view.displayPriority = .defaultHigh
            view.collisionMode = .circle
            view.zPriority = .min
            // The sheet lists every stop; VoiceOver only visits the pins.
            view.isAccessibilityElement = false
            view.accessibilityElementsHidden = true
            return view
        }
        let view = mapView.dequeueReusableAnnotationView(withIdentifier: "pin") as? MKMarkerAnnotationView
            ?? MKMarkerAnnotationView(annotation: stop, reuseIdentifier: "pin")
        view.annotation = stop
        view.markerTintColor = stop.color
        view.glyphTintColor = stop.glyphColor
        view.glyphText = stop.platform
        view.displayPriority = .required
        view.zPriority = .max
        view.accessibilityLabel = stop.spokenLabel
        return view
    }

    private static func dot(_ color: UIColor, fill: UIColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10)).image { _ in
            let circle = UIBezierPath(ovalIn: CGRect(x: 1, y: 1, width: 8, height: 8))
            fill.setFill()
            circle.fill()
            color.setStroke()
            circle.lineWidth = 2
            circle.stroke()
        }
    }
}

private final class RoutePolyline: MKPolyline {
    private(set) var color = UIColor.systemGray
    private(set) var width: CGFloat = 5
    private(set) var isDashed = false

    static func make(
        _ coordinates: [CLLocationCoordinate2D], color: UIColor, width: CGFloat, dashed: Bool = false
    ) -> RoutePolyline {
        let line = RoutePolyline(coordinates: coordinates, count: coordinates.count)
        line.color = color
        line.width = width
        line.isDashed = dashed
        return line
    }
}

/// A pin labelled with the platform letter where a ride starts or ends, or a dot for a stop in between.
private final class TripStopAnnotation: MKPointAnnotation {
    let isPin: Bool
    let platform: String?
    let color: UIColor
    let glyphColor: UIColor
    let spokenLabel: String?

    init(
        pinAt coordinate: CLLocationCoordinate2D, name: String, platform: String?, color: UIColor,
        glyphColor: UIColor, spokenLabel: String
    ) {
        isPin = true
        self.platform = platform
        self.color = color
        self.glyphColor = glyphColor
        self.spokenLabel = spokenLabel
        super.init()
        self.coordinate = coordinate
        title = name
    }

    init(dotAt coordinate: CLLocationCoordinate2D, name: String, color: UIColor) {
        isPin = false
        platform = nil
        self.color = color
        glyphColor = color
        spokenLabel = nil
        super.init()
        self.coordinate = coordinate
        title = name
    }
}

extension StopGps {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
