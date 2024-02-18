//
//  VirtualTableController.swift
//  Transi
//
//  Created by magic_sk on 10/02/2024.
//

import Combine
import Foundation
import SocketIO
import CoreLocation

class VirtualTableController: ObservableObject {
    private let manager: SocketManager
    private var socket: SocketIOClient
    private var connected = false
    private var updater: Timer.TimerPublisher?
    private var updaterSubscription: AnyCancellable?
    private var reconnect: Bool = false

    @Published var tabs = [Tab]()
    @Published var vehicleInfo = [VehicleInfo]()
    @Published var changeLocation = true
    @Published var currentStop: Stop = .example
    @Published var socketStatus = "unknown"
    
    init() {
        manager = SocketManager(socketURL: URL(string: GlobalController.iApiBaseUrl)!, config: [.path("/rt/sio2/"), .version(.two), .forceWebsockets(true), .log(false), .reconnectAttempts(-1), .reconnectWaitMax(1)])
        socket = manager.defaultSocket
        startListeners()
        connect()
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

    func connect() {
        print("atempting to connect...")    
        disconnect()
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
        socket.on(clientEvent: .statusChange) { _, _ in
            let connectionStatus = self.socket.status.description
            DispatchQueue.main.async {
//                print(connectionStatus) 
                if connectionStatus != "connected" {
                    self.socketStatus = self.socket.status.description
                }
            }
        }

        socket.on(clientEvent: .connect) { _, _ in
            DispatchQueue.main.async {
                self.connected = true
                self.startUpdater()
            }
        }

        socket.on(clientEvent: .disconnect) { _, _ in
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
//            print("cack")
            self.socket.emit("tabStart", [self.currentStop.id, "*"] as [Any])
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
                        newTabs.removeAll(where: { $0.platform == _platform || $0.stopId != self.currentStop.id })
                        newTabs.append(contentsOf: tabs)
                    }
                }
            }
            let sortedTabs = newTabs.sorted(by: { Int($0.departureTimeRaw) < Int($1.departureTimeRaw) })
            DispatchQueue.main.async {
                self.tabs = sortedTabs
                self.socketStatus = "connected"
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
            changeStop(GlobalController.getNearestStopId(), true)
        } else {
            changeLocation = false
        }
    }

    func changeStop(_ stopId: Int, _ switchOnly: Bool = false) { // FIXME: this function is called multiple times and one change of location stop location changeing
        if stopId == -1 {
            switchLocationChanging(true)
        } else {
            if currentStop.id != stopId {
                if !switchOnly { switchLocationChanging(false) }
                currentStop.id = stopId
                if let currentStop = GlobalController.getStopById(stopId) { self.currentStop = currentStop }
                disconnect(reconnect: true)
            }
        }
    }
}
