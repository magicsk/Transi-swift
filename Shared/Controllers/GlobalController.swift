//
//  GlobalController.swift
//  Transi
//
//  Created by magic_sk on 10/02/2024.
//

import CoreLocation
import SwiftUI

struct GlobalController {
    static let magicApiBaseUrl = (Bundle.main.infoDictionary?["MAGIC_API_URL"] as? String)!
    static let iApiBaseUrl = (Bundle.main.infoDictionary?["I_API_URL"] as? String)!
    static let bApiBaseUrl = (Bundle.main.infoDictionary?["B_API_URL"] as? String)!
    static let rApiBaseUrl = (Bundle.main.infoDictionary?["R_API_URL"] as? String)!
    static let bApiKey = (Bundle.main.infoDictionary?["B_API_KEY"] as? String)!
    static let rApiKey = (Bundle.main.infoDictionary?["R_API_KEY"] as? String)!
    static let thunderforestApiUrl = (Bundle.main.infoDictionary?["THUNDERFOREST_API_URL"] as? String)!
    static let thunderforestApiKey = (Bundle.main.infoDictionary?["THUNDERFOREST_API_KEY"] as? String)!

    static let appState = AppStateProvider()
    static let locationProvider = LocationProvider()
    static let stopsListProvider = StopsListProvider()
    static let virtualTable = VirtualTableController()
    static let tripPlanner = TripPlannerController()

    static var sessionToken = ""
    static var shouldRunInBackground = false
    var sessionTokenError = false

    static func appLaunch() {
        registerForNotifications()
        registerUserDefaults()
        fetchSessionToken()
        VirtualTableLiveActivityController.activateExistingActitivites()
    }

    static func scenePhaseChange(_ phase: ScenePhase) {
        appState.phase = phase
        _ = VirtualTableLiveActivityController.listAllTabActivities()
        switch phase {
            case .background:
                virtualTable.disconnect()
                if shouldRunInBackground {
                    locationProvider.decreaseAccuracy()
                } else {
                    locationProvider.stopUpdatingLocation()
                }
            case .active:
                locationProvider.startUpdatingLocation()
                virtualTable.connect()
            default:
                break
        }
    }

    static func startBackgroundMode() {
        shouldRunInBackground = true
        if locationProvider.locationManager.authorizationStatus != .authorizedAlways {
            locationProvider.locationManager.requestAlwaysAuthorization()
        }
        cancelApplicationQuitNotification()
        scheduleApplicationQuitNotification()
    }

    static func stopBackgroundMode() {
        shouldRunInBackground = false
        cancelApplicationQuitNotification()
        DispatchQueue.global().asyncAfter(deadline: .now() + 6) {
            if !shouldRunInBackground, appState.phase == .background {
                locationProvider.stopUpdatingLocation()
            }
        }
    }

    private static func registerUserDefaults() {
        UserDefaults.standard.register(defaults: [Stored.tripSaveDuration: -1, Stored.tripMaxTransfers: 3, Stored.tripMaxWalkDuration: 15, Stored.liveActivitiesSounds: true])
    }

    private static func fetchSessionToken() {
        let sessionRequestBody = SessionReq()
        let jsonBody = try! JSONEncoder().encode(sessionRequestBody)

        fetchBApiPost(endpoint: "/mobile/v1/startup", jsonBody: jsonBody, type: Session.self) { result in
            switch result {
            case .success(let data):
                sessionToken = data.session
            case .failure(let error):
                print(error)
            }
        }
    }

    private static func registerForNotifications() {
        let category = UNNotificationCategory(identifier: "Transi", actions: [], intentIdentifiers: [])
        UNUserNotificationCenter.current().setNotificationCategories([category])
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
        }
    }

    static func cancelApplicationQuitNotification() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["eu.magicsk.Transi.AppStoppedRunning"])
    }

    static func scheduleApplicationQuitNotification() {
        let delay = 5 as TimeInterval

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("App Stopped Running", comment: "")
        content.body = NSLocalizedString("Tap this notification to resume live activity.", comment: "")
        content.sound = .defaultCritical

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay + 1, repeats: false)

        let request = UNNotificationRequest(identifier: "eu.magicsk.Transi.AppStoppedRunning", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            if shouldRunInBackground {
                self.scheduleApplicationQuitNotification()
            }
        }
    }

    static func getSessionToken(_ retry: Int = 0) -> String {
        if sessionToken != "" {
            return sessionToken
        }
        if retry > 5 {
            return ""
        }
        fetchSessionToken()
        sleep(1)
        return getSessionToken(retry + 1)
    }

    static func getNearestStopId() -> Int {
        return stopsListProvider.stops.first(where: { $0.id > 0 })?.id ?? 20
    }

    static func getNearestStationId() -> Int {
        return stopsListProvider.stops.first(where: { $0.id > 0 })?.stationId ?? 0
    }

    static func getStopById(_ id: Int) -> Stop? {
        return stopsListProvider.stops.first(where: { $0.id == id })
    }
}
