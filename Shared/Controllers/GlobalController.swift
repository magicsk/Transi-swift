//
//  GlobalController.swift
//  Transi
//
//  Created by magic_sk on 10/02/2024.
//

import CoreLocation
import Foundation

struct GlobalController {
    static let magicApiBaseUrl = (Bundle.main.infoDictionary?["MAGIC_API_URL"] as? String)!
    static let iApiBaseUrl = (Bundle.main.infoDictionary?["I_API_URL"] as? String)!
    static let bApiBaseUrl = (Bundle.main.infoDictionary?["B_API_URL"] as? String)!
    static let rApiBaseUrl = (Bundle.main.infoDictionary?["R_API_URL"] as? String)!
    static let bApiKey = (Bundle.main.infoDictionary?["B_API_KEY"] as? String)!
    static let rApiKey = (Bundle.main.infoDictionary?["R_API_KEY"] as? String)!

    static let locationProvider = LocationProvider()
    static let stopsListProvider = StopsListProvider()
    static let virtualTable = VirtualTableController()
    static let tripPlanner = TripPlannerController()

    static var sessionToken = ""
    var sessionTokenError = false

    init() {
        registerUserDefaults()
        GlobalController.fetchSessionToken()
    }

    private func registerUserDefaults() {
        UserDefaults.standard.register(defaults: [Stored.tripSaveDuration: -1, Stored.tripMaxTransfers: 3, Stored.tripMaxWalkDuration: 15])
    }

    private static func fetchSessionToken() {
        let sessionRequestBody = SessionReq()
        let jsonBody = try! JSONEncoder().encode(sessionRequestBody)

        fetchBApiPost(endpoint: "/mobile/v1/startup", jsonBody: jsonBody, type: Session.self) { result in
            switch result {
            case .success(let data):
                GlobalController.sessionToken = data.session
            case .failure(let error):
                print(error)
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
