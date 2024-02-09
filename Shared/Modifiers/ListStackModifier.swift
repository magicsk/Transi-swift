//
//  ListStackModifier.swift
//  Transi
//
//  Created by magic_sk on 15/05/2023.
//

import SwiftUI

struct ListStackModifier: ViewModifier {
    func body(content: Content) -> some View {
        ZStack {
            content
                .padding(.vertical, 12.0)
                .frame(maxWidth: .infinity)
                .background(.secondarySystemGroupedBackground)
                .cornerRadius(10.0)
                .padding(.all, 20.0)
            HStack {
                VStack(spacing: 3.5) {
                    ForEach(1 ... 3, id: \.self) { _ in
                        Circle()
                            .foregroundColor(.quaternaryLabel)
                            .frame(width: 3.5, height: 3.5)
                    }
                }
                Spacer()
            }.padding(.all, 38.5)
        }
    }
}
