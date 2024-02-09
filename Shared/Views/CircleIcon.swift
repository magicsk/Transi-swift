//
//  CircleIcon.swift
//  Transi
//
//  Created by magic_sk on 04/02/2024.
//

import SwiftUI

struct CircleIcon: View {
    private let systemName: String
    private let iconColor: Color
    private let backgroundColor: Color
    
    init(_ systemName: String, _ iconColor: Color, _ backgroundColor: Color) {
        self.systemName = systemName
        self.iconColor = iconColor
        self.backgroundColor = backgroundColor
    }
    
    var body: some View {
        Image(systemName: systemName)
            .foregroundColor(iconColor)
            .font(.system(size: 10.5))
            .padding(.horizontal, 14.0)
            .background(Circle().foregroundColor(backgroundColor).frame(width: 20.0, height: 20.0))
    }
}

#Preview {
    CircleIcon("circle.inset.filled", .white, .systemFill)
}
