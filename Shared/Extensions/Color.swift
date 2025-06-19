//
//  Color.swift
//  Transi
//
//  Created by magic_sk on 15/05/2023.
//

import SwiftUI
import SwiftUIX

extension Color {     
    // MARK: - Text Colors
    static let lightText = Color(UIColor.lightText)
    static let darkText = Color(UIColor.darkText)
    static let placeholderText = Color(UIColor.placeholderText)

    // MARK: - Label Colors
    static let label = Color(UIColor.label)
    static let secondaryLabel = Color(UIColor.secondaryLabel)
    static let tertiaryLabel = Color(UIColor.tertiaryLabel)
    static let quaternaryLabel = Color(UIColor.quaternaryLabel)

    // MARK: - Background Colors
    static let systemBackground = Color(UIColor.systemBackground)
    static let secondarySystemBackground = Color(UIColor.secondarySystemBackground)
    static let tertiarySystemBackground = Color(UIColor.tertiarySystemBackground)
    
    // MARK: - Fill Colors
    static let systemFill = Color(UIColor.systemFill)
    static let secondarySystemFill = Color(UIColor.secondarySystemFill)
    static let tertiarySystemFill = Color(UIColor.tertiarySystemFill)
    static let quaternarySystemFill = Color(UIColor.quaternarySystemFill)
    
    // MARK: - Grouped Background Colors
    static let systemGroupedBackground = Color(UIColor.systemGroupedBackground)
    static let secondarySystemGroupedBackground = Color(UIColor.secondarySystemGroupedBackground)
    static let tertiarySystemGroupedBackground = Color(UIColor.tertiarySystemGroupedBackground)
    
    // MARK: - Gray Colors
    static let systemGray = Color(UIColor.systemGray)
    static let systemGray2 = Color(UIColor.systemGray2)
    static let systemGray3 = Color(UIColor.systemGray3)
    static let systemGray4 = Color(UIColor.systemGray4)
    static let systemGray5 = Color(UIColor.systemGray5)
    static let systemGray6 = Color(UIColor.systemGray6)
    
    // MARK: - Other Colors
    static let separator = Color(UIColor.separator)
    static let opaqueSeparator = Color(UIColor.opaqueSeparator)
    static let link = Color(UIColor.link)
    
    // MARK: System Colors
    static let systemBlue = Color(UIColor.systemBlue)
    static let systemPurple = Color(UIColor.systemPurple)
    static let systemGreen = Color(UIColor.systemGreen)
    static let systemYellow = Color(UIColor.systemYellow)
    static let systemOrange = Color(UIColor.systemOrange)
    static let systemPink = Color(UIColor.systemPink)
    static let systemRed = Color(UIColor.systemRed)
    static let systemTeal = Color(UIColor.systemTeal)
    static let systemIndigo = Color(UIColor.systemIndigo)

    // MARK: Line Colors
    static let l1 = Color(hexadecimal: "ec691f")
    static let l2 = Color(hexadecimal: "393185")
    static let l3 = Color(hexadecimal: "e31e24")
    static let l4 = Color(hexadecimal: "5171b9")
    static let l5 = Color(hexadecimal: "db821a")
    static let l6 = Color(hexadecimal: "eb609d")
    static let l7 = Color(hexadecimal: "ffed03")
    static let l8 = Color(hexadecimal: "4d897c")
    static let l9 = Color(hexadecimal: "889923")
    static let l21 = Color(hexadecimal: "338632")
    static let ln21 = Color(hexadecimal: "54c279")
    static let ln29 = Color(hexadecimal: "bbc79a")
    static let ln31 = Color(hexadecimal: "ddf8de")
    static let l33 = Color(hexadecimal: "7468ac")
    static let ln33 = Color(hexadecimal: "b1a4e1")
    static let ln34 = Color(hexadecimal: "78b1dc")
    static let l37 = Color(hexadecimal: "e31e24")
    static let ln37 = Color(hexadecimal: "ffa5b4")
    static let l40 = Color(hexadecimal: "e51a4b")
    static let l42 = Color(hexadecimal: "a65430")
    static let l44 = Color(hexadecimal: "b84a94")
    static let ln44 = Color(hexadecimal: "d780c8")
    static let l47 = Color(hexadecimal: "af8e13")
    static let ln47 = Color(hexadecimal: "fcc802")
    static let l49 = Color(hexadecimal: "d36d1e")
    static let l50 = Color(hexadecimal: "075369")
    static let ln53 = Color(hexadecimal: "82d7df")
    static let ln55 = Color(hexadecimal: "fadf17")
    static let ln56 = Color(hexadecimal: "c1ea8b")
    static let l60 = Color(hexadecimal: "2b4493")
    static let l61 = Color(hexadecimal: "a21517")
    static let ln61 = Color(hexadecimal: "fb7373")
    static let l63 = Color(hexadecimal: "642f6c")
    static let l64 = Color(hexadecimal: "0e562c")
    static let l68 = Color(hexadecimal: "897917")
    static let ln70 = Color(hexadecimal: "ffd8a8")
    static let l71 = Color(hexadecimal: "047db3")
    static let l72 = Color(hexadecimal: "899d1c")
    static let ln72 = Color(hexadecimal: "bbd702")
    static let ln74 = Color(hexadecimal: "b5f1bb")
    static let ln80 = Color(hexadecimal: "feae46")
    static let l83 = Color(hexadecimal: "0e7bba")
    static let ln91 = Color(hexadecimal: "fff4b3")
    static let l93 = Color(hexadecimal: "ab075f")
    static let ln93 = Color(hexadecimal: "e43692")
    static let l95 = Color(hexadecimal: "ec6a1f")
    static let ln95 = Color(hexadecimal: "ee6901")
    static let l96 = Color(hexadecimal: "3fa03b")
    static let l98 = Color(hexadecimal: "b45c2e")
    static let ln99 = Color(hexadecimal: "f6b4d5")
    static let l141 = Color(hexadecimal: "aad29b")
    static let l245 = Color(hexadecimal: "bcb5da")
    static let l255 = Color(hexadecimal: "acd086")
    static let l256 = Color(hexadecimal: "ea5558")
    static let l257 = Color(hexadecimal: "6caddf")
    static let l258 = Color(hexadecimal: "9d9e9e")
    static let l269 = Color(hexadecimal: "a2d9f7")
    static let l523 = Color(hexadecimal: "ea544a")
    static let l525 = Color(hexadecimal: "af9778")
    static let l530 = Color(hexadecimal: "33b7bc")
    static let l540 = Color(hexadecimal: "78b833")
    static let l610 = Color(hexadecimal: "d4a31d")
    static let l620 = Color(hexadecimal: "f6bfd9")
    static let l632 = Color(hexadecimal: "eed502")
    static let l720 = Color(hexadecimal: "fabc48")
    static let l737 = Color(hexadecimal: "ea533d")
    static let train = Color(hexadecimal: "166dd4")
    static let AT_train = Color(hexadecimal: "ff671f")
    static let night = Color(hexadecimal: "2b2a29")
    static let night_regio = Color(hexadecimal: "000000")
    static let replacement = Color(hexadecimal: "ef7f1a")
    static let regio = Color(hexadecimal: "bfbfb9")
    static let ldefault = Color(hexadecimal: "52595c")
}
