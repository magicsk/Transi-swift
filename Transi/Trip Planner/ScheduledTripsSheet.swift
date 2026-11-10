//
//  ScheduledTripsSheet.swift
//  Transi
//
//  Created by magic_sk on 09/11/2026.
//

import SwiftUI

/// The scheduled trips, soonest first: each opens its detail and can be cancelled. Closes with the last one.
struct ScheduledTripsSheet: View {
    @StateObject private var tripSchedule = GlobalController.tripSchedule
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .headline) private var badgeSize = 17.0

    var body: some View {
        NavigationStack {
            List(tripSchedule.trips) { trip in
                row(trip)
            }
            .navigationTitle("Scheduled trips")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        // Drops the trips that arrived since the app came up.
        .onAppear { tripSchedule.sync(opened: true) }
        .onChange(of: tripSchedule.trips.isEmpty) { isEmpty in
            if isEmpty {
                dismiss()
            }
        }
    }

    @ViewBuilder
    private func row(_ trip: ScheduledTrip) -> some View {
        let parts = trip.journey.parts ?? []
        if let first = parts.first, let last = parts.last {
            let route = "\(first.startStopName ?? "") → \(last.endStopName ?? "")"
            let times = "\(dayAndTime(first.startDeparture)) – \(timeStringFromDate(last.endArrival))"
            let lines = trip.journey.lines().map { $0 ?? "?" }
            HStack(spacing: 12) {
                Button {
                    GlobalController.appState.pendingJourney = trip.journey
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            ForEach(Array(lines.enumerated()), id: \.offset) { LineText($0.element, badgeSize) }
                        }
                        Text(times).font(.headline)
                        Text(route).font(.subheadline).foregroundColor(.secondary)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel(
                    Text("Line \(lines.joined(separator: ", then line ")), \(route), \(times)")
                )
                .accessibilityHint("Shows the trip on the map, step by step")
                Button("Cancel", role: .destructive) {
                    tripSchedule.cancel(trip)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Cancel the trip \(route), \(times)"))
            }
        }
    }
}
