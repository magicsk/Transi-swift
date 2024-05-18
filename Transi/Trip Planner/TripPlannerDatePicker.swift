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
    @State private var adDate = Date()
    @State private var arrivalDepartureSetNow = false
    @State private var sheetContentHeight = 270.0

    init(_ dateDialog: Binding<Bool>) {
        _dateDialog = dateDialog
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
                if arrivalDepartureSetNow {
                    tripPlannerController.arrivalDepartureCustomDate = false
                    arrivalDepartureSetNow = false
                } else {
                    tripPlannerController.arrivalDepartureCustomDate = true
                }
            }
            HStack {
                Spacer()
                Button("Now") {
                    arrivalDepartureSetNow = true
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
