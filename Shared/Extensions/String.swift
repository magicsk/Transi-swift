//
//  String.swift
//  Transi
//
//  Created by magic_sk on 10/04/2023.
//

import Foundation

extension String {
    func leftPadding(toLength: Int, withPad: String) -> String {
        String(String(reversed()).padding(toLength: toLength, withPad: withPad, startingAt: 0).reversed())
    }
    func simplify() -> String {
        String(folding(options: .diacriticInsensitive, locale: .current).lowercased().trimmingCharacters(in: .whitespaces))
    }
}
