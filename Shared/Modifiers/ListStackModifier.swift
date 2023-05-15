//
//  ListStackModifier.swift
//  Transi
//
//  Created by magic_sk on 15/05/2023.
//

import SwiftUI

struct ListStackModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.vertical, 12.0)
            .padding(.leading, 20.0)
            .frame(maxWidth: .infinity)
            .backgroundFill(.secondarySystemGroupedBackground)
            .cornerRadius(10)
            .padding(.all, 20.0)
            .backgroundFill(.systemGroupedBackground)
    }
}
