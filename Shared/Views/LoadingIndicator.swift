//
//  LoadingIndicator.swift
//  Transi
//
//  Created by magic_sk on 18/02/2024.
//

import SwiftUI

struct LoadingIndicator: View {
    var text = "Loading…"

    var body: some View {
        VStack {
            ProgressView()
                .progressViewStyle(.circular)
                .padding(.bottom, 2.5)
            Text(text)
                .foregroundColor(.secondaryLabel)
        }
    }
}

#Preview {
    LoadingIndicator()
}
