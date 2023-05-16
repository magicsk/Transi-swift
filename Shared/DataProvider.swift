//
//  DataProvider.swift
//  Transi
//
//  Created by magic_sk on 13/11/2022.
//

import Foundation
import SocketIO
import CoreLocation

struct Stored {
    static let stops = "stops"
    static let stopsVerison = "stopsVersion"
    static let trip = ""
}

open class DataProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let magicApiBaseUrl = (Bundle.main.infoDictionary?["MAGIC_API_URL"] as? String)!
    private let iApiBaseUrl = (Bundle.main.infoDictionary?["I_API_URL"] as? String)!
    private let bApiBaseUrl = (Bundle.main.infoDictionary?["B_API_URL"] as? String)!
    private let rApiBaseUrl = (Bundle.main.infoDictionary?["R_API_URL"] as? String)!
    private let xApiKey = (Bundle.main.infoDictionary?["X_API_KEY"] as? String)!
    private let xSession = (Bundle.main.infoDictionary?["X_SESSION"] as? String)!

    private let locationManager = CLLocationManager()
    private let jsonDecoder = JSONDecoder()
    private let manager: SocketManager
    private var socket: SocketIOClient
    private let userDefaults = UserDefaults.standard
    private var connected = false
    var stopId = 20
    var stopsVersion: String

    var changeLocation = true
    let actualLocationStop = Stop(
        id: -1, stationId: -1, name: "Actual location", type: "location")

    @Published var tabs = [Tab]()
    @Published var vehicleInfo = [VehicleInfo]()
    @Published var stops = [Stop]()
    @Published var trip = Trip()
    @Published var lastLocation: CLLocation? = nil
    var originalStops = [Stop]()

    override init() {
        manager = SocketManager(socketURL: URL(string: iApiBaseUrl)!, config: [.path("/rt/sio2/"), .version(.two), .forceWebsockets(true), .log(false)])
        socket = manager.defaultSocket
        stopsVersion = userDefaults.string(forKey: Stored.stopsVerison) ?? ""
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.requestWhenInUseAuthorization()
        jsonDecoder.keyDecodingStrategy = .convertFromSnakeCase
        startListeners()
        connect()
        fetchStops()
        if let cachedTrip = userDefaults.retrieve(object: Trip.self, forKey: Stored.trip) {
            trip = cachedTrip
        }
    }

    func fetchTrip(from: Int, to: Int) {
        DispatchQueue.main.async {
            self.trip = Trip()
            print("fetching trip")
            let encoder = JSONEncoder()
            let tripRequestBody = TripReq(org_id: 120, max_walk_duration: 5, search_from_hours: 2, search_to_hours: 2, max_transfers: 3, from_station_id: [from], to_station_id: [to])
            let jsonBody = try! encoder.encode(tripRequestBody) // TODO: error handeling
            var request = URLRequest(url: URL(string: "\(rApiBaseUrl)/mobile/v1/raptor/")!)
            request.httpMethod = "POST"
            request.setValue("\(String(describing: jsonBody.count))", forHTTPHeaderField: "Content-Length")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Dalvik/2.1.0 (Linux; U; Android 12; Pixel 6)", forHTTPHeaderField: "User-Agent")
            request.setValue("gzip", forHTTPHeaderField: "Accept-Encoding")
            request.setValue(xApiKey, forHTTPHeaderField: "x-api-key")
            request.setValue(xSession, forHTTPHeaderField: "x-session")
            request.httpBody = jsonBody
            self.fetchData(request: request, type: Trip.self) { trip in
                print("fetched trip")
                self.trip = trip
                self.userDefaults.save(customObject: trip, forKey: Stored.trip)
            }
        }
    }

    func fetchStops() {
        DispatchQueue.main.async {
            self.fetchData(url: "\(self.magicApiBaseUrl)/stops?v", type: StopsVersion.self) { stopsVersion in
                let cachedStops = self.userDefaults.retrieve(object: [Stop].self, forKey: Stored.stops)
                print(stopsVersion.version)
                if self.stopsVersion == stopsVersion.version && cachedStops != nil {
                    print("useing cached stops json")
                    self.stops = cachedStops!
                    self.originalStops = cachedStops!
                } else {
                    print("getting new stops json")
                    self.fetchData(url: "\(self.magicApiBaseUrl)/stops", type: [Stop].self) { stops in
                        self.stops = stops
                        self.originalStops = stops
                        self.userDefaults.save(customObject: stops, forKey: Stored.stops)
                    }
                }
                self.userDefaults.set(stopsVersion.version, forKey: Stored.stopsVerison)
                self.locationManager.startUpdatingLocation()
            }
        }
    }

    func addUtilsToStopList() {
        stops.insert(actualLocationStop, at: 0)
    }

    func sortStops(lastLocation: CLLocation?) {
        DispatchQueue.main.async {
            if lastLocation != nil && self.stops.count > 0 {
                let actualLocation = lastLocation!
                self.stops = self.originalStops.sorted(by: { $0.distance(to: actualLocation) < $1.distance(to: actualLocation) })
                self.addUtilsToStopList()
                if self.changeLocation {
                    self.changeStop(stopId: self.getNearestStopId())
                }
            }
        }
    }

    func getNearestStopId() -> Int {
        return stops.first(where: { $0.id ?? 0 > 0 })?.id ?? stopId
    }

    public func getNearestStationId() -> Int {
        return stops.first(where: { $0.id ?? 0 > 0 })?.stationId ?? 0
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        // print("got new location")
        lastLocation = location
        sortStops(lastLocation: location)
    }

    func connect() {
        print("atempting to connect...")
        if connected {
            print("already connected, disconnecting...")
            disconnect()
        }
        // print(manager.engine?.connected)
        if manager.engine?.connected != true {
            manager.engine?.connect()
        }
        socket.connect()
    }

    func disconnect() {
        socket.disconnect()
        vehicleInfo = [VehicleInfo]()
    }

    func startListeners() {
        socket.on(clientEvent: .connect) { _, _ in
            print("socket connected")
            self.connected = true
        }

        socket.on(clientEvent: .disconnect) { _, _ in
            print("socket disconnected")
            self.connected = false
        }

        socket.on("cack") { _, _ in
            print(self.stopId)
            self.socket.emit("tabStart", [self.stopId, "*"] as [Any])
            self.socket.emit("infoStart")
        }

        socket.on("tabs") { data, _ in
//            print("tabs")
            DispatchQueue.main.async {
                var newTabs = [Tab]()
                newTabs.append(contentsOf: self.tabs)
                if let platforms = data[0] as? [String: Any] {
                    for (_, value) in platforms {
                        if let json = value as? [String: Any],
                           let platform = json["nastupiste"] as? Int,
                           let tabsJson = json["tab"] as? [Any]
                        {
                            var tabs = [Tab]()
                            for object in tabsJson {
                                if let tabJson = object as? [String: Any] {
                                    if let tab = Tab(json: tabJson, platform: platform) {
                                        tabs.append(tab)
                                    }
                                }
                            }
                            newTabs.removeAll(where: { $0.platform == platform })
                            newTabs.append(contentsOf: tabs)
                        }
                    }
                }
                self.tabs = newTabs.sorted(by: { Int($0.departureTimeRaw) < Int($1.departureTimeRaw) })
            }
        }
        socket.on("vInfo") { data, _ in
//            print("vInfo")
            DispatchQueue.main.async {
                // print(data)
                if let vehicleInfoJson = data[0] as? [String: Any] {
                    if let newVehicleInfo = VehicleInfo(json: vehicleInfoJson) {
                        self.vehicleInfo.append(newVehicleInfo)
                        // print(self.vehicleInfo)
                    }
                }
            }
        }
    }

    func stopListeners() {
        socket.removeAllHandlers()
    }

    func switchLocationChanging(_ value: Bool) {
        if value {
            changeLocation = true
            changeStop(stopId: getNearestStopId())
        } else {
            changeLocation = false
        }
    }

    func changeStop(stopId: Int) {
        DispatchQueue.main.async {
            switch stopId {
            case -1:
                self.switchLocationChanging(true)
            default:
                if self.stopId != stopId {
                    self.switchLocationChanging(false)
                    self.disconnect()
                    self.tabs = [Tab]()
                    self.stopId = stopId
                    self.connect()
                }
            }
        }
    }

    func fetchData<T: Decodable>(request: URLRequest? = nil, url: String? = nil, type: T.Type, completion: @escaping (T) -> ()) {
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
            let stops = try! self.jsonDecoder.decode(type, from: data!)

            DispatchQueue.main.async {
                completion(stops)
            }
        }
        .resume()
    }
}