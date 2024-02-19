//
//  TimetablesView.swift
//  Transi
//
//  Created by magic_sk on 08/05/2023.
//

import SwiftUI
import WrappingHStack

struct TimetablesView: View {
    @State var category = CategorizedTimetables()
    @State var loading = true
    @State var error = false
    private let updateTabBarApperance: () -> Void

    init(_ updateTabBarApperance: @escaping () -> Void) {
        self.updateTabBarApperance = updateTabBarApperance
    }

    let columns = [
        GridItem(.flexible())
    ]

    var body: some View {
        LoadingOverlay($loading, error: $error, errorText: TimetableError.plural) {
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 5.0) {
                        Text("Trams").font(.system(size: 24.0, weight: .semibold))
                        WrappingHStack(category.trams) { route in
                            NavigationLink(destination: TimetableView(route)) {
                                LineText(route.shortName, 22.0).padding(.horizontal, 2.0).padding(.vertical, 5.0)
                            }
                        }
                        Text("Trolleybuses").font(.system(size: 24.0, weight: .semibold))
                        WrappingHStack(category.trolleybuses) { route in
                            NavigationLink(destination: TimetableView(route)) {
                                LineText(route.shortName, 22.0).padding(.horizontal, 2.0).padding(.vertical, 5.0)
                            }
                        }
                        Text("Buses").font(.system(size: 24.0, weight: .semibold))
                        WrappingHStack(category.buses) { route in
                            NavigationLink(destination: TimetableView(route)) {
                                LineText(route.shortName, 22.0).padding(.horizontal, 2.0).padding(.vertical, 5.0)
                            }
                        }
                        Text("Night lines").font(.system(size: 24.0, weight: .semibold))
                        WrappingHStack(category.nightlines) { route in
                            NavigationLink(destination: TimetableView(route)) {
                                LineText(route.shortName, 22.0).padding(.horizontal, 2.0).padding(.vertical, 5.0)
                            }
                        }
                        Text("Trains").font(.system(size: 24.0, weight: .semibold))
                        WrappingHStack(category.trains) { route in
                            NavigationLink(destination: TimetableView(route)) {
                                LineText(route.shortName, 22.0).padding(.horizontal, 2.0).padding(.vertical, 5.0)
                            }
                        }
                        Text("Regional Buses").font(.system(size: 24.0, weight: .semibold))
                        WrappingHStack(category.regionalbuses) { route in
                            NavigationLink(destination: TimetableView(route)) {
                                LineText(route.shortName, 22.0).padding(.horizontal, 2.0).padding(.vertical, 5.0)
                            }
                        }
                    }
                    .padding(.bottom, 10.0)
                    .padding(.horizontal, 12.0)
                }
                .navigationTitle(Text("Timetables"))
            }
        } retry: {
            fetchTimetables()
        } cancel: {}
        .paddingTop(80.0)
        .overlayBackground(Color.systemBackground)
        .onAppear {
            updateTabBarApperance()
            fetchTimetables()
        }
    }
    
    func fetchTimetables() {
        if category.regionalbuses.isEmpty {
            loading = true
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                fetchBApi(endpoint: "/mobile/v1/route/12/", type: Timetables.self) { result in
                    switch result {
                    case .success(let timetables):
                        category.clear()
                        timetables.routes.forEach { route in
                            switch route.routeType {
                            case 0:
                                category.trams.append(route)

                            case 2:
                                category.trains.append(route)

                            case 3:
                                if route.shortName.starts(with: "N") {
                                    category.nightlines.append(route)
                                } else {
                                    category.buses.append(route)
                                }

                            case 50:
                                if route.shortName.starts(with: "N") {
                                    category.nightlines.append(route)
                                } else {
                                    category.trolleybuses.append(route)
                                }

                            default:
                                category.regionalbuses.append(route)
                            }
                        }
                        DispatchQueue.main.async {
                            loading = false
                        }
                    case .failure:
                        DispatchQueue.main.async {
                            loading = false
                            error = true
                        }
                    }
                }
            }
        }
    }
}

// struct TimetablesView_Previews: PreviewProvider {
//    static var previews: some View {
//        TimetablesView()
//    }
// }
