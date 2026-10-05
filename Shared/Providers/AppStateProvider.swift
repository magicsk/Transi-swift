//
//  AppStateProvider.swift
//  Transi
//
//  Created by magic_sk on 06/05/2024.
//

import SwiftUI

enum NavigationDestination {
    case trip
    /// The detail of the trip the Live Activity follows, in the planner.
    case activeTrip
    case table(stopId: Int, expandConnection: String? = nil)
    case timetable(line: String? = nil)
    case map(stopId: Int)
}

class AppStateProvider: ObservableObject {
    @Published var phase: ScenePhase = .active
    @Published var openedURL: URL? = nil
    @Published var pendingNavigation: NavigationDestination? = nil
    @Published var pendingTimetableLine: String? = nil
    @Published var pendingJourney: Journey? = nil
}
