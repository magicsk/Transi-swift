//
//  DataProvider.swift
//  Transi
//
//  Created by magic_sk on 13/11/2022.
//

import Foundation
import SocketIO

final class DataProvider: ObservableObject {
    private let magicApiBaseUrl = (Bundle.main.infoDictionary?["MAGIC_API_URL"] as? String)!
    private let iApiBaseUrl = (Bundle.main.infoDictionary?["I_API_URL"] as? String)!
    private let bApiBaseUrl = (Bundle.main.infoDictionary?["B_API_URL"] as? String)!
    private let rApiBaseUrl = (Bundle.main.infoDictionary?["R_API_URL"] as? String)!
    private let xApiKey = (Bundle.main.infoDictionary?["X_API_KEY"] as? String)!
    private let xSession = (Bundle.main.infoDictionary?["X_SESSION"] as? String)!


    let manager = SocketManager(socketURL: URL(string: iApiBaseUrl)!, config: [.path("/rt/sio2/"), .version(.two), .forceWebsockets(true)])
    var socket: SocketIOClient
    var stopId = 20
    
    @Published var tabs = [Tab]()
    @Published var stops = [Stop]()

    init() {
        self.socket = manager.defaultSocket
        startListeners()
        connect()
        getStops() { (stops) in
            self.stops = stops
        }
    }

    func connect() {
        socket.connect()
    }

    func disconnect() {
        socket.disconnect()
    }

    func startListeners() {
        socket.on(clientEvent: .connect) { data, ack in
            print("socket connected")
        }

        socket.on(clientEvent: .disconnect) { data, ack in
            print("socket disconnected")
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
        guard let url = URL(string: "\(magicApiBaseUrl)/stops") else { return }

        URLSession.shared.dataTask(with: url) { (data, _, _) in
            let stops = try! JSONDecoder().decode([Stop].self, from: data!)

            DispatchQueue.main.async {
                completion(stops)
            }
        }
            .resume()
    }
}
