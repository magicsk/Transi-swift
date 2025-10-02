//
//  NowIndicator.swift
//  Transi
//
//  Created by magic_sk on 06/02/2024.
//

import SwiftUI

struct NowIndicator: View {
    @State private var firstOpacity: CGFloat = 0.0
    @State private var secondOpacity: CGFloat = 1.0
    private let justStroke: Bool

    init(_ justStroke: Bool = false) {
        self.justStroke = justStroke
    }

    var body: some View {
        HStack(spacing: 5.0) {
            Circle()
                .ifCondition(justStroke) { circle in
                    circle.stroke(Color.label, lineWidth: 1.5)
                }
                .opacity(firstOpacity)
                .foregroundStyle(Color.label)
                .frame(width: 15.0, height: 15.0)
            Circle()
                .ifCondition(justStroke) { circle in
                    circle.stroke(Color.label, lineWidth: 1.5)
                }
                .opacity(secondOpacity)
                .foregroundStyle(Color.label)
                .frame(width: 15.0, height: 15.0)
        }
        .padding(.horizontal, 2.5)
        .onAppear(perform: {
            firstOpacity = 0
            secondOpacity = 1
            let baseAnimation = Animation.easeInOut(duration: 1)
            let repeated = baseAnimation.repeatForever(autoreverses: true)

            withAnimation(repeated) {
                firstOpacity = 1
                secondOpacity = 0
            }
        })
    }
}

#Preview {
    VStack(spacing: 35.0) {
        NowIndicator()
        NowIndicator(true)
    }
}
