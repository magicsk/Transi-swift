//
//  LoadingIndicator.swift
//  Transi
//
//  Created by magic_sk on 18/02/2024.
//

import SwiftUI

struct LoadingIndicator: View {
    var body: some View {
        VStack {
            ProgressView()
                .progressViewStyle(.circular)
                .padding(.bottom, 2.5)
            Text("Loading...")
                .foregroundColor(.secondaryLabel)
        }
    }
}

#Preview {
    LoadingIndicator()
}
