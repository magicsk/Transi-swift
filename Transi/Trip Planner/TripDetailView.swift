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

    func updateUIViewController(_ controller: TripDetailMapViewController, context: Context) {
        controller.goBack = context.environment.dismiss
    }
}

/// Presents the sheet while the map is on screen and dismisses it when the user goes back or leaves the tab.
/// In a regular width (iPad, Mac) a sheet becomes a dimmed form sheet over the back button and the tab bar,
/// so its content floats in a panel beside the map instead.
final class TripDetailMapViewController: UIViewController, MKMapViewDelegate, UISheetPresentationControllerDelegate,
    UIGestureRecognizerDelegate
{
    private typealias Detent = UISheetPresentationController.Detent

    private let model: TripDetailModel
    private let tiles = TransportTiles()
    private let mapView = MKMapView()
    private let sheet: UIHostingController<TripDetailSheet>
    private let panel = UIVisualEffectView()
    private let followButton = UIButton(configuration: .filled())
    private var subscriptions = Set<AnyCancellable>()
    /// What the map was last fitted to; nil once the user moved it.
    private var focus: MapFocus? = .route
    private var fittedLayout: FittedLayout?
    /// The focused stop, selected on the map.
    private weak var highlightedStop: TripStopAnnotation?
    /// The medium detent's height, as last resolved.
    private var mediumDetentHeight: CGFloat?
    /// What the sheet covers below its detent's height: the home indicator's safe area, or the margin under
    /// iOS 26's floating sheet. Measured once the sheet rests.
    private var sheetMargin: CGFloat?
    /// The part of `sheetMargin` the sheet's content shows in: none of the margin under a floating sheet.
    private var sheetContentMargin: CGFloat?
    /// The summary's frame in the sheet as last reported, and its top where it last came to rest in view.
    private var summaryFrame = CGRect.zero
    private var summaryTop: CGFloat?
    /// Takes the summary's next position at once: before it was first measured, when the sheet comes up and when
    /// the text size changes. Otherwise it counts once the summary stops moving.
    private var remeasuresSummary = true
    private let summaryMoves = PassthroughSubject<Void, Never>()
    private var following = Following.off {
        didSet { followButton.isHidden = following != .paused }
    }

    private var isOnScreen = false
    private let backSwipe = UIPanGestureRecognizer()
    /// Pops this journey off the planner's navigation path.
    var goBack: DismissAction?
    /// Places the sheet once another modal lets it come up.
    private var sheetRetry: DispatchWorkItem?

    /// While the trip Live Activity follows this journey, the map follows its step until the user moves the map
    /// or picks something to show.
    private enum Following {
        case off, on, paused
    }

    /// The layout the map was last fitted in.
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

        setUpFollowing()
        model.onFocus = { [weak self] target in
            self?.pauseFollowing()
            self?.focusMap(on: target, lowering: .medium)
        }
        model.onSummaryFrame = { [weak self] in self?.summaryMoved($0) }
        // At rest once the list stops scrolling it and the sheet's drag stops shifting the list's inset.
        summaryMoves.debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] in self?.summaryRested() }
            .store(in: &subscriptions)
        // @Published emits before the property changes, so draw the emitted journey.
        model.$journey.dropFirst().sink { [weak self] journey in
            guard let self else { return }
            self.drawRoute(journey)
            if self.focus == .route {
                self.focusMap(on: .route, in: journey, animated: false)
            }
        }.store(in: &subscriptions)
        GlobalController.tripLiveActivity.$progress.dropFirst()
            .sink { [weak self] in self?.followTrip($0) }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)
            .sink { [weak self] _ in self?.model.stop() }
            .store(in: &subscriptions)
        NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in
                guard let self, self.viewIfLoaded?.window != nil else { return }
                self.model.start()
                self.resumeFollowing()
            }
            .store(in: &subscriptions)
        drawRoute(model.journey)
    }

    /// The user moving the map pauses following the trip, and a button resumes it.
    private func setUpFollowing() {
        let doubleTap = UITapGestureRecognizer()
        doubleTap.numberOfTapsRequired = 2
        let twoFingerTap = UITapGestureRecognizer()
        twoFingerTap.numberOfTouchesRequired = 2
        for gesture in [UIPanGestureRecognizer(), UIPinchGestureRecognizer(), UIRotationGestureRecognizer(),
                        doubleTap, twoFingerTap]
        {
            gesture.addTarget(self, action: #selector(userMovedMap(_:)))
            gesture.cancelsTouchesInView = false
            gesture.delaysTouchesEnded = false
            gesture.delegate = self
            mapView.addGestureRecognizer(gesture)
        }

        var configuration = UIButton.Configuration.filled()
        configuration.title = String(localized: "Follow trip")
        configuration.image = UIImage(systemName: "location.fill")
        configuration.imagePadding = 6
        configuration.buttonSize = .large
        configuration.cornerStyle = .capsule
        configuration.baseBackgroundColor = .clear
        configuration.baseForegroundColor = .accent
        if #available(iOS 26.0, *) {
            configuration.background.visualEffect = UIGlassEffect(style: .regular)
        } else {
            configuration.background.visualEffect = UIBlurEffect(style: .systemMaterial)
        }
        followButton.configuration = configuration
        followButton.accessibilityHint = String(localized: "Keeps the trip's current step in view")
        followButton.addTarget(self, action: #selector(resumeFollowing), for: .touchUpInside)
        followButton.isHidden = true
        followButton.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(followButton)
        // MapKit's compass sits where the button goes, so the button goes below a compass placed here.
        mapView.showsCompass = false
        let compass = MKCompassButton(mapView: mapView)
        compass.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(compass)
        NSLayoutConstraint.activate([
            compass.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 12),
            compass.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            followButton.topAnchor.constraint(equalTo: compass.bottomAnchor, constant: 8),
            followButton.trailingAnchor.constraint(equalTo: compass.trailingAnchor),
            followButton.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 16
            ),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Fit the map again once the bars' safe area, the size or the panel is known, and when it changes.
        let layout = FittedLayout(
            safeArea: mapView.safeAreaInsets, size: view.bounds.size, panel: sheet.parent == nil ? nil : panel.frame
        )
        guard view.bounds.height > 0, fittedLayout != layout else { return }
        fittedLayout = layout
        if let focus {
            focusMap(on: focus, in: model.journey, animated: false)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        isOnScreen = true
        setUpBackSwipe()
        // Before the sheet comes up, so it comes up at the summary while the trip is followed.
        followTrip(GlobalController.tripLiveActivity.progress)
        resumeFollowing()
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
        if previousTraitCollection?.preferredContentSizeCategory != traitCollection.preferredContentSizeCategory {
            remeasuresSummary = true
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
        // UIKit refuses to present over another modal, as when the trip's Live Activity opens this over another
        // journey's detail going away, another tab's sheet or an alert. Place the sheet again once one coming up or
        // going away has, and check again shortly while one stays up; placing stops once the map is off screen.
        if let other = view.window?.rootViewController?.presentedViewController, other !== sheet {
            sheetRetry?.cancel()
            let retry = DispatchWorkItem { [weak self] in self?.placeSheet(animated: animated) }
            sheetRetry = retry
            let waitsForTransition = other.transitionCoordinator?.animate(alongsideTransition: nil) { _ in
                DispatchQueue.main.async(execute: retry)
            } ?? false
            if !waitsForTransition {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: retry)
            }
            return
        }
        if let controller = sheet.sheetPresentationController {
            controller.detents = [
                .custom(identifier: .summary) { [weak self] in self?.summaryDetentHeight(in: $0) },
                .medium(),
                .large(),
            ]
            controller.largestUndimmedDetentIdentifier = .medium
            controller.prefersGrabberVisible = true
            controller.delegate = self
            // Come back to the map, whatever detent the sheet was left at; above the summary while following.
            controller.selectedDetentIdentifier = following == .off ? .medium : .summary
        }
        remeasuresSummary = true
        summaryRested()
        if let focus {
            focusMap(on: focus, in: model.journey, animated: false)
        }
        present(sheet, animated: animated) { [weak self] in
            guard let self else { return }
            // Selected here, the summary detent tells the delegate nothing: show the summary, not the rows the list
            // was left scrolled to.
            if self.sheetDetent == .summary {
                self.revealSummary()
            }
            // Fit the map to where the sheet really ends.
            guard self.measureSheet(), let focus = self.focus else { return }
            self.focusMap(on: focus)
        }
    }

    /// The detent the sheet rests at, or comes up at.
    private var sheetDetent: Detent.Identifier {
        guard sheet.presentingViewController != nil, let controller = sheet.sheetPresentationController else {
            return following == .off ? .medium : .summary
        }
        // None selected is the smallest.
        return controller.selectedDetentIdentifier ?? .summary
    }

    private func summaryDetentHeight(in context: UISheetPresentationControllerDetentResolutionContext) -> CGFloat {
        let medium = Detent.medium().resolvedValue(in: context) ?? context.maximumDetentValue / 2
        mediumDetentHeight = medium
        return summaryDetentHeight(medium: medium)
    }

    /// Down to the end of the summary at the top of the sheet; a step below the medium detent at the largest text
    /// sizes. Detent heights leave out the sheet's margin below them.
    private func summaryDetentHeight(medium: CGFloat) -> CGFloat {
        // Until the summary is laid out, about where it ends.
        let summaryEnd = summaryTop.map { $0 + summaryFrame.height + 12 } ?? medium / 2
        return min(summaryEnd - (sheetContentMargin ?? sheetMarginOrGuess), medium * 0.8)
    }

    private var sheetMarginOrGuess: CGFloat {
        sheetMargin ?? view.window?.safeAreaInsets.bottom ?? 0
    }

    /// How far the sheet reaches up from the bottom at the summary or medium detent.
    private func sheetHeight(at detent: Detent.Identifier) -> CGFloat {
        guard let medium = mediumDetentHeight else {
            // Before the sheet is first laid out: the medium detent is a little over half the screen.
            return view.bounds.height * (detent == .medium ? 0.5 : 0.25)
        }
        return (detent == .medium ? medium : summaryDetentHeight(medium: medium)) + sheetMarginOrGuess
    }

    /// Call while the sheet rests. True when its margin changed, which moves the summary detent.
    private func measureSheet() -> Bool {
        let detent = sheetDetent
        guard detent != .large, let medium = mediumDetentHeight, view.bounds.height > 0,
              let controller = sheet.sheetPresentationController
        else { return false }
        let frame = view.convert(sheet.view.bounds, from: sheet.view)
        let height = detent == .medium ? medium : summaryDetentHeight(medium: medium)
        let margin = view.bounds.maxY - frame.minY - height
        // A floating sheet shows its content down to its own bottom, above the screen's.
        let contentMargin = min(frame.maxY, view.bounds.maxY) - frame.minY - height
        guard abs(margin - (sheetMargin ?? .infinity)) >= 1
            || abs(contentMargin - (sheetContentMargin ?? .infinity)) >= 1
        else { return false }
        sheetMargin = margin
        sheetContentMargin = contentMargin
        animateSheet(controller) { controller.invalidateDetents() }
        return true
    }

    /// The summary moved in the list or changed its height; `frame` is in the window. A new height moves the summary
    /// detent at once, a new top once the summary comes to rest there.
    private func summaryMoved(_ frame: CGRect) {
        let end = summaryEnd
        // Relative to the sheet's top as it is now, which moved with the summary.
        summaryFrame = frame.offsetBy(dx: 0, dy: -sheet.view.convert(CGPoint.zero, to: nil).y)
        if remeasuresSummary {
            summaryRested()
        } else {
            resizeSummaryDetent(from: end)
            summaryMoves.send()
        }
    }

    /// Ends the summary detent below the summary where it is now, when it is in view: a reveal scrolls away the
    /// space above it, and a smaller text size moves it up. The list's top inset may differ at the large detent,
    /// which never shows just the summary.
    private func summaryRested() {
        guard summaryFrame.height > 0, summaryFrame.minY >= 0, remeasuresSummary || sheetDetent != .large else {
            return
        }
        remeasuresSummary = false
        let end = summaryEnd
        summaryTop = summaryFrame.minY
        resizeSummaryDetent(from: end)
    }

    private var summaryEnd: CGFloat? {
        summaryTop.map { $0 + summaryFrame.height }
    }

    /// Moves the summary detent when the summary's end moved from `end`.
    private func resizeSummaryDetent(from end: CGFloat?) {
        guard summaryEnd != end, sheet.presentingViewController != nil,
              let controller = sheet.sheetPresentationController
        else { return }
        animateSheet(controller) { controller.invalidateDetents() }
        if sheetDetent == .summary, let focus {
            focusMap(on: focus)
        }
    }

    /// Scrolls the list back to the summary once the sheet comes down to it.
    private func revealSummary() {
        if let summaryTop, summaryFrame.minY < summaryTop - 1 {
            model.showSummary.send()
        }
    }

    private func animateSheet(_ controller: UISheetPresentationController, _ changes: @escaping () -> Void) {
        if UIAccessibility.isReduceMotionEnabled {
            changes()
        } else {
            controller.animateChanges(changes)
        }
    }

    func sheetPresentationControllerDidChangeSelectedDetentIdentifier(_ controller: UISheetPresentationController) {
        if controller.selectedDetentIdentifier == .summary {
            revealSummary()
        }
        // Fit the map above where the user left the sheet.
        if let focus {
            focusMap(on: focus)
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
                // A journey that starts or ends on foot has no platform pin there.
                if index == 0, let gps = part.startStopGps {
                    let name = part.startStopName ?? ""
                    mapView.addAnnotation(TripStopAnnotation(
                        pinAt: gps.coordinate, name: name, platform: nil, glyph: UIImage(systemName: "figure.walk"),
                        color: .systemGray, glyphColor: .white, spokenLabel: String(localized: "Start, \(name)")
                    ))
                }
                if index == parts.count - 1, let gps = part.endStopGps {
                    let name = part.endStopName ?? ""
                    mapView.addAnnotation(TripStopAnnotation(
                        pinAt: gps.coordinate, name: name, platform: nil, glyph: UIImage(systemName: "flag.fill"),
                        color: .systemGray, glyphColor: .white, spokenLabel: String(localized: "Destination, \(name)")
                    ))
                }
                continue
            }
            let line = part.routeShortName ?? ""
            let color = UIColor(colorFromLineNum(line) ?? .gray)
            // Where a stop has no platform letter, as at train stations.
            let vehicle = UIImage(
                systemName: isTrain(line) ? "train.side.front.car" : isRounded(line) ? "tram.fill" : "bus.fill"
            )
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
                    pinAt: gps.coordinate, name: name, platform: part.startStopCode,
                    glyph: part.startStopCode == nil ? vehicle : nil, color: color, glyphColor: glyphColor,
                    spokenLabel: Self.platformLabel(
                        String(localized: "Board line \(line) at \(name)"), part.startStopCode
                    )
                ))
            }
            if let gps = part.endStopGps {
                let name = part.endStopName ?? ""
                mapView.addAnnotation(TripStopAnnotation(
                    pinAt: gps.coordinate, name: name, platform: part.endStopCode,
                    glyph: part.endStopCode == nil ? vehicle : nil, color: color, glyphColor: glyphColor,
                    spokenLabel: Self.platformLabel(
                        String(localized: "Get off line \(line) at \(name)"), part.endStopCode
                    )
                ))
            }
        }
        highlightFocusedStop()
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

    private func focusMap(on target: MapFocus, lowering detent: Detent.Identifier? = nil) {
        focusMap(on: target, in: model.journey, animated: !UIAccessibility.isReduceMotionEnabled, lowering: detent)
    }

    /// Fits `target` into the map beside the panel or above the sheet, after lowering the sheet to `detent` when
    /// it is higher. While the large sheet covers the map, the map is fitted once the sheet comes down.
    private func focusMap(
        on target: MapFocus, in journey: Journey, animated: Bool, lowering detent: Detent.Identifier? = nil
    ) {
        focus = target
        highlightFocusedStop()
        let parts = journey.parts ?? []
        let coordinates: [CLLocationCoordinate2D]
        switch target {
        case .route:
            coordinates = parts.indices.flatMap { Self.coordinates(of: $0, in: parts) }
        case .part(let index):
            // A walk goes on through the walks after it, as to the destination's pin.
            let last = parts[index].routeType == 64
                ? (parts[index...].firstIndex { $0.routeType != 64 } ?? parts.count) - 1 : index
            coordinates = (index ... last).flatMap { Self.coordinates(of: $0, in: parts) }
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
        case .stretch(let stops):
            coordinates = stops.map(\.coordinate)
        }
        guard let first = coordinates.first else { return }

        var restingDetent = sheetDetent
        if let detent, Self.rank(detent) < Self.rank(restingDetent), sheet.presentingViewController != nil,
           let controller = sheet.sheetPresentationController
        {
            if animated {
                controller.animateChanges { controller.selectedDetentIdentifier = detent }
            } else {
                controller.selectedDetentIdentifier = detent
            }
            restingDetent = detent
            if detent == .summary {
                revealSummary()
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
            guard restingDetent != .large else { return }
            // The sheet covers the tab bar.
            insets.bottom += max(sheetHeight(at: restingDetent) - mapView.safeAreaInsets.bottom, 0)
        }
        mapView.setVisibleMapRect(rect, edgePadding: insets, animated: animated)
    }

    private static func rank(_ detent: Detent.Identifier) -> Int {
        detent == .summary ? 0 : detent == .medium ? 1 : 2
    }

    /// Selects the pin or dot of the stop picked in the sheet, once MapKit shows it, and deselects it once the
    /// map shows something else.
    private func highlightFocusedStop() {
        var stop: TripStopAnnotation?
        if case .stop(let gps) = focus {
            // The sheet's stop lists and the journey's ends may place a stop a few metres apart.
            let point = MKMapPoint(gps.coordinate)
            stop = mapView.annotations.lazy.compactMap { $0 as? TripStopAnnotation }
                .map { ($0, MKMapPoint($0.coordinate).distance(to: point)) }
                .filter { $0.1 < 30 }
                .min { $0.1 < $1.1 }?.0
        }
        let animated = !UIAccessibility.isReduceMotionEnabled
        if let highlightedStop, highlightedStop !== stop {
            mapView.deselectAnnotation(highlightedStop, animated: animated)
        }
        highlightedStop = stop
        if let stop, !mapView.selectedAnnotations.contains(where: { $0 === stop }) {
            mapView.selectAnnotation(stop, animated: animated)
        }
    }

    // MARK: Following

    /// The trip's step on the map while the Live Activity follows this journey.
    private func followTarget(_ progress: TripProgress?) -> MapFocus? {
        let trip = GlobalController.tripLiveActivity
        guard let progress, let journey = trip.journey, journey == model.journey else { return nil }
        return progress.mapFocus(on: journey)
    }

    /// Follows the trip as it progresses, from above the summary once it starts, and shows the route once it ends
    /// unless the user was looking elsewhere. `progress` is the trip's, emitted before the controller holds it.
    private func followTrip(_ progress: TripProgress?) {
        guard let target = followTarget(progress) else {
            if following == .on, focus != .route {
                focusMap(on: .route)
            }
            following = .off
            return
        }
        switch following {
        case .off:
            following = .on
            focusMap(on: target, lowering: .summary)
        case .on where target != focus:
            focusMap(on: target)
        case .on, .paused:
            break
        }
    }

    private func pauseFollowing() {
        if following == .on {
            following = .paused
        }
    }

    @objc private func resumeFollowing() {
        guard following == .paused, let target = followTarget(GlobalController.tripLiveActivity.progress) else {
            return
        }
        following = .on
        focusMap(on: target)
    }

    @objc private func userMovedMap(_ gesture: UIGestureRecognizer) {
        guard gesture.state == .began || gesture.state == .ended else { return }
        focus = nil
        highlightFocusedStop()
        pauseFollowing()
    }

    /// A swipe from the left edge goes back rather than moving the map. While the sheet is up, touches beside it reach
    /// the map without their screen-edge flag, so neither the system's back swipe nor a screen-edge recognizer begins;
    /// this plain pan starts only from the edge instead, and only when the system's doesn't. The map's drags, MapKit's
    /// and the ones that pause following, wait for both to fail, which they do as soon as a touch moves.
    /// iOS 26's swipe back from anywhere in the content keeps yielding to the map's drags.
    private func setUpBackSwipe() {
        guard backSwipe.view == nil else { return }
        backSwipe.maximumNumberOfTouches = 1
        backSwipe.delegate = self
        backSwipe.addTarget(self, action: #selector(swipedBack))
        view.addGestureRecognizer(backSwipe)
        var backSwipes: [UIGestureRecognizer] = [backSwipe]
        if let systemBackSwipe = navigationController?.interactivePopGestureRecognizer {
            backSwipe.require(toFail: systemBackSwipe)
            backSwipes.append(systemBackSwipe)
        }
        func drags(in view: UIView) -> [UIGestureRecognizer] {
            (view.gestureRecognizers ?? []).filter { $0 is UIPanGestureRecognizer }
                + view.subviews.flatMap { drags(in: $0) }
        }
        for drag in drags(in: mapView) {
            for swipe in backSwipes {
                drag.require(toFail: swipe)
            }
        }
    }

    /// Goes back like the system's swipe: past a third of the width or with a flick, unless flicked back.
    @objc private func swipedBack() {
        guard backSwipe.state == .ended else { return }
        let distance = backSwipe.translation(in: view).x
        let speed = backSwipe.velocity(in: view).x
        if speed > 500 || (distance > view.bounds.width / 3 && speed > -500) {
            goBack?()
        }
    }

    /// The back swipe begins only for a mostly sideways drag to the right that started at the left edge.
    func gestureRecognizerShouldBegin(_ gesture: UIGestureRecognizer) -> Bool {
        guard gesture === backSwipe else { return true }
        let start = backSwipe.location(in: view).x - backSwipe.translation(in: view).x
        let velocity = backSwipe.velocity(in: view)
        return start - view.safeAreaInsets.left <= 24 && velocity.x > abs(velocity.y)
    }

    /// The gestures that pause following recognize alongside the map's own.
    func gestureRecognizer(
        _ gesture: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        gesture !== backSwipe && other !== backSwipe
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
            styleDot(view)
            view.displayPriority = .defaultHigh
            // Out of collisions, so the pins keep their names where a ride's stops crowd them.
            view.collisionMode = .none
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
        view.glyphImage = stop.glyph
        view.displayPriority = .required
        view.zPriority = .max
        view.accessibilityLabel = stop.spokenLabel
        return view
    }

    func mapView(_: MKMapView, regionDidChangeAnimated _: Bool) {
        // The focused stop may only now have come into view.
        highlightFocusedStop()
    }

    func mapView(_: MKMapView, didSelect view: MKAnnotationView) {
        styleDot(view)
    }

    func mapView(_: MKMapView, didDeselect view: MKAnnotationView) {
        styleDot(view)
    }

    /// A ring in the line's colour, or a larger filled dot while selected.
    private func styleDot(_ view: MKAnnotationView) {
        guard let stop = view.annotation as? TripStopAnnotation, !stop.isPin else { return }
        let background = UIColor.systemBackground.resolvedColor(with: traitCollection)
        view.image = view.isSelected
            ? Self.dot(background, fill: stop.color, size: 18, lineWidth: 3)
            : Self.dot(stop.color, fill: background, size: 10, lineWidth: 2)
    }

    private static func dot(_ color: UIColor, fill: UIColor, size: CGFloat, lineWidth: CGFloat) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { context in
            let circle = UIBezierPath(ovalIn: context.format.bounds.insetBy(dx: lineWidth / 2, dy: lineWidth / 2))
            fill.setFill()
            circle.fill()
            color.setStroke()
            circle.lineWidth = lineWidth
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

/// A pin labelled with the platform letter (or a glyph) where a ride starts or ends or a walk starts or ends the
/// journey, or a dot for a stop in between.
private final class TripStopAnnotation: MKPointAnnotation {
    let isPin: Bool
    let platform: String?
    let glyph: UIImage?
    let color: UIColor
    let glyphColor: UIColor
    let spokenLabel: String?

    init(
        pinAt coordinate: CLLocationCoordinate2D, name: String, platform: String?, glyph: UIImage?, color: UIColor,
        glyphColor: UIColor, spokenLabel: String
    ) {
        isPin = true
        self.platform = platform
        self.glyph = glyph
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
        glyph = nil
        self.color = color
        glyphColor = color
        spokenLabel = nil
        super.init()
        self.coordinate = coordinate
        title = name
    }
}

private extension UISheetPresentationController.Detent.Identifier {
    /// Just the journey's summary at the top of the sheet, so the map shows the whole route.
    static let summary = Self("summary")
}

extension StopGps {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
