//
//  StopIcon.swift
//  Transi
//
//  Created by magic_sk on 28/02/2024.
//

import SwiftUI
struct StopIcon: View {
    var color: Color = Color.systemGray
    var scale: CGFloat = 1.0
    
    var body: some View {
        Image("stop")
            .resizable(resizingMode: .stretch)
            .foregroundColor(color)
            .frame(width: scale * 7.0, height: scale * 10.0)
    }
}

#Preview {
    StopIcon()
}
