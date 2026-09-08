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
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .task {
                        sheetContentHeight = proxy.size.height
                    }
            }
        }
        .presentationDetents([.height(sheetContentHeight)])
    }
}
