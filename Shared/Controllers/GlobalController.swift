//
//  GlobalController.swift
//  Transi
//
//  Created by magic_sk on 10/02/2024.
//

import CoreLocation
import SwiftUI

struct GlobalController {
    private static let _defaultMagicApiBaseUrl = (Bundle.main.infoDictionary?["MAGIC_API_URL"] as? String)!
    static var magicApiBaseUrl: String {
        let override = UserDefaults.standard.string(forKey: Stored.magicApiUrlOverride) ?? ""
        return override.isEmpty ? _defaultMagicApiBaseUrl : override
    }
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
    #if os(iOS)
    static let tripLiveActivity = TripLiveActivityController()
    static let tripSchedule = TripScheduleController()
    #endif
    static let timetableDatabase = TimetableDatabase()
    static let ticketCatalogue = TicketCatalogueProvider()
    static let watchSync = WatchSyncController()

    private static let tokenLock = NSLock()
    private static var _sessionToken = ""
    private static var tokenWaiters = [DispatchSemaphore]()
    private static var isTokenFetchInFlight = false

    static var sessionToken: String {
        get {
            tokenLock.lock()
            defer { tokenLock.unlock() }
            return _sessionToken
        }
        set {
            tokenLock.lock()
            _sessionToken = newValue
            let waiters = tokenWaiters
            tokenWaiters.removeAll()
            isTokenFetchInFlight = false
            tokenLock.unlock()
            for sem in waiters {
                sem.signal()
            }
        }
    }

    static var shouldRunInBackground = false
    var sessionTokenError = false

    static func appLaunch() {
        #if os(iOS)
        // Before launch finishes, or the tap that launched the app is lost.
        UNUserNotificationCenter.current().delegate = tripSchedule
        registerForNotifications()
        #endif
        registerUserDefaults()
        fetchSessionToken()
        watchSync.activate()
        #if os(iOS)
        VirtualTableLiveActivityController.activateExistingActitivites()
        tripLiveActivity.restore()
        // After the restore, so an answer from the trip Live Activity that relaunched the app finds its trip.
        TripQuestion.answer = { await tripLiveActivity.answer(stillOn: $0) }
        tripSchedule.sync()
        #endif
        if timetableDatabase.shouldMaintainOfflineDatabase {
            _ = timetableDatabase.openDatabases()
            timetableDatabase.checkAndUpdate()
        }
    }

    static func scenePhaseChange(_ phase: ScenePhase) {
        appState.phase = phase
        #if os(iOS)
        _ = VirtualTableLiveActivityController.listAllTabActivities()
        #endif
        switch phase {
            case .background:
                virtualTable.disconnect()
                watchSync.sendState()
                #if os(iOS)
                if shouldRunInBackground {
                    // A followed trip checks where the traveller is, which needs the full accuracy.
                    if !TripLiveActivityController.followsTrip {
                        locationProvider.decreaseAccuracy()
                    }
                } else {
                    locationProvider.stopUpdatingLocation()
                }
                #else
                locationProvider.stopUpdatingLocation()
                #endif
            case .active:
                locationProvider.startUpdatingLocation()
                // A followed trip keeps the full accuracy in the background, so no fresh fix may come to switch the
                // table to where the traveller got to.
                if LocationProvider.lastLocation != nil {
                    stopsListProvider.showNearestStop()
                }
                virtualTable.connect()
                if !LocationProvider.isLocationAvailable {
                    stopsListProvider.setDefaultStopIfNeeded()
                }
                if timetableDatabase.shouldMaintainOfflineDatabase && !timetableDatabase.isReady {
                    _ = timetableDatabase.openDatabases()
                    timetableDatabase.checkAndUpdate()
                }
                #if os(iOS)
                tripSchedule.sync(opened: true)
                tripSchedule.runTappedReminder()
                #endif
            default:
                break
        }
    }

    #if os(iOS)
    static func startBackgroundMode() {
        shouldRunInBackground = true
        if locationProvider.locationManager.authorizationStatus != .authorizedAlways {
            locationProvider.locationManager.requestAlwaysAuthorization()
        }
        cancelApplicationQuitNotification()
        scheduleApplicationQuitNotification()
    }

    static func stopBackgroundMode() {
        guard backgroundModeCanStop(
            tableActivities: VirtualTableLiveActivityController.liveActivities.count,
            followsTrip: TripLiveActivityController.followsTrip
        ) else { return }
        shouldRunInBackground = false
        cancelApplicationQuitNotification()
        DispatchQueue.global().asyncAfter(deadline: .now() + 6) {
            if !shouldRunInBackground, appState.phase == .background {
                locationProvider.stopUpdatingLocation()
            }
        }
    }
    #endif

