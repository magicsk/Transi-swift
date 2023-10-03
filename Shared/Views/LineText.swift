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

    init(_ lineNum: String, _ size: CGFloat = 28.0) {
        self.lineNum = lineNum
        self.size = size
    }

    var body: some View {
        Text(lineNum)
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(textColorFromLineNum(lineNum)!)
            .lineLimit(1)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.vertical, size * 0.14)
            .padding(.horizontal, size * 0.21)
            .width(Int(lineNum) ?? 99 < 10 ? size*1.57 : .infinity)
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
            LineText("99")
        }
        HStack {
            LineText("X4")
            LineText("X70")
            LineText("N72")
        }
        HStack {
            LineText("AT1")
            LineText("S8")
            LineText("R60")
        }
    }
}
