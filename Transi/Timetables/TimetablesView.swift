//
//  TimetablesView.swift
//  Transi
//
//  Created by magic_sk on 08/05/2023.
//

import SwiftUI
import WrappingHStack

struct TimetablesView: View {
    @ObservedObject var timetableDb = GlobalController.timetableDatabase
    /// The trip planner can keep the database ready while offline timetables are off, so readiness alone doesn't tell
    /// when the catalog's source changes; route ids differ between the two sources.
    @AppStorage(Stored.offlineTimetables) private var offlineTimetables = false
    @State var category = CategorizedTimetables()
    @State var loading = true
    @State var error = false
    @State var openFromUrl = ""
    @State var urlNavigateDestination: Route = .empty
    @State var navigateInsideFromUrl = false

    let columns = [
        GridItem(.flexible()),
    ]

    var body: some View {
        LoadingOverlay($loading, error: $error, errorText: TimetableError.plural) {
            // TODO: change to NavigationSplitView
            NavigationStack {
                ScrollView {
                    if timetableDb.shouldMaintainOfflineDatabase && !timetableDb.isReady {
                        TimetableDownloadBanner()
                            .padding(.bottom, 5)
                    }
                    VStack(alignment: .leading, spacing: 5.0) {
                        Text("Trams").font(.system(size: 24.0, weight: .semibold))
                        WrappingHStack(category.trams) { route in
                            NavigationLink(destination: TimetableView(route)) {
                                LineText(route.shortName, 22.0).padding(.horizontal, 2.0).padding(
                                    .vertical, 5.0
                                )
                            }
                        }
                        Text("Trolleybuses").font(.system(size: 24.0, weight: .semibold))
                        WrappingHStack(category.trolleybuses) { route in
                            NavigationLink(destination: TimetableView(route)) {
                                LineText(route.shortName, 22.0).padding(.horizontal, 2.0).padding(
                                    .vertical, 5.0
                                )
                            }
                        }
                        Text("Buses").font(.system(size: 24.0, weight: .semibold))
                        WrappingHStack(category.buses) { route in
                            NavigationLink(destination: TimetableView(route)) {
                                LineText(route.shortName, 22.0).padding(.horizontal, 2.0).padding(
                                    .vertical, 5.0
                                )
                            }
                        }
                        Text("Night lines").font(.system(size: 24.0, weight: .semibold))
                        WrappingHStack(category.nightlines) { route in
                            NavigationLink(destination: TimetableView(route)) {
                                LineText(route.shortName, 22.0).padding(.horizontal, 2.0).padding(
                                    .vertical, 5.0
                                )
                            }
                        }
                        Text("Trains").font(.system(size: 24.0, weight: .semibold))
                        WrappingHStack(category.trains) { route in
                            NavigationLink(destination: TimetableView(route)) {
                                LineText(route.shortName, 22.0).padding(.horizontal, 2.0).padding(
                                    .vertical, 5.0
                                )
                            }
                        }
                        Text("Regional Buses").font(.system(size: 24.0, weight: .semibold))
                        WrappingHStack(category.regionalbuses) { route in
                            NavigationLink(destination: TimetableView(route)) {
                                LineText(route.shortName, 22.0).padding(.horizontal, 2.0).padding(
                                    .vertical, 5.0
                                )
                            }
                        }
                    }
                    .padding(.bottom, 10.0)
                    .padding(.horizontal, 24.0)
                }
                .navigationTitle("Timetables")
                .navigationDestination(isPresented: $navigateInsideFromUrl) {
                    TimetableView(urlNavigateDestination)
                }
            }
        } retry: {
            fetchTimetables()
        } cancel: {}
            .paddingTop(100.0)
            .overlayBackground(Color.systemBackground)
            .onAppear {
                fetchTimetables()
            }
            .onChange(of: timetableDb.isReady) { ready in
                if ready {
                    fetchTimetables(force: true)
                }
            }
            .onChange(of: offlineTimetables) { _ in
                category.clear()
                fetchTimetables(force: true)
            }
            .onReceive(GlobalController.appState.$pendingTimetableLine.compactMap { $0 }) { line in
                GlobalController.appState.pendingTimetableLine = nil
                openFromUrl = line
                if !category.regionalbuses.isEmpty {
                    let mirror = Mirror(reflecting: category)
                    var foundRoute: Route? = nil
                    for (_, attr) in mirror.children.enumerated() {
                        if let routes = attr.value as? [Route] {
                            if let route = routes.first(where: { $0.shortName == line }) {
                                foundRoute = route
                                break
                            }
                        }
                    }
                    if let route = foundRoute {
                        navigateInsideFromUrl = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                            urlNavigateDestination = route
                            navigateInsideFromUrl = true
                        }
                    }
                }
            }
    }

    func fetchTimetables(force: Bool = false) {
        guard force || categoryIsEmpty else { return }
        loading = true

        let offline = timetableDb.isOfflineEnabled && timetableDb.isReady
        // A reply from the source the catalog no longer uses is dropped, so its route ids never mix in.
        let isCurrentSource = { (timetableDb.isOfflineEnabled && timetableDb.isReady) == offline }
        if offline {
            timetableDb.queryRoutes { routes in
                guard isCurrentSource() else { return }
                categorizeRoutes(routes)
            }
        } else {
            // Our server first; the B API only when it fails.
            fetchMagicApi(endpoint: "/timetable/routes", type: Timetables.self) { result in
                guard isCurrentSource() else { return }
                if case let .success(timetables) = result {
                    categorizeRoutes(timetables.routes.map { var route = $0; route.source = .server; return route })
                } else {
                    fetchBApiRoutes(isCurrentSource: isCurrentSource)
                }
            }
        }
    }

    private func fetchBApiRoutes(isCurrentSource: @escaping () -> Bool) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            fetchBApi(endpoint: "/mobile/v1/route/12/", type: Timetables.self) { result in
                switch result {
                case let .success(timetables):
                    guard isCurrentSource() else { return }
                    categorizeRoutes(timetables.routes)
                case .failure:
                    DispatchQueue.main.async {
                        guard isCurrentSource() else { return }
                        loading = false
                        error = true
                    }
                }
            }
        }
    }

    private var categoryIsEmpty: Bool {
        category.trams.isEmpty &&
            category.trolleybuses.isEmpty &&
            category.buses.isEmpty &&
            category.nightlines.isEmpty &&
            category.trains.isEmpty &&
            category.regionalbuses.isEmpty
    }

    private func categorizeRoutes(_ routes: [Route]) {
        var foundRoute: Route? = nil
        category.clear()
        for route in routes {
            switch route.routeType {
            case 0:
                category.trams.append(route)

            case 2, 100 ... 199:
                category.trains.append(route)

            case 3:
                if route.shortName.starts(with: "N") {
                    category.nightlines.append(route)
                } else {
                    category.buses.append(route)
                }

            case 11, 800, 50:
                if route.shortName.starts(with: "N") {
                    category.nightlines.append(route)
                } else {
                    category.trolleybuses.append(route)
                }

            default:
                category.regionalbuses.append(route)
            }

            if openFromUrl != "", route.shortName == openFromUrl {
                foundRoute = route
            }
        }
        loading = false
        if let route = foundRoute {
            openFromUrl = ""
            urlNavigateDestination = route
            navigateInsideFromUrl = true
        }
    }
}

// struct TimetablesView_Previews: PreviewProvider {
//    static var previews: some View {
//        TimetablesView()
//    }
// }
