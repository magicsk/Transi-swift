//
//  TransiApp.swift
//  Transi
//
//  Created by magic_sk on 05/11/2022.
//

import SwiftUI

@main
struct TransiApp: App {
    @State private var selection = 1
    @State private var urlErrorAlert = false
    @State private var changelog: Changelog?
    @Environment(\.scenePhase) private var scenePhase

    init() {
        GlobalController.appLaunch()
    }

    var body: some Scene {
        WindowGroup {
            ContentView(selectedIndex: $selection)
                .ignoresSafeArea()
                .onReceive(GlobalController.appState.$pendingNavigation.compactMap { $0 }) { dest in
                    GlobalController.appState.pendingNavigation = nil
                    switch dest {
                    case .trip:
                        selection = 0
                    case .activeTrip:
                        selection = 0
                        // A tap on a scheduled trip's Live Activity is what starts following it.
                        GlobalController.tripSchedule.sync(opened: true)
                        // Just the planner once the trip is no longer followed.
                        GlobalController.appState.pendingJourney = GlobalController.tripLiveActivity.journey
                    case .journey(let journey):
                        selection = 0
                        GlobalController.appState.pendingJourney = journey
                    case .table(let stopId, let expandConnection):
                        selection = 1
                        if let exp = expandConnection {
                            GlobalController.virtualTable.changeStop(stopId, expandConnection: exp)
                        } else {
                            GlobalController.virtualTable.changeStop(stopId)
                        }
                    case .timetable(let line):
                        selection = 2
                        GlobalController.appState.pendingTimetableLine = line
                    case .map(let stopId):
                        selection = 3
                        GlobalController.appState.openedURL = URL(string: "transi://map/\(stopId)")
                    }
                }
                .onOpenURL { url in
                    switch url.host {
                    case "trip":
                        GlobalController.appState.pendingNavigation = url.path == "/active" ? .activeTrip : .trip
                    case "table":
                        if url.pathComponents.endIndex >= 2, let stopId = Int(url.pathComponents[1]) {
                            let expandConnection = url.pathComponents.endIndex >= 3 ? url.pathComponents[2] : nil
                            GlobalController.appState.pendingNavigation = .table(stopId: stopId, expandConnection: expandConnection)
                        } else {
                            selection = 1
                        }
                    case "timetable":
                        let line = url.pathComponents.endIndex >= 2 ? url.pathComponents[1] : nil
                        GlobalController.appState.pendingNavigation = .timetable(line: line)
                    case "map":
                        selection = 3
                        GlobalController.appState.openedURL = url
                    default:
                        urlErrorAlert = true
                    }
                }
                .alert(
                    "Unable to navigate",
                    isPresented: $urlErrorAlert
                ) {} message: {
                    Text("Openned url is either expired or no longer supported.")
                }
                .sheet(item: $changelog) { ChangelogView(changelog: $0) }
                .onReceive(GlobalController.tripLiveActivity.$state) { TripQuestionAlert.update($0) }
                .onAppear {
                    Changelog.fetchIfUpdated { notes in
                        // Presenting over the URL alert or another sheet would dismiss or drop it; retry next launch instead.
                        let root = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.rootViewController
                        if !urlErrorAlert, root?.presentedViewController == nil {
                            changelog = notes
                        }
                    }
                }
        }
        .onChange(of: scenePhase) { phase in
            GlobalController.scenePhaseChange(phase)
            if phase == .active {
                // In case something else was on top when the trip started asking.
                TripQuestionAlert.update(GlobalController.tripLiveActivity.state)
            }
        }
    }
}

/// Asks the trip's question over whatever is on screen, with the Live Activity's two answers, and takes the dialog down
/// once the question is answered or settled by itself. A UIKit alert, as the trip detail is a UIKit sheet.
private enum TripQuestionAlert {
    private static weak var shown: UIAlertController?

    static func update(_ state: TripActivityAttributes.ContentState?) {
        guard let state, state.step == .question else {
            shown?.dismiss(animated: true)
            return
        }
        if let shown {
            shown.title = state.title
            shown.message = state.detail
            return
        }
        var top = (UIApplication.shared.connectedScenes.first as? UIWindowScene)?.windows.first?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        guard let top, !(top is UIAlertController) else { return }
        let alert = UIAlertController(title: state.title, message: state.detail, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString("I'm on it", comment: ""), style: .default) { _ in
            GlobalController.tripLiveActivity.keepFollowing()
        })
        alert.addAction(UIAlertAction(title: NSLocalizedString("Other connections", comment: ""), style: .default) { _ in
            GlobalController.tripLiveActivity.confirmMissed()
        })
        top.present(alert, animated: true)
        shown = alert
    }
}
