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
}

open class DataProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let magicApiBaseUrl = (Bundle.main.infoDictionary?["MAGIC_API_URL"] as? String)!
    private let iApiBaseUrl = (Bundle.main.infoDictionary?["I_API_URL"] as? String)!
    private let bApiBaseUrl = (Bundle.main.infoDictionary?["B_API_URL"] as? String)!
    private let rApiBaseUrl = (Bundle.main.infoDictionary?["R_API_URL"] as? String)!
    private let xApiKey = (Bundle.main.infoDictionary?["X_API_KEY"] as? String)!
    private let xSession = (Bundle.main.infoDictionary?["X_SESSION"] as? String)!

    private let locationManager = CLLocationManager()
    private let manager = SocketManager(socketURL: URL(string: iApiBaseUrl)!, config: [.path("/rt/sio2/"), .version(.two), .forceWebsockets(true)])
    private let userDefaults = UserDefaults.standard
    private var socket: SocketIOClient
    private var connected = false
    var stopId = 20
    var stopsVersion: String
    
    var changeLocation = true
    let actualLocationStop = Stop(
        id: -1, stationID: -1, name: "Actual location", type: "location")
   
    @Published var tabs = [Tab]()
    @Published var stops = [Stop]()
    var originalStops = [Stop]()

    override init() {
        self.socket = manager.defaultSocket
        self.stopsVersion = userDefaults.string(forKey: Stored.stopsVerison) ?? ""
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        locationManager.requestWhenInUseAuthorization()
        startListeners()
        connect()
        fetchStops()
    }
    
    func fetchStops() {
        fetchData(url: "\(magicApiBaseUrl)/stops?v", type: StopsVersion.self) { (stopsVersion) in
            let cachedStops = self.userDefaults.retrieve(object: [Stop].self, forKey: Stored.stops)
            print(stopsVersion.version)
            if (self.stopsVersion == stopsVersion.version && cachedStops != nil) {
                print("useing cached stops json")
                self.stops = cachedStops!
                self.originalStops = cachedStops!
            } else {
                print("getting new stops json")
                self.fetchData(url: "\(self.magicApiBaseUrl)/stops", type: [Stop].self) { (stops) in
                    self.stops = stops
                    self.originalStops = stops
                    self.userDefaults.save(customObject: stops, forKey: Stored.stops)
                }
            }
            self.userDefaults.set(stopsVersion.version, forKey: Stored.stopsVerison)
            self.locationManager.startUpdatingLocation()
        }
        
    }
    
    func addUtilsToStopList() {
        self.stops.insert(actualLocationStop, at: 0)
    }
    
    func sortStops(lastLocation: CLLocation?) {
        if (lastLocation != nil && self.stops.count > 0) {
            let actualLocation = lastLocation!
            self.stops = self.originalStops.sorted(by: { $0.distance(to: actualLocation) < $1.distance(to: actualLocation)})
            addUtilsToStopList()
            if (self.changeLocation) {
                changeStop(stopId: getNearestStopId())
            }
        }
    }
    
    func getNearestStopId() -> Int {
        return self.stops.first(where: {$0.id ?? 0 > 0})?.id ?? self.stopId
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        print("got new location")
        sortStops(lastLocation: location)
    }

    func connect() {
        if (connected) {disconnect()}
        socket.connect()
    }

    func disconnect() {
        socket.disconnect()
    }

    func startListeners() {
        socket.on(clientEvent: .connect) { data, ack in
            print("socket connected")
            self.connected = true
        }

        socket.on(clientEvent: .disconnect) { data, ack in
            print("socket disconnected")
            self.connected = false
        }

        socket.on("cack") { data, ack in
            print(self.stopId)
            self.socket.emit("tabStart", [self.stopId, "*"] as [Any])
//            self.socket.emit("infoStart")
        }

        socket.on("tabs") { data, ack in
            print("tabs")
            var newTabs = [Tab]()
            newTabs.append(contentsOf: self.tabs)
            if let platforms = data[0] as? [String: Any] {
                for (_, value) in platforms {
                    if let json = value as? [String: Any],
                        let platform = json["nastupiste"] as? Int,
                        let tabsJson = json["tab"] as? [Any] {
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
            DispatchQueue.main.async {
                self.tabs = newTabs.sorted(by: { $0.departureTime < $1.departureTime })
            }
        }
    }

    func stopListeners() {
        socket.removeAllHandlers()
    }
    
    func switchLocationChanging(_ value: Bool) {
        if (value) {
            changeLocation = true
            changeStop(stopId: getNearestStopId())
        } else {
            changeLocation = false
        }
    }
    
    func changeStop(stopId: Int) {
        switch (stopId) {
            case -1:
                switchLocationChanging(true)
            default:
                if (self.stopId != stopId) {
                    switchLocationChanging(false)
                    disconnect()
                    self.tabs = [Tab]()
                    self.stopId = stopId
                    connect()
                }
            }
        
    }
    
    func fetchData<T: Decodable>(url: String, type: T.Type, completion: @escaping (T) -> ()) {
        let url = URL(string: url)

        URLSession.shared.dataTask(with: url!) { (data, _, _) in
            let stops = try! JSONDecoder().decode(type, from: data!)

            DispatchQueue.main.async {
                completion(stops)
            }
        }
            .resume()
    }
}
