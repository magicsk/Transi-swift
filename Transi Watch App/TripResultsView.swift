//
//  TripResultsView.swift
//  Transi Watch App
//
//  Created by magic_sk on 19/11/2026.
//

import SwiftUI

/// The routes the planner found, soonest first; more load at the end of the list.
struct TripResultsView: View {
    @StateObject private var planner = GlobalController.tripPlanner

    var body: some View {
        let journeys = planner.trip.journey ?? []
        List {
            if !journeys.isEmpty {
                ForEach(journeys, id: \.id) { journey in
                    NavigationLink {
                        JourneyDetailView(journey: journey)
                    } label: {
                        JourneyRow(journey: journey)
                    }
                    // Loading more moves the search later, past an arrive-by time.
                    .onAppear { if planner.arrivalDeparture == .departure { planner.loadMoreTripsIfNeeded(journey) } }
                }
                if planner.loadingMore {
                    ProgressView().frame(maxWidth: .infinity).listRowBackground(Color.clear)
                }
            } else if let error = planner.error, !planner.loading {
                ContentUnavailableView(
                    error.errorDescription ?? "", systemImage: "exclamationmark.triangle",
                    description: Text(error.failureReason ?? "")
                )
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                    .accessibilityLabel("Finding routes")
            }
        }
        .navigationTitle("Routes")
    }
}

extension Journey {
    /// When it starts and arrives with the delays the search found, as its legs show them: a first ride's delay moves
    /// the start, the last ride's delay the arrival and any walk after it.
    var expectedTimes: (start: Date, end: Date)? {
        guard let first = parts?.first, let last = parts?.last else { return nil }
        let start = first.routeType == 64 ? first.startDeparture : first.startDeparture.expected(delaySeconds: first.delaySeconds)
        let lastRide = parts?.last { $0.routeType != 64 }
        return (start, last.endArrival.expected(delaySeconds: lastRide?.delaySeconds))
    }
}

struct JourneyRow: View {
    let journey: Journey

    var body: some View {
        let parts = journey.parts ?? []
        let transit = parts.filter { $0.routeType != 64 }
        if let times = journey.expectedTimes {
            let (startDate, endDate) = times
            let start = timeStringFromDate(startDate)
            let day = dayStringUnlessToday(startDate)
            let minutes = minutesBetween(startDate, endDate)
            VStack(alignment: .leading, spacing: 4.0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(start) – \(timeStringFromDate(endDate))")
                        .font(.headline.monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Spacer(minLength: 2.0)
                    Text("\(minutes) min").font(.footnote).foregroundStyle(.secondary).fixedSize()
                }
                HStack(spacing: 3.0) {
                    if transit.isEmpty {
                        Image(systemName: "figure.walk")
                    }
                    ForEach(Array(transit.prefix(4).enumerated()), id: \.offset) { _, part in
                        LineText(part.routeShortName ?? "?", 13.0)
                    }
                    if transit.count > 4 {
                        Text("+\(transit.count - 4)").font(.footnote)
                    }
                }
                if let board = transit.first {
                    HStack(spacing: 4.0) {
                        if let day {
                            Text(day).fontWeight(.semibold)
                        }
                        Text("from \(board.startStopName ?? "")").lineLimit(1)
                        if let delay = board.delaySeconds.map(delayMinutes), delay != 0 {
                            Text(delay > 0 ? "+\(delay) min" : "\(delay) min")
                                .foregroundStyle(getDelayColor(delay, "online"))
                                .fixedSize()
                        }
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 2.0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                [
                    day, String(localized: "\(start) to \(timeStringFromDate(endDate))"),
                    String(localized: "\(minutes) minutes"),
                    transit.isEmpty
                        ? String(localized: "walk")
                        : String(localized: "lines \(transit.compactMap(\.routeShortName).joined(separator: ", "))"),
                    transit.first?.startStopName.map { String(localized: "from \($0)") },
                    transit.first?.delaySeconds.map(delayMinutes).flatMap { delay in
                        delay == 0 ? nil
                            : delay > 0 ? String(localized: "\(delay) min late") : String(localized: "\(-delay) min early")
                    },
                ].compactMap { $0 }.joined(separator: ", ")
            )
        }
    }
}
