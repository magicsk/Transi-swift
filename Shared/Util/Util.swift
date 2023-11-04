//
//  Util.swift
//  Transi
//
//  Created by magic_sk on 04/11/2023.
//

import Foundation

func getPlatformLabel(_ labels: [PlatformLabel]?, _ platform: Int) -> String {
    return labels?.first(where: { Int($0.id) ?? 0 == platform })?.label ?? ""
}
