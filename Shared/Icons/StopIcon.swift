//
//  StopIcon.swift
//  Transi
//
//  Created by magic_sk on 28/02/2024.
//

import SwiftUI

struct StopIcon: View {
    var color: Color
    
    init(_ color: Color = Color.systemGray) {
        self.color = color
    }
    
    var body: some View {
        Image("stop")
            .resizable(resizingMode: .stretch)
            .foregroundColor(color)
            .frame(width: 7.0, height: 10.0)
    }
}

#Preview {
    StopIcon()
}
