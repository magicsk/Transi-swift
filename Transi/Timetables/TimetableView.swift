//
//  Timetable.swift
//  Transi
//
//  Created by magic_sk on 18/12/2023.
//

import SwiftUI
import SwiftUIIntrospect

struct TimetableView: View {
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

    let route: Route
    let timezoneOffset = TimeZone(identifier: "Europe/Bratislava")!.secondsFromGMT()
    private static let feedbackGenerator: UIImpactFeedbackGenerator = {
        let gen = UIImpactFeedbackGenerator(style: .rigid)
        gen.prepare()
        return gen
    }()
    @State var departures: [Departure] = []
    @State var selectedDeparture = 0.0
    @State var directions: [Direction] = []
    @State var selectedDirection: Direction = .initial
    @State var selectedDate = Date()
    @State var loading = true
    @State var timetableError = false
    @State var directionsError = false
    @State var noTimetable = false

    init(_ route: Route) {
        self.route = route
    }

    var body: some View {
        let lastDepartureIndex = departures.count - 1
        LoadingOverlay($loading, true, error: $directionsError, errorText: TimetableError.directions) {
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

                        }.introspect(.list(style: .insetGrouped), on: .iOS(.v16, .v17, .v18)) { list in
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
        } retry: {
            fetchDirections()
        } cancel: {
            presentationMode.wrappedValue.dismiss()
        }
        .paddingTop(100.0)
        .overlayBackground(Color.clear)
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
                ZStack {
                    DatePicker(
                        "",
                        selection: $selectedDate,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .colorMultiply(.clear)
                    Text(datePickerFormatter.string(from: selectedDate))
                        .allowsHitTesting(false)
                }
            }
        }
        .onChange(of: selectedDeparture) { _ in
            Self.feedbackGenerator.impactOccurred()
        }
        .onChange(of: [selectedDirection.name, selectedDate.description]) { _ in
            fetchTimetable()
        }
        .alert(isPresented: $timetableError, error: TimetableError.singular) { _ in
            Button("Cancel") {
                presentationMode.wrappedValue.dismiss()
            }
            Button("Retry") {
                fetchTimetable()
            }
        } message: { error in
            if let message = error.failureReason {
                Text(message)
            }
        }
        .onAppear {
            fetchDirections()
        }
    }

    func fetchTimetable() {
        noTimetable = false
        loading = true
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            fetchBApi(endpoint: "/mobile/v1/route/\(route.id)/departures/\(selectedDirection.id)/\(selectedDate.toString())/0/1440/", type: Departures.self) { result in
                switch result {
                case let .success(departures):
                    self.departures = departures.all
                    if departures.all.isEmpty {
                        self.noTimetable = true
                        self.departures = []
                    }
                    self.loading = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.selectedDeparture = Double(self.departures.firstIndex(where: { $0.departure > (Int(Date.now.timeIntervalSince1970) + timezoneOffset) / 60 % 1440 }) ?? 0)
                    }

                case .failure:
                    DispatchQueue.main.async {
                        self.departures = []
                        self.loading = false
                        self.timetableError = true
                    }
                }
            }
        }
    }

    func fetchDirections() {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            if directions.isEmpty {
                fetchBApi(endpoint: "/mobile/v1/route/\(route.id)/directions", type: Directions.self) { result in
                    switch result {
                    case let .success(directions):
                        DispatchQueue.main.async {
                            self.directions = directions.all
                            self.selectedDirection = directions.all.first ?? .initial
                        }
                    case .failure:
                        DispatchQueue.main.async {
                            self.directionsError = true
                        }
                    }
                }
            }
        }
    }

    private let datePickerFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter
    }()
}

// #Preview {
//    TimetableView()
// }
