//
//  Timetable.swift
//  Transi
//
//  Created by magic_sk on 18/12/2023.
//

import SwiftUI
import SwiftUIIntrospect
import AudioToolbox

struct TimetableView: View {
    let route: Route
    let timezoneOffset = TimeZone(identifier: "Europe/Bratislava")!.secondsFromGMT()
    let feedbackGenerator = UIImpactFeedbackGenerator(style: .rigid)
    @State var departures: [Departure] = []
    @State var selectedDeparture = 0.0
    @State var directions: [Direction] = []
    @State var selectedDirection: Direction = .initial
    @State var selectedDate = Date()
    @State var isLoading = true
    @State var isError = false
    @State var noTimetable = false

    init(_ route: Route) {
        self.route = route
        feedbackGenerator.prepare()
    }

    var body: some View {
        let lastDepartureIndex = departures.count - 1
        LoadingOverlay($isLoading, true) {
            ZStack {
                Color.systemGroupedBackground.edgesIgnoringSafeArea(.all)
                VStack(alignment: .leading, spacing: 15.0) {
                    Picker("Direction", selection: $selectedDirection) {
                        ForEach(directions) { direction in
                            Text(direction.name).tag(direction)
                        }
                    }
                    .pickerStyle(.segmented)

                    let sliderEnd = Double(lastDepartureIndex < 1 ? 1 : lastDepartureIndex)
                    Slider(
                        value: $selectedDeparture,
                        in: 0 ... sliderEnd,
                        step: 1
                    ) {} minimumValueLabel: {
                        Button(action: {
                            if selectedDeparture > 0 {
                                selectedDeparture -= 1
                            }
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(Color.secondaryLabel, Color.tertiarySystemBackground)
                                .cornerRadius(1000)
                        }
                    } maximumValueLabel: {
                        Button(action: {
                            if Int(selectedDeparture) < lastDepartureIndex {
                                selectedDeparture += 1
                            }
                        }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(Color.secondaryLabel, Color.tertiarySystemBackground)
                                .cornerRadius(1000)
                        }
                    }

                    if !departures.isEmpty && Int(selectedDeparture) <= lastDepartureIndex {
                        let directionDepartures = departures[Int(selectedDeparture)].directionDepartures
                        List(directionDepartures) { departure in
                            HStack {
                                Text(departure.name)
                                Spacer()
                                Text(Date(timeIntervalSince1970: Double(departure.departure * 60 - timezoneOffset)).formatted(date: .omitted, time: .shortened))
                            }.overlay {
                                NavigationLink(destination: TimetableDetailView(route, selectedDirection, departure, selectedDate),
                                               label: { EmptyView() })
                                    .opacity(0)
                            }

                        }.introspect(.list(style: .insetGrouped), on: .iOS(.v16, .v17)) { list in
                            list.contentInset.top = -25
                        }
                        .padding(.horizontal, -20.0)
                    } else {
                        if noTimetable {
                            VStack {
                                Image(systemName: "calendar.badge.exclamationmark").font(.system(size: 96.0, weight: .light)).foregroundColor(.tertiaryLabel)
                                    .padding(.bottom, 2.5)
                                Text("No timetable found for selected date.").foregroundColor(.secondaryLabel)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            Spacer()
                        }
                    }
                }
                .padding(.top, 10.0)
                .padding(.horizontal, 20.0)
            }
        }
        .paddingTop(100.0)
        .overlayBackground(.clear)
        .navigationTitle("Line \(route.shortName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack {
                    Text("Line")
                    LineText(route.shortName, 18.5)
                }.frame(width: 100)
            }
            ToolbarItem(placement: .topBarTrailing) {
                DatePicker(
                    "",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
            }
        }
        .onChange(of: selectedDeparture) { _ in
            feedbackGenerator.impactOccurred()
        }
        .onChange(of: [selectedDirection.name, selectedDate.description]) { _ in
            noTimetable = false
            isLoading = true
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                var request = URLRequest(url: URL(string: "\(GlobalController.bApiBaseUrl)/mobile/v1/route/\(route.id)/departures/\(selectedDirection.id)/\(selectedDate.toString())/0/1440/")!)
                request.setValue("Dalvik/2.1.0 (Linux; U; Android 12; Pixel 6)", forHTTPHeaderField: "User-Agent")
                request.setValue(GlobalController.bApiKey, forHTTPHeaderField: "x-api-key")
                request.setValue(GlobalController.getSessionToken(), forHTTPHeaderField: "x-session")
                GlobalController.fetchData(request: request, type: Departures.self) { departures in
                    self.departures = departures.all
                    self.selectedDeparture = Double(self.departures.firstIndex(where: { $0.departure > (Int(Date.now.timeIntervalSince1970) + timezoneOffset) / 60 % 1440 }) ?? 0)
                    if departures.all.isEmpty {
                        self.noTimetable = true
                        self.departures = [] // do this also on error
                    }
                    self.isLoading = false
                }
            }
        }
        .onAppear {
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                if directions.isEmpty {
                    var request = URLRequest(url: URL(string: "\(GlobalController.bApiBaseUrl)/mobile/v1/route/\(route.id)/directions")!)
                    request.setValue("Dalvik/2.1.0 (Linux; U; Android 12; Pixel 6)", forHTTPHeaderField: "User-Agent")
                    request.setValue(GlobalController.bApiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue(GlobalController.getSessionToken(), forHTTPHeaderField: "x-session")
                    GlobalController.fetchData(request: request, type: Directions.self) { directions in
                        self.directions = directions.all
                        self.selectedDirection = directions.all.first ?? .initial
                    }
                }
            }
        }
    }
}

// #Preview {
//    TimetableView()
// }
