//
//  TimetablesView.swift
//  Transi
//
//  Created by magic_sk on 08/05/2023.
//

import SwiftUI
import WrappingHStack

struct TimetablesView: View {
    @EnvironmentObject private var dataProvider: DataProvider

    @State var trams: [Route] = []
    @State var trolleybuses: [Route] = []
    @State var buses: [Route] = []
    @State var nightlines: [Route] = []
    @State var trains: [Route] = []
    @State var regionalbuses: [Route] = []

    @State var isLoading = true

    let columns = [
        GridItem(.flexible())
    ]

    var body: some View {
        LoadingOverlay($isLoading) {
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 5.0) {
                        Text("Trams").font(.system(size: 24.0, weight: .semibold))
                        WrappingHStack(trams) { route in
                            NavigationLink(destination: TimetableView(route)) {
                                LineText(route.shortName, 22.0).padding(.horizontal, 2.0).padding(.vertical, 5.0)
                            }
                        }
                        Text("Trolleybuses").font(.system(size: 24.0, weight: .semibold))
                        WrappingHStack(trolleybuses) { route in
                            NavigationLink(destination: TimetableView(route)) {
                                LineText(route.shortName, 22.0).padding(.horizontal, 2.0).padding(.vertical, 5.0)
                            }
                        }
                        Text("Buses").font(.system(size: 24.0, weight: .semibold))
                        WrappingHStack(buses) { route in
                            NavigationLink(destination: TimetableView(route)) {
                                LineText(route.shortName, 22.0).padding(.horizontal, 2.0).padding(.vertical, 5.0)
                            }
                        }
                        Text("Night lines").font(.system(size: 24.0, weight: .semibold))
                        WrappingHStack(nightlines) { route in
                            NavigationLink(destination: TimetableView(route)) {
                                LineText(route.shortName, 22.0).padding(.horizontal, 2.0).padding(.vertical, 5.0)
                            }
                        }
                        Text("Trains").font(.system(size: 24.0, weight: .semibold))
                        WrappingHStack(trains) { route in
                            NavigationLink(destination: TimetableView(route)) {
                                LineText(route.shortName, 22.0).padding(.horizontal, 2.0).padding(.vertical, 5.0)
                            }
                        }
                        Text("Regional Buses").font(.system(size: 24.0, weight: .semibold))
                        WrappingHStack(regionalbuses) { route in
                            NavigationLink(destination: TimetableView(route)) {
                                LineText(route.shortName, 22.0).padding(.horizontal, 2.0).padding(.vertical, 5.0)
                            }
                        }
                    }
                    .padding(.bottom, 10.0)
                }
                .padding(.horizontal, 12.0)
                .navigationTitle(Text("Timetables"))
            }
        }
        .paddingTop(80.0)
        .overlayBackground(Color.systemBackground)
        .onAppear {
            if regionalbuses.isEmpty {
                isLoading = true
                DispatchQueue.global(qos: .userInitiated).async { [self] in
                    var request = URLRequest(url: URL(string: "\(dataProvider.bApiBaseUrl)/mobile/v1/route/12/")!)
                    request.setValue("Dalvik/2.1.0 (Linux; U; Android 12; Pixel 6)", forHTTPHeaderField: "User-Agent")
                    request.setValue(dataProvider.bApiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue(dataProvider.sessionToken, forHTTPHeaderField: "x-session")
                    DataProvider.fetchData(request: request, type: Timetables.self) { timetables in
                        let routes = timetables.routes
                        routes.forEach { route in
                            switch route.routeType {
                            case 0:
                                trams.append(route)

                            case 2:
                                trains.append(route)

                            case 3:
                                if route.shortName.starts(with: "N") {
                                    nightlines.append(route)
                                } else {
                                    buses.append(route)
                                }

                            case 50:
                                if route.shortName.starts(with: "N") {
                                    nightlines.append(route)
                                } else {
                                    trolleybuses.append(route)
                                }

                            default:
                                regionalbuses.append(route)
                            }
                        }
                        isLoading = false
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
