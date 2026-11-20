//
//  TimetableDetail.swift
//  Transi
//
//  Created by magic_sk on 21/12/2023.
//

import SwiftUI
import SwiftUIIntrospect
import WrappingHStack

struct TimetableDetailView: View {
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

    let timetableDb = GlobalController.timetableDatabase
    let route: Route
    let direction: Direction
    let departure: DirectionDeparture
    let selectedDate: Date
    @State var departures: [HourMinute] = []
    @State var loading = true
    @State var error = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(_ route: Route, _ direction: Direction, _ departure: DirectionDeparture, _ selectedDate: Date) {
        self.route = route
        self.direction = direction
        self.departure = departure
        self.selectedDate = selectedDate
    }

    var body: some View {
        LoadingOverlay($loading, true, error: $error, errorText: TimetableError.singular) {
            ZStack {
                Color.systemGroupedBackground.edgesIgnoringSafeArea(.all)
                VStack(alignment: .leading, spacing: 10.0) {
                    HStack(alignment: .center, spacing: 20.0) {
                        LineText(route.shortName)
                        VStack(alignment: .leading) {
                            Text(direction.name)
                                .font(.title2.bold())
                                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                                .minimumScaleFactor(0.8)
                            HStack(alignment: .center, spacing: 5.0) {
                                Image("stop").padding(.leading, -5.0)
                                Text(departure.name).font(.callout)
                            }
                        }
                    }
                    .padding(.horizontal, 20.0)
                    let list = List(departures) { departure in
                        let hour = String(departure.hour % 24).leftPadding(toLength: 2, withPad: "0")
                        Label {
                            // Wrapped, not scrolled sideways: a busy hour hid its later departures off the row.
                            WrappingHStack(departure.minutes) { minute in
                                // Equal-width digits keep the minutes in columns from hour to hour.
                                Text(minute).monospacedDigit()
                            }
                        } icon: {
                            Text(hour)
                                .fontWeight(.bold)
                                .padding(0.0)
                        }
                        // One element per hour, each departure read as a time rather than a bare number.
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(
                            (departure.hour >= 24 ? "Next day, " : "")
                                + departure.minutes.map { "\(hour):\($0)" }.joined(separator: ", ")
                        )
                    }
                    .introspect(.list(style: .insetGrouped), on: .iOS(.v16, .v17, .v18)) { list in
                        list.contentInset.top = -25.0
                    }
                    // The inset above has no match from iOS 26 on.
                    if #available(iOS 26.0, *) {
                        list.contentMargins(.top, 0, for: .scrollContent)
                    } else {
                        list
                    }
                }
            }
        } retry: {
            fetchTimetableDetail()
        } cancel: {
            presentationMode.wrappedValue.dismiss()
        }
        .paddingTop(100.0)
        .overlayBackground(Color.clear)
        .onAppear {
            fetchTimetableDetail()
        }
    }

    func fetchTimetableDetail() {
        guard departures.isEmpty else { return }
        loading = true

        let handleResult = { [self] (result: Result<TimetableDetails, Error>) in
            switch result {
            case let .success(timetableDetails):
                groupDetailsIntoHourMinutes(timetableDetails.all)
            case .failure:
                if route.source == .server { timetableDb.serverTimetablesFailed = true }
                error = true
            }
        }
        switch (route.source, departure.stopCode) {
        case let (.offline, stopCode?):
            timetableDb.queryTimetableDetail(routeRowid: route.id, directionId: direction.id, directionName: direction.name, date: selectedDate, gtfsStopId: stopCode) { [self] details in
                groupDetailsIntoHourMinutes(details)
            }
        case let (.server, stopCode?):
            fetchMagicApi(endpoint: route.serverEndpoint("stop-departures", direction: direction, date: selectedDate, stopId: stopCode), type: TimetableDetails.self, timeout: MAGIC_API_FALLBACK_TIMEOUT, completion: handleResult)
        case (.bApi, _):
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                fetchBApi(endpoint: "/mobile/v1/route/\(route.id)/departures/\(direction.id)/\(selectedDate.toString())/\(departure.id)/", type: TimetableDetails.self, completion: handleResult)
            }
        case (_, nil):
            // A GTFS stop without an id can't be looked up, and its route's ids mean nothing to the B API.
            error = true
        }
    }

    private func groupDetailsIntoHourMinutes(_ details: [TimetableDetail]) {
        departures.removeAll()
        for detail in details {
            // Not wrapped to 0–23: a night trip at 24:15 belongs after 23:xx, not with the morning's 00:xx.
            let hour = detail.t / 60
            let minute = String(detail.t % 60).leftPadding(toLength: 2, withPad: "0")
            if let idx = departures.firstIndex(where: { $0.hour == hour }) {
                departures[idx].minutes.append(minute)
            } else {
                departures.append(HourMinute(hour: hour, minutes: [minute]))
            }
        }
        loading = false
    }
}

// #Preview {
//    TimetableDetailView()
// }
