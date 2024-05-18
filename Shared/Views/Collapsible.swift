//
//  Collapsible.swift
//  Transi
//
//  Created by magic_sk on 02/03/2024.
//

import SwiftUI

struct Collapsible<Content: View, Label: View>: View {
    @State var label: () -> Label
    @State var content: () -> Content
    
    @State private var collapsed: Bool = true
    
    var body: some View {
        VStack {
            Button(
                action: { self.collapsed.toggle() },
                label: {
                    HStack {
                        self.label()
                    }
                    .padding(.bottom, 1)
                    .background(Color.white.opacity(0.01))
                }
            )
            .buttonStyle(PlainButtonStyle())
            
            VStack {
                self.content()
            }
            .opacity(collapsed ? 0 : 1)
            .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: collapsed ? 0 : .none)
            .animation(.easeOut, value: collapsed)
            .transition(.slide)
        }
    }
}
