//
//  TripPlannerDatePicker.swift
//  Transi
//
//  Created by magic_sk on 29/01/2024.
//

import SwiftUI

struct TripPlannerDatePicker: View {
    @StateObject var tripPlannerController = GlobalController.tripPlanner
    @Binding private var dateDialog: Bool
    @State private var adDate: Date
    /// The wheel writes to the planner as it turns; a swipe down keeps that date, so it fetches like Done.
    @State private var unfetchedChange = false
    @State private var sheetContentHeight = 270.0
    /// Keeps Now and Done off the sheet's edge where it has no bottom safe area: floating on iPad and the Mac, or on
    /// iPhones with a Home button.
    @State private var bottomPadding = 0.0

    init(_ dateDialog: Binding<Bool>) {
        _dateDialog = dateDialog
        // A "Now" search starts the wheel at the current time, not at when it last ran.
        let planner = GlobalController.tripPlanner
        let custom = planner.arrivalDepartureCustomDate && !planner.restoredNowSearch
        _adDate = State(initialValue: custom ? planner.arrivalDepartureDate : Date())
    }
    
    var body: some View {
        VStack(spacing: .zero) {
            Text(
                tripPlannerController.arrivalDeparture == ArrivalDeparture.arrival ? "Arrival" : "Departure"
            )
            .font(.title2.weight(.semibold))
            .padding(.top, 5.0)
            DatePicker(
                "Select date",
                selection: $adDate,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .onChange(of: adDate) { _ in
                tripPlannerController.arrivalDepartureDate = adDate
                tripPlannerController.arrivalDepartureCustomDate = true
                tripPlannerController.restoredNowSearch = false
                unfetchedChange = true
            }
            HStack {
                Spacer()
                Button {
                    unfetchedChange = false
                    tripPlannerController.arrivalDepartureCustomDate = false
                    tripPlannerController.arrivalDepartureDate = Date()
                    dateDialog = false
                    tripPlannerController.fetchTrip()
                } label: {
                    // Not just the glyphs: a near miss landed on the wheel and changed the date.
                    Text("Now").frame(minWidth: 44.0, minHeight: 44.0).contentShape(Rectangle())
                }
                Spacer()
                Button {
                    unfetchedChange = false
                    dateDialog = false
                    tripPlannerController.fetchTrip()
                } label: {
                    Text("Done").fontWeight(.semibold).frame(minWidth: 44.0, minHeight: 44.0).contentShape(Rectangle())
                }
                Spacer()
            }
            .padding(.bottom, bottomPadding)
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .task(id: proxy.size.height) {
                        sheetContentHeight = proxy.size.height
                    }
            }
        }
        // Reads the safe area where the sheet ends, not where the content ends: that moves with the sheet's height,
        // which follows the padding, and would resize the sheet in a loop.
        .frame(maxHeight: .infinity)
        .background {
            GeometryReader { proxy in
                Color.clear
                    .task(id: proxy.safeAreaInsets.bottom) {
                        bottomPadding = max(16.0 - proxy.safeAreaInsets.bottom, 0.0)
                    }
            }
        }
        .presentationDetents([.height(sheetContentHeight)])
        .onDisappear {
            if unfetchedChange {
                tripPlannerController.fetchTrip()
            }
        }
    }
}