    private static func registerUserDefaults() {
        UserDefaults.standard.register(defaults: [
            Stored.tripSaveDuration: -1,
            Stored.tripMaxTransfers: 3,
            Stored.tripMaxWalkDuration: 15,
            Stored.liveActivitiesSounds: true,
            Stored.offlineTimetables: false,
            Stored.displayClockOnTable: true,
            Stored.displaySocketStatus: true,
            Stored.defaultStopId: -1,
            Stored.favoriteStopIds: [Int](),
            Stored.liveActivityThreshold: 200,
            Stored.notifyOnTimeChange: true,
            Stored.notifyOnDelayChange: true,
            Stored.notifyOnPositionChange: true,
            Stored.offlineTripPlanner: false,
            Stored.developerSettings: false,
            Stored.passDays: 0,
            Stored.passValidFrom: 0.0,
            Stored.passZones: "100,101",
            Stored.passNetworkWide: false,
            Stored.passBankCard: false,
            Stored.tripReminderMinutes: 15,
            Stored.tripStartMinutes: 15,
            Stored.timetableAllowCellularUpdates: false,
        ])
    }

    private static func fetchSessionToken() {
        tokenLock.lock()
        if isTokenFetchInFlight {
            tokenLock.unlock()
            return
        }
        isTokenFetchInFlight = true
        tokenLock.unlock()

        let sessionRequestBody = SessionReq()
        let jsonBody = try! JSONEncoder().encode(sessionRequestBody)

        fetchBApiPost(endpoint: "/mobile/v1/startup", jsonBody: jsonBody, type: Session.self) { result in
            switch result {
            case .success(let data):
                sessionToken = data.session
            case .failure(let error):
                #if DEBUG
                print(error)
                #endif
                // Signal waiters with empty string so they don't hang forever
                sessionToken = ""
            }
        }
    }

    #if os(iOS)
    // UNUserNotificationCenter calls can block on a synchronous XPC reply from usernotificationsd,
    // so they run off the main thread, in call order, on this serial queue.
    static let notificationQueue = DispatchQueue(label: "eu.magicsk.transi.notifications")

    private static func registerForNotifications() {
        notificationQueue.async {
            let category = UNNotificationCategory(identifier: "Transi", actions: [], intentIdentifiers: [])
            UNUserNotificationCenter.current().setNotificationCategories([category, TripScheduleController.category])
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { _, _ in
            }
        }
    }

    static func cancelApplicationQuitNotification() {
        notificationQueue.async {
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["eu.magicsk.Transi.AppStoppedRunning"])
        }
    }

    static func scheduleApplicationQuitNotification() {
        let delay = 5 as TimeInterval

        notificationQueue.async {
            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString("App Stopped Running", comment: "")
            content.body = NSLocalizedString("Tap this notification to resume live activity.", comment: "")
            content.sound = .defaultCritical

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay + 1, repeats: false)

            let request = UNNotificationRequest(identifier: "eu.magicsk.Transi.AppStoppedRunning", content: content, trigger: trigger)
            UNUserNotificationCenter.current().add(request)
        }

        DispatchQueue.global().asyncAfter(deadline: .now() + delay) {
            if shouldRunInBackground {
                self.scheduleApplicationQuitNotification()
            }
        }
    }
    #endif

    static func getSessionToken() -> String {
        tokenLock.lock()
        if !_sessionToken.isEmpty {
            tokenLock.unlock()
            return _sessionToken
        }
        let sem = DispatchSemaphore(value: 0)
        tokenWaiters.append(sem)
        tokenLock.unlock()

        fetchSessionToken()
        _ = sem.wait(timeout: .now() + 10)
        return sessionToken
    }

    static func getNearestStopId() -> Int {
        return stopsListProvider.stops.first(where: { $0.id > 0 })?.id ?? 20
    }

    /// The trip planner routes between IDS BK stations; railway stations elsewhere in the country have none.
    private static var nearestPlannableStop: Stop? {
        stopsListProvider.stops.first(where: { $0.id > 0 && $0.stationId != nil })
    }

    static func getNearestPlannableStopId() -> Int {
        return nearestPlannableStop?.id ?? 20
    }

    static func getNearestStationId() -> Int {
        return nearestPlannableStop?.stationId ?? 0
    }

    static func getStopById(_ id: Int) -> Stop? {
        return stopsListProvider.stops.first(where: { $0.id == id })
    }
}
