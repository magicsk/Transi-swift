//
//  AppStateProvider.swift
//  Transi
//
//  Created by magic_sk on 06/05/2024.
//

import SwiftUI

class AppStateProvider: ObservableObject {
    @Published var scene: ScenePhase = .active
    @Published var openedURL: URL? = nil
}
