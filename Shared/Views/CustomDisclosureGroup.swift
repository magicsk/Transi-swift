//
//  CustomDisclosureGroup.swift
//  Transi
//
//  Created by magic_sk on 06/10/2024.
//

import SwiftUI

struct CustomDisclosureGroup<Label: View, Content: View>: View {
    let label: Label
    let content: Content
    @Binding var isExpanded: Bool
    
    init(
        isExpanded: Binding<Bool>,
        @ViewBuilder label: () -> Label,
        @ViewBuilder content: () -> Content
    ) {
        self._isExpanded = isExpanded
        self.label = label()
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
//                withAnimation(.easeInOut(duration: 0.3)) {
                    isExpanded.toggle()
//                }
            }) {
                HStack {
                    label
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
            }
            
            if isExpanded {
                content
                    .padding(.leading)
            }
        }
    }
}
