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
    @State private var sheetContentHeight = 270.0
    /// Keeps Now and Done off the sheet's edge where it has no bottom safe area: floating on iPad and the Mac, or on
    /// iPhones with a Home button.
    @State private var bottomPadding = 0.0

    init(_ dateDialog: Binding<Bool>) {
        _dateDialog = dateDialog
        _adDate = State(initialValue: GlobalController.tripPlanner.arrivalDepartureDate)
    }
    
    var body: some View {
        VStack(spacing: .zero) {
            Text(
                tripPlannerController.arrivalDeparture == ArrivalDeparture.arrival ? "Arrival" : "Departure"
            )
            .font(.system(size: 24.0, weight: .semibold))
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
            }
            HStack {
                Spacer()
                Button("Now") {
                    tripPlannerController.arrivalDepartureCustomDate = false
                    tripPlannerController.arrivalDepartureDate = Date()
                    dateDialog = false
                    tripPlannerController.fetchTrip()
                }
                Spacer()
                Button("Done") {
                    dateDialog = false
                    tripPlannerController.fetchTrip()
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
    }
}
