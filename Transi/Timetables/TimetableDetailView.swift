//
//  TimetableDetail.swift
//  Transi
//
//  Created by magic_sk on 21/12/2023.
//

import SwiftUI
import SwiftUIIntrospect

struct TimetableDetailView: View {
    @Environment(\.presentationMode) var presentationMode: Binding<PresentationMode>

    let route: Route
    let direction: Direction
    let departure: DirectionDeparture
    let selectedDate: Date
    @State var departures: [HourMinute] = []
    @State var loading = true
    @State var error = false

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
                            Text(direction.name).font(.system(size: 26.0, weight: .bold)).lineLimit(1)
                            HStack(alignment: .center, spacing: 5.0) {
                                Image("stop").padding(.leading, -5.0)
                                Text(departure.name).font(.system(size: 16.0))
                            }
                        }
                    }
                    .padding(.horizontal, 20.0)
                    List(departures) { departure in
                        HStack {
                            Label {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack {
                                        ForEach(enumerating: departure.minutes) { minute in
                                            Text(minute)
                                        }
                                    }
                                }
                            } icon: {
                                Text(String(departure.hour).leftPadding(toLength: 2, withPad: "0"))
                                    .fontWeight(.bold)
                                    .padding(0.0)
                            }
                        }
                    }
                    .introspect(.list(style: .insetGrouped), on: .iOS(.v16, .v17)) { list in
                        list.contentInset.top = -25.0
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
        if departures.isEmpty {
            loading = true
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                fetchBApi(endpoint: "/mobile/v1/route/\(route.id)/departures/\(direction.id)/\(selectedDate.toString())/\(departure.id)/", type: TimetableDetails.self) { result in
                    switch result {
                        case .success(let timetableDetails):
                            departures.removeAll()
                            timetableDetails.all.forEach { departure in
                                let hour = (departure.t / 60) % 24
                                let minute = String(departure.t % 60).leftPadding(toLength: 2, withPad: "0")
                                if let hourMinuteIndex = departures.firstIndex(where: { $0.hour == hour }) {
                                    departures[hourMinuteIndex].minutes.append(minute)
                                } else {
                                    let hourMinute = HourMinute(hour: hour, minutes: [minute])
                                    departures.append(hourMinute)
                                }
                            }
                            DispatchQueue.main.async {
                                loading = false
                            }
                        case .failure:
                            DispatchQueue.main.async {
                                error = true
                            }
                    }
                }
            }
        }
    }
}

// #Preview {
//    TimetableDetailView()
// }
