//
//  LineText.swift
//  Transi
//
//  Created by magic_sk on 03/10/2023.
//

import SwiftUI

struct LineText: View {
    var lineNum: String
    var size: CGFloat
    var isDirectionSign: Bool

    init(_ lineNum: String, _ size: CGFloat = 28.0) {
        self.lineNum = lineNum
        self.size = size
        isDirectionSign = lineNum == "►"
    }

    var body: some View {
        Text(lineNum)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(textColorFromLineNum(lineNum)!)
            .offset(x: isDirectionSign ? 1.0 : 0.0, y: isDirectionSign ? -2.5 : 0.0)
            .lineLimit(1)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical,  size * 0.14)
            .padding(.horizontal,isDirectionSign ? size * 0.55 : size * 0.21)
            .width(Int(lineNum) ?? 99 < 10 ? size*1.57 : nil)
            .background(
                RoundedRectangle(cornerRadius: isRounded(lineNum) ? 100.0 : 4.0, style: .circular)
                    .fill(colorFromLineNum(lineNum)!)
            )
    }
}

#Preview {
    VStack {
        HStack {
            LineText("1")
            LineText("3")
            LineText("14")
        }
        HStack {
            LineText("21")
            LineText("71")
            LineText("147", 18.0)
        }
        HStack {
            LineText("►")
            LineText("X70", 18.0)
            LineText("N72", 18.0)
        }
        HStack {
            LineText("AT1")
            LineText("S8")
            LineText("R60", 18.0)
        }
    }
}
