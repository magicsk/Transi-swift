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
        Button(action: {dateDialog = true}) {
            Text(customDate ? formatter.string(from: date) : "now")
                .padding(.vertical, 6.0)
                .frame(maxWidth: .infinity)
                .background(.secondarySystemGroupedBackground)
                .cornerRadius(26.0)
                .padding(.leading, 10.0)
        }
    }
}

#Preview {
    ZStack {
        Color.systemGroupedBackground.edgesIgnoringSafeArea(.all)
        TripPlannerDateButton(.constant(.now), dateDialog: .constant(false), customDate: false)
    }
}
