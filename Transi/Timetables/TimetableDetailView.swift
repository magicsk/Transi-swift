//
//  TimetableDetail.swift
//  Transi
//
//  Created by magic_sk on 21/12/2023.
//

import SwiftUI
import SwiftUIIntrospect

struct TimetableDetailView: View {
    let route: Route
    let direction: Direction
    let departure: DirectionDeparture
    let selectedDate: Date
    @State var departures: [HourMinute] = []
    @State var isLoading = true

    init(_ route: Route, _ direction: Direction, _ departure: DirectionDeparture, _ selectedDate: Date) {
        self.route = route
        self.direction = direction
        self.departure = departure
        self.selectedDate = selectedDate
    }

    var body: some View {
        LoadingOverlay($isLoading, true) {
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
        }
        .paddingTop(100.0)
        .overlayBackground(.clear)
        .onAppear {
            if departures.isEmpty {
                isLoading = true
                DispatchQueue.global(qos: .userInitiated).async { [self] in
                    var request = URLRequest(url: URL(string: "\(GlobalController.bApiBaseUrl)/mobile/v1/route/\(route.id)/departures/\(direction.id)/\(selectedDate.toString())/\(departure.id)/")!)
                    request.setValue("Dalvik/2.1.0 (Linux; U; Android 12; Pixel 6)", forHTTPHeaderField: "User-Agent")
                    request.setValue(GlobalController.bApiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue(GlobalController.getSessionToken(), forHTTPHeaderField: "x-session")
                    GlobalController.fetchData(request: request, type: TimetableDetails.self) { timetableDetails in
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
                        isLoading = false
                    }
                }
            }
        }
    }
}

// #Preview {
//    TimetableDetailView()
// }
