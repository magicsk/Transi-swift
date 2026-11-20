//
//  Util.swift
//  Transi
//
//  Created by magic_sk on 04/11/2023.
//

import Foundation
import SwiftUI

func getPlatformLabel(_ labels: [PlatformLabel]?, _ platform: Int) -> String {
    return labels?.first(where: { Int($0.id) ?? 0 == platform })?.label ?? ""
}

/// The platform letter to show; the stop data marks platforms it doesn't know with "-".
func shownPlatformLabel(_ labels: [PlatformLabel]?, _ platform: Int) -> String {
    let label = getPlatformLabel(labels, platform)
    return label == "-" ? "" : label
}

func getDelayColor(_ delay: Int, _ type: String) -> Color {
    if type != "online" {
        return .systemGray
    }
    switch delay {
        case 0...1:
            return .systemGreen

        case 2...3:
            return .systemOrange

        case 4...999:
            return .systemRed

        default:
            return .systemPurple
    }
}
