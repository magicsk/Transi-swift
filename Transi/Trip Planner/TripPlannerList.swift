//
//  TripPlannerList.swift
//  Transi
//
//  Created by magic_sk on 14/05/2023.
//

import SwiftUI

struct TripPlannerList: View {
    let trip: Trip
    let loading: Bool
    let loadingMore: Bool
    let loadMoreTripsIfNeeded: (_ journey: Journey) -> Void

    init(
        _ trip: Trip, _ loading: Bool, _ loadingMore: Bool,
        loadMoreTripsIfNeeded: @escaping (_ journey: Journey) -> Void
    ) {
        self.trip = trip
        self.loading = loading
        self.loadingMore = loadingMore
        self.loadMoreTripsIfNeeded = loadMoreTripsIfNeeded
    }

    var body: some View {
        let journeys = trip.journey!
        ScrollViewReader { proxy in
            List(journeys, id: \.id) { journey in
                if let parts = journey.parts {
                    if journey.id == journeys.first?.id {
                        EmptyView().id("top")
                    }
                    Section {
                        NavigationLink(value: journey) {
                            VStack(alignment: .leading, spacing: 12.0) {
                                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                                    if part.routeType == 64 {
                                        TripPlannerWalkListItem(part, last: index == parts.count - 1)
                                    } else if part.routeType != nil {
                                        TripPlannerTransitListItem(part)
                                    } else {
                                        Text("Something went wrong")
                                    }
                                }
                            }
                            // One sentence per journey instead of loose numbers, asset names and a doubled marquee.
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(journeyAccessibilityLabel(parts, journey.zones))
                        }
                        .accessibilityHint("Shows the route on a map with every stop")
                    } header: {
                        getHeaderText(parts, journey.zones)
                            // The row's label starts with the same summary.
                            .accessibilityHidden(true)
                    }
                    .onAppear {
                        loadMoreTripsIfNeeded(journey)
                    }
                    if journey.id == journeys.last?.id {
                        if loadingMore {
                            Section {
                            } header: {
                                HStack(alignment: .center) {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                        .padding(.vertical, 2.5)
                                }.width(1000.0)
                            }
                        }
                    }
                } else {
                    Text("Error")
                }
            }
            .listStyle(.insetGrouped)
            .onChange(of: loading) { _ in
                proxy.scrollTo("top", anchor: .init(x: 0.0, y: -10.0))
            }
        }
    }
}

/// "Departs 18:09, 21 min, 2 zones. Line 84 to Pri kríži, from Hodžovo nám. platform C at 18:09, to Pri kríži platform F
/// at 18:30."
func journeyAccessibilityLabel(_ parts: [Part], _ zones: [String]?) -> String {
    guard let first = parts.first, let last = parts.last else { return "" }
    let start = timeStringFromDate(first.startDeparture)
    let day = dayStringUnlessToday(first.startDeparture).map { "\($0) " } ?? ""
    var summary = "Departs \(day)\(start), \(timeDiffFromDates(first.startDeparture, last.endArrival)) min"
    if let count = zones?.count, count > 0 {
        summary += count == 1 ? ", 1 zone" : ", \(count) zones"
    }
    func platform(_ code: String?) -> String {
        guard let code, !code.isEmpty else { return "" }
        return " platform \(code)"
    }
    let steps = parts.enumerated().map { index, part -> String in
        if part.routeType == 64 {
            // The row adds the platform unless the walk stays at one stop or ends the journey.
            let showsPlatform = part.startStopName != part.endStopName && index < parts.count - 1
            return "Walk \(TripPlannerWalkListItem.text(for: part))\(showsPlatform ? platform(part.endStopCode) : "")"
        }
        return "Line \(part.routeShortName ?? "") to \(part.tripHeadsign ?? ""), from \(part.startStopName ?? "")"
            + "\(platform(part.startStopCode)) at \(timeStringFromDate(part.startDeparture)), to \(part.endStopName ?? "")"
            + "\(platform(part.endStopCode)) at \(timeStringFromDate(part.endArrival))"
    }
    return ([summary] + steps).joined(separator: ". ")
}

func getHeaderText(_ parts: [Part], _ zones: [String]?) -> Text {
    if let first = parts.first, let last = parts.last {
        let startTime = timeStringFromDate(first.startDeparture)
        let duration = timeDiffFromDates(first.startDeparture, last.endArrival)
        let numOfZones = zones?.count ?? 0
        let timeDateSection = dayStringUnlessToday(first.startDeparture).map { "\($0) \(startTime)" } ?? startTime
        // Trains and cross-border stops have no fare zone; "0 zones" would read as free.
        if numOfZones == 0 {
            return Text("\(timeDateSection) | \(duration) min")
        }
        return Text("\(timeDateSection) | \(duration) min | ^[\(numOfZones) zone](inflect: true)")
    } else {
        return Text("Error")
    }
}

// struct TripPlannerList_Previews: PreviewProvider {
//    static var previews: some View {
//        TripPlannerList([Journey.example])
//    }
// }
