//
//  DataProvider.swift
//  Transi
//
//  Created by magic_sk on 13/11/2022.
//

import Combine
import CoreLocation
import Foundation
import SocketIO

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
    private var updater: Timer.TimerPublisher?
    private var updaterSubscription: AnyCancellable?
    private var reconnect: Bool = false
    var stopId = 20
    var stopsVersion: String

    var changeLocation = true

    @Published var tabs = [Tab]()
    @Published var vehicleInfo = [VehicleInfo]()
    @Published var stops = [Stop]()
    @Published var trip = Trip()
    @Published var lastLocation: CLLocation? = nil
    @Published var currentStop: Stop = .example
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
        trip = Trip()
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
        fetchData(request: request, type: Trip.self) { trip in
            DispatchQueue.main.async {
                print("fetched trip")
                self.trip = trip
                self.userDefaults.save(customObject: trip, forKey: Stored.trip)
            }
        }
    }

    private func startUpdater() {
        updater = Timer.publish(every: 10, on: .current, in: .common)
        updaterSubscription = updater?.autoconnect().sink(receiveValue: { [weak self] _ in
            self?.updateTabs()
        })
    }

    private func stopUpdater() { // TODO: also stop if inactive and time inforamation is not needed
        updaterSubscription?.cancel()
        updaterSubscription = nil
        updater = nil
    }

    private func updateTabs() {
        var updatedTabs = tabs
        for index in updatedTabs.indices {
            updatedTabs[index].departureTimeRemaining = getDepartureTimeRemainingText(updatedTabs[index].departureTime, updatedTabs[index].departureTimeRaw, updatedTabs[index].type)
        }
        DispatchQueue.main.async {
            self.tabs = updatedTabs
        }
    }

    func fetchStops() {
        print(Thread.isMainThread)
        fetchData(url: "\(self.magicApiBaseUrl)/stops?v", type: StopsVersion.self) { stopsVersion in
            let cachedStops = self.userDefaults.retrieve(object: [Stop].self, forKey: Stored.stops)
            print(stopsVersion.version)
            DispatchQueue.main.async {
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
        stops.insert(Stop.actualLocation, at: 0)
    }

    func sortStops(lastLocation: CLLocation?) {
        if lastLocation != nil && stops.count > 0 {
            let actualLocation = lastLocation!
            DispatchQueue.main.async {
                self.stops = self.originalStops.sorted(by: { $0.distance(to: actualLocation) < $1.distance(to: actualLocation) })
                self.addUtilsToStopList()
                if self.changeLocation {
                    self.changeStop(self.getNearestStopId(), true)
                }
            }
        }
    }

    func getNearestStopId() -> Int {
        return stops.first(where: { $0.id ?? 0 > 0 })?.id ?? stopId
    }

    func getNearestStationId() -> Int {
        return stops.first(where: { $0.id ?? 0 > 0 })?.stationId ?? 0
    }
    
    func getStopById(_ id: Int) -> Stop? {
        return stops.first(where: { $0.id == id })
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
//        print("got new location")
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

    func disconnect(reconnect: Bool = false) {
        self.reconnect = reconnect
        socket.disconnect()
    }

    func startListeners() {
        socket.on(clientEvent: .connect) { _, _ in
            print("socket connected")
            self.connected = true
            self.startUpdater()
        }

        socket.on(clientEvent: .disconnect) { _, _ in
            print("socket disconnected")
            DispatchQueue.main.async {
                self.tabs = [Tab]()
                self.vehicleInfo = [VehicleInfo]()
                self.connected = false
                if self.reconnect {
                    self.reconnect = false
                    self.connect()
                } else {
                    self.stopUpdater()
                }
            }
        }

        socket.on("cack") { _, _ in
            print(self.stopId)
            self.socket.emit("tabStart", [self.stopId, "*"] as [Any])
            self.socket.emit("infoStart")
        }

        socket.on("tabs") { data, _ in
//            print("tabs")
            var newTabs = [Tab]()
            newTabs.append(contentsOf: self.tabs)
            if let platforms = data[0] as? [String: Any] {
                for (_, value) in platforms {
                    if let json = value as? [String: Any],
                       let _platform = json["nastupiste"] as? Int,
                       let _stopId = json["zastavka"] as? Int,
                       let tabsJson = json["tab"] as? [Any]
                    {
                        var tabs = [Tab]()
                        for object in tabsJson {
                            if let tabJson = object as? [String: Any] {
                                if let tab = Tab(json: tabJson, platform: _platform, stopId: _stopId) {
                                    tabs.append(tab)
                                }
                            }
                        }
                        newTabs.removeAll(where: { $0.platform == _platform || $0.stopId != self.stopId })
                        newTabs.append(contentsOf: tabs)
                    }
                }
            }
            let sortedTabs = newTabs.sorted(by: { Int($0.departureTimeRaw) < Int($1.departureTimeRaw) })
            DispatchQueue.main.async {
                self.tabs = sortedTabs
            }
        }
        socket.on("vInfo") { data, _ in
            if let vehicleInfoJson = data[0] as? [String: Any] {
                if let newVehicleInfo = VehicleInfo(json: vehicleInfoJson) {
                    self.vehicleInfo.append(newVehicleInfo)
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
            changeStop(getNearestStopId(), true)
        } else {
            changeLocation = false
        }
    }

    func changeStop(_ stopId: Int, _ switchOnly: Bool = false) { // FIXME: this function is called multiple times and one change of location stop location changeing
        if stopId == -1 {
            switchLocationChanging(true)
        } else {
            if self.stopId != stopId {
                if !switchOnly { switchLocationChanging(false) }
                self.stopId = stopId
                if let currentStop = getStopById(stopId) { self.currentStop = currentStop }
                disconnect(reconnect: true)
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
