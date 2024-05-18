//
//  NoDeparturesIcon.swift
//  Transi
//
//  Created by magic_sk on 18/02/2024.
//

import SwiftUI

struct NoDeparturesIcon: View {
    var body: some View {
        ZStack {
            Image(systemName: "bus.fill")
                .font(.system(size: 96.0, weight: .light))
                .foregroundColor(.tertiaryLabel)

            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 50.0, weight: .light))
                .foregroundColor(.tertiaryLabel)
                .padding(1.0)
                .backgroundFill(.systemBackground)
                .cornerRadius(.infinity)
                .offset(x: 37.5, y: 45.0)
        }.padding(15.0)
    }
}

#Preview {
    VStack {
        NoDeparturesIcon()
        Text("There are no departures at this time.").foregroundColor(.secondaryLabel)
    }
}
