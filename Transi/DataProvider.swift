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

final class DataProvider: ObservableObject {
    private let magicApiBaseUrl = (Bundle.main.infoDictionary?["MAGIC_API_URL"] as? String)!
    private let iApiBaseUrl = (Bundle.main.infoDictionary?["I_API_URL"] as? String)!
    private let bApiBaseUrl = (Bundle.main.infoDictionary?["B_API_URL"] as? String)!
    private let rApiBaseUrl = (Bundle.main.infoDictionary?["R_API_URL"] as? String)!
    private let xApiKey = (Bundle.main.infoDictionary?["X_API_KEY"] as? String)!
    private let xSession = (Bundle.main.infoDictionary?["X_SESSION"] as? String)!


    let manager = SocketManager(socketURL: URL(string: iApiBaseUrl)!, config: [.path("/rt/sio2/"), .version(.two), .forceWebsockets(true)])
    let userDefaults = UserDefaults.standard
    var socket: SocketIOClient
    var stopsVersion: String
    var stopId = 20
    var connected = false
    
    @Published var tabs = [Tab]()
    @Published var stops = [Stop]()

    init() {
        self.socket = manager.defaultSocket
        self.stopsVersion = userDefaults.string(forKey: Stored.stopsVerison) ?? ""
        startListeners()
        connect()
        fetchStops()
    }
    
    func fetchStops() {
        getStopsVersion() { (stopsVersion) in
            let cachedStops = self.userDefaults.retrieve(object: [Stop].self, forKey: Stored.stops)
            print(stopsVersion.version)
            if (self.stopsVersion == stopsVersion.version && cachedStops != nil) {
                print("useing cached stops json")
                self.stops = cachedStops!
            } else {
                print("getting new stops json")
                self.getStops() { (stops) in
                    self.stops = stops
                    self.userDefaults.save(customObject: stops, forKey: Stored.stops)
                }
            }
            self.userDefaults.set(stopsVersion.version, forKey: Stored.stopsVerison)
        }
        
    }
    
    func sortStops(lastLocation: CLLocation?) -> Int {
        if (lastLocation != nil) {
            let actualLocation = lastLocation!
            self.stops.sort(by: { $0.distance(to: actualLocation) < $1.distance(to: actualLocation) })
            // return self.stops[0]?.id ?? 94
        }
        return 94
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

    func changeStop(stopId: Int) {
        disconnect()
        self.tabs = [Tab]()
        self.stopId = stopId
        connect()
    }


    func getStops(completion: @escaping ([Stop]) -> ()) {
        let url = URL(string: "\(magicApiBaseUrl)/stops")

        URLSession.shared.dataTask(with: url!) { (data, _, _) in
            let stops = try! JSONDecoder().decode([Stop].self, from: data!)

            DispatchQueue.main.async {
                completion(stops)
            }
        }
            .resume()
    }

    func getStopsVersion(completion: @escaping (StopsVersion) -> ()) {
        let url = URL(string: "\(magicApiBaseUrl)/stops?v")

        URLSession.shared.dataTask(with: url!) { (data, _, _) in
            let stops = try! JSONDecoder().decode(StopsVersion.self, from: data!)

            DispatchQueue.main.async {
                completion(stops)
            }
        }
            .resume()
    }
}
