//
//  TripPlannerDateButton.swift
//  Transi
//
//  Created by magic_sk on 04/02/2024.
//

import SwiftUI

struct TripPlannerDateButton: View {
    @Binding private var date: Date
    @Binding private var dateDialog: Bool
    private let customDate: Bool
    private let formatter = DateFormatter()

    init(_ date: Binding<Date>, dateDialog: Binding<Bool>, customDate: Bool) {
        _date = date
        _dateDialog = dateDialog
        self.customDate = customDate
        formatter.dateFormat = "d MMM H:mm"
    }

    var body: some View {
        Button(
            customDate ?
                formatter.string(from: date) :
                "now"
        ) {
            dateDialog = true
        }
        .padding(.vertical, 6.0)
        .frame(maxWidth: .infinity)
        .background(.secondarySystemGroupedBackground)
        .cornerRadius(8.0)
        .padding(.leading, 10.0)
    }
}
