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

    let timetableDb = GlobalController.timetableDatabase
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
                    ) {
                        Text("Departure")
                    } minimumValueLabel: {
                        Button(action: {
                            if selectedDeparture > 0 {
                                selectedDeparture -= 1
                            }
                        }) {
                            Image(systemName: "minus.circle.fill")
                                .font(.system(size: 32))
                                .foregroundStyle(Color.secondaryLabel, Color.tertiarySystemBackground)
                                .cornerRadius(1000)
                                .frame(width: 44.0, height: 44.0)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Earlier departure")
                        .disabled(selectedDeparture <= 0)
                        .opacity(selectedDeparture <= 0 ? 0.4 : 1.0)
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
                                .frame(width: 44.0, height: 44.0)
                                .contentShape(Rectangle())
                        }
                        .accessibilityLabel("Later departure")
                        .disabled(Int(selectedDeparture) >= lastDepartureIndex)
                        .opacity(Int(selectedDeparture) >= lastDepartureIndex ? 0.4 : 1.0)
                    }
                    .accessibilityValue(selectedRunText)
                    // Its range is padded to 0...1 for a single run, where the end would pick a run that doesn't exist.
                    .disabled(departures.count < 2)

                    if !departures.isEmpty && Int(selectedDeparture) <= lastDepartureIndex {
                        let directionDepartures = departures[Int(selectedDeparture)].directionDepartures
                        let list = List(directionDepartures) { departure in
                            // A visible link: the chevron tells that a stop opens its whole day's timetable.
                            NavigationLink(destination: TimetableDetailView(route, selectedDirection, departure, selectedDate)) {
                                HStack {
                                    Text(departure.name)
                                    Spacer()
                                    Text(timeText(departure.departure))
                                }
                            }
                        }.introspect(.list(style: .insetGrouped), on: .iOS(.v16, .v17, .v18)) { list in
                            list.contentInset.top = -25
                        }
                        .padding(.horizontal, -20.0)
                        // The inset above has no match from iOS 26 on, which left a band above the stops.
                        if #available(iOS 26.0, *) {
                            list.contentMargins(.top, 0, for: .scrollContent)
                        } else {
                            list
                        }
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
        .navigationTitle(route.shortName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack {
                    LineText(route.shortName, 18.5)
                }.frame(width: 100)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Line \(route.shortName)")
                .accessibilityAddTraits(.isHeader)
            }
            ToolbarItem(placement: .topBarTrailing) {
                ZStack {
                    DatePicker(
                        "Date",
                        selection: $selectedDate,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .colorMultiply(.clear)
                    Text(datePickerFormatter.string(from: selectedDate))
                        .allowsHitTesting(false)
                        // The picker beneath already reads the date.
                        .accessibilityHidden(true)
                }
            }
        }
        .onChange(of: selectedDeparture) { _ in
            Self.feedbackGenerator.impactOccurred()
        }
        // The id too: two directions can share a headsign.
        .onChange(of: [String(selectedDirection.id), selectedDirection.name, selectedDate.description]) { _ in
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
        let direction = selectedDirection
        let date = selectedDate
        // A slower reply for an earlier direction or date would replace the one now selected.
        let isCurrent = { direction == selectedDirection && date == selectedDate }

        let handleResult = { [self] (result: Result<Departures, Error>) in
            guard isCurrent() else { return }
            switch result {
            case let .success(departures):
                handleDepartures(departures.all)
            case .failure:
                if route.source == .server { timetableDb.serverTimetablesFailed = true }
                self.departures = []
                self.loading = false
                self.timetableError = true
            }
        }
        switch route.source {
        case .offline:
            timetableDb.queryDepartures(routeRowid: route.id, directionId: direction.id, directionName: direction.name, date: date) { [self] departures in
                guard isCurrent() else { return }
                handleDepartures(departures)
            }
        case .server:
            fetchMagicApi(endpoint: route.serverEndpoint("departures", direction: direction, date: date), type: Departures.self, timeout: MAGIC_API_FALLBACK_TIMEOUT, completion: handleResult)
        case .bApi:
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                fetchBApi(endpoint: "/mobile/v1/route/\(route.id)/departures/\(direction.id)/\(date.toString())/0/1440/", type: Departures.self, completion: handleResult)
            }
        }
    }

    private func handleDepartures(_ deps: [Departure]) {
        if deps.isEmpty {
            noTimetable = true
            departures = []
        } else {
            departures = deps
        }
        loading = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.selectedDeparture = Double(self.departures.firstIndex(where: { $0.departure > (Int(Date.now.timeIntervalSince1970) + timezoneOffset) / 60 % 1440 }) ?? 0)
        }
    }

    func fetchDirections() {
        guard directions.isEmpty else { return }

        let handleResult = { [self] (result: Result<Directions, Error>) in
            switch result {
            case let .success(directions):
                self.directions = directions.all
                self.selectedDirection = directions.all.first ?? .initial
                if directions.all.isEmpty {
                    noTimetable = true
                    loading = false
                }
            case .failure:
                if route.source == .server { timetableDb.serverTimetablesFailed = true }
                self.directionsError = true
            }
        }
        switch route.source {
        case .offline:
            timetableDb.queryDirections(routeRowid: route.id) { [self] dirs in
                directions = dirs
                selectedDirection = dirs.first ?? .initial
                if dirs.isEmpty {
                    noTimetable = true
                    loading = false
                }
            }
        case .server:
            fetchMagicApi(endpoint: "/timetable/routes/\(route.id)/directions", type: Directions.self, timeout: MAGIC_API_FALLBACK_TIMEOUT, completion: handleResult)
        case .bApi:
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                fetchBApi(endpoint: "/mobile/v1/route/\(route.id)/directions", type: Directions.self, completion: handleResult)
            }
        }
    }

    /// Minutes after midnight in UTC, so neither summer time nor the device's time zone shifts them: subtracting
    /// today's offset from a January 1970 date showed summer departures an hour early.
    private static let minutesStyle: Date.FormatStyle = {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = TimeZone(secondsFromGMT: 0)!
        return style
    }()

    /// A departure's minutes since midnight as a time of day.
    private func timeText(_ minutes: Int) -> String {
        Date(timeIntervalSince1970: Double(minutes * 60)).formatted(Self.minutesStyle)
    }

    /// The run the slider picks, as VoiceOver reads it: where and when it starts.
    private var selectedRunText: String {
        guard departures.indices.contains(Int(selectedDeparture)),
              let first = departures[Int(selectedDeparture)].directionDepartures.first
        else { return "" }
        return "\(timeText(first.departure)) from \(first.name)"
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
