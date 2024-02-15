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

    init() {
        registerUserDefaults()
        GlobalController.fetchSessionToken()
    }

    private func registerUserDefaults() {
        UserDefaults.standard.register(defaults: [Stored.tripSaveDuration: -1, Stored.tripMaxTransfers: 3, Stored.tripMaxWalkDuration: 15])
    }

    private static func fetchSessionToken() {
        var request = URLRequest(url: URL(string: "\(GlobalController.bApiBaseUrl)/mobile/v1/startup/")!)
        let uuid = UUID().uuidString
        let sessionRequestBody = SessionReq(installation: uuid)
        let jsonEncoder = JSONEncoder()
        let jsonBody = try! jsonEncoder.encode(sessionRequestBody)
        request.httpMethod = "POST"
        request.setValue("\(String(describing: jsonBody.count))", forHTTPHeaderField: "Content-Length")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Dalvik/2.1.0 (Linux; U; Android 12; Pixel 6)", forHTTPHeaderField: "User-Agent")
        request.setValue(GlobalController.bApiKey, forHTTPHeaderField: "x-api-key")
        request.httpBody = jsonBody
        GlobalController.fetchData(request: request, type: Session.self) { response in
            print(response.session)
            GlobalController.sessionToken = response.session
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

    static func fetchData<T: Decodable>(request: URLRequest? = nil, url: String? = nil, type: T.Type, completion: @escaping (T) -> ()) {
        var urlRequest: URLRequest?
        if request != nil {
            urlRequest = request!
        } else if url != nil {
            urlRequest = URLRequest(url: URL(string: url!)!)
        } else {
            urlRequest = nil
            print("At least one parameter needed!")
        }

        URLSession.shared.dataTask(with: urlRequest!) { data, _, _ in
            let jsonDecoder = JSONDecoder()
            jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
            let stops = try! jsonDecoder.decode(type, from: data!)

            DispatchQueue.main.async {
                completion(stops)
            }
        }
        .resume()
    }
}
