//
//  TripPlannerDatePicker.swift
//  Transi
//
//  Created by magic_sk on 29/01/2024.
//

import SwiftUI

struct TripPlannerDatePicker: View {
    @ObservedObject var dataProvider: DataProvider
    @Binding private var arrivalDepratureCustomDate: Bool
    @Binding private var dateDialog: Bool
    @State private var arrivalDepratureSetNow = false
    @State private var sheetContentHeight = 270.0

    init(_ dataProvider: DataProvider,_ dateDialog: Binding<Bool> ,_ arrivalDepratureCustomDate: Binding<Bool>) {
        self.dataProvider = dataProvider
        _dateDialog = dateDialog
        _arrivalDepratureCustomDate = arrivalDepratureCustomDate
    }
    
    var body: some View {
        VStack(spacing: .zero) {
            Text(
                dataProvider.tripArrivalDeprature == ArrivalDeparture.arrival ? "Arrival" : "Departure"
            )
            .font(.system(size: 24.0, weight: .semibold))
            .padding(.top, 5.0)
            DatePicker(
                "Select date",
                selection: $dataProvider.tripArrivalDepratureDate,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .onChange(of: dataProvider.tripArrivalDepratureDate) { _ in
                if arrivalDepratureSetNow {
                    arrivalDepratureCustomDate = false
                    arrivalDepratureSetNow = false
                } else {
                    arrivalDepratureCustomDate = true
                }
            }
            HStack {
                Spacer()
                Button("Now") {
                    arrivalDepratureSetNow = true
                    dataProvider.tripArrivalDepratureDate = Date()
                    dateDialog = false
                    dataProvider.fetchTrip()
                }
                Spacer()
                Button("Done") {
                    dateDialog = false
                    dataProvider.fetchTrip()
                }
                Spacer()
            }
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .task {
                        print("size = \(proxy.size.height)")
                        sheetContentHeight = proxy.size.height
                    }
            }
        }
        .presentationDetents([.height(sheetContentHeight)])
    }
}
