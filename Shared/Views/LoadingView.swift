//
//  LoadingView.swift
//  Transi
//
//  Created by magic_sk on 18/02/2024.
//

import SwiftUI

struct LoadingView: View {
    private var background = AnyView(Color.clear.background(.ultraThinMaterial).blur(radius: 10))
    @Binding var visible: Bool
    
    init(_ visible: Binding<Bool> = .constant(true)) {
        _visible = visible
    }
    
    var body: some View {
        LoadingIndicator()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(background)
            .visible(visible)
            .animation(.easeInOut(duration: 0.25), value: visible)
    }
}

extension LoadingView {
    func overlayBackground<Background>(_ style: Background) -> LoadingView where Background : View {
        var newView = self
        newView.background = AnyView(style)
        return newView
    }
}

#Preview {
    LoadingView()
}
