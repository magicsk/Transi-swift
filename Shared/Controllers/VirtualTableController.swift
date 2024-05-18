//
//  VirtualTableController.swift
//  Transi
//
//  Created by magic_sk on 10/02/2024.
//

import Combine
import CoreLocation
import SocketIO
import SwiftUI

class VirtualTableController: ObservableObject {
    private let manager: SocketManager
    private var socket: SocketIOClient
    private var connected = false
    private var updater: Timer.TimerPublisher?
    private var updaterSubscription: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var reconnect: Bool = false
    private var expadndTabId: Int? = nil

    @Published var tabs = [Tab]()
    @Published var vehicleInfo = [VehicleInfo]()
    @Published var changeLocation = true
    @Published var currentStop: Stop = .example
    @Published var socketStatus = "unknown"
    @Published var lastExpandedTab: Tab? = nil

    init() {
        manager = SocketManager(socketURL: URL(string: GlobalController.iApiBaseUrl)!, config: [.path("/rt/sio2/"), .version(.two), .forceWebsockets(true), .log(false), .reconnectAttempts(-1), .reconnectWaitMax(1)])
        socket = manager.defaultSocket
        startListeners()
//            connect() // TODO: Disable this and change Loading to searching location and add default location that can be stop or actual location
    }

    private func startUpdater() {
        updater = Timer.publish(every: 10, on: .current, in: .common)
        updaterSubscription = updater?.autoconnect().sink(receiveValue: { [weak self] _ in
            self?.updateTabs()
        })
    }

    private func stopUpdater() {
        updaterSubscription?.cancel()
        updaterSubscription = nil
        updater = nil
    }

    private func updateTabs() {
//        print("update")
        for index in tabs.indices {
            let tab = tabs[index]
            let oldTimeRemaining = tab.departureTimeRemaining
            let updatedTimeRemaining = getDepartureTimeRemainingText(
                tab.departureTime,
                tab.departureTimeRaw,
                tab.type
            )
            if oldTimeRemaining != updatedTimeRemaining {
                DispatchQueue.main.async {
                    self.tabs[index].departureTimeRemaining = updatedTimeRemaining
                }
            }
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
                print(connectionStatus)
                if connectionStatus != "connected" {
                    self.socketStatus = self.socket.status.description
                }
            }
        }

        socket.on(clientEvent: .connect) { _, _ in
            DispatchQueue.main.async {
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
            self.connected = true
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
                                if var tab = Tab(json: tabJson, platform: _platform, stopId: _stopId) {
                                    if tab.id == self.expadndTabId {
                                        tab.expanded = true
                                        self.expadndTabId = nil
                                    }
                                    tabs.append(tab)
                                }
                            }
                        }
                        newTabs.removeAll(where: { $0.platform == _platform || $0.stopId != self.currentStop.id })
                        newTabs.append(contentsOf: tabs)
                    }
                }
            }
            newTabs.sort(by: { Int($0.departureTimeRaw) == Int($1.departureTimeRaw) ? $0.id < $1.id : Int($0.departureTimeRaw) < Int($1.departureTimeRaw) })
            DispatchQueue.main.async {
                self.tabs = newTabs
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
            changeStop(GlobalController.getNearestStopId(), switchOnly: true)
        } else {
            changeLocation = false
        }
    }

    func changeStop(_ stopId: Int, switchOnly: Bool = false, expandTab: Int? = nil) {
        if stopId == -1 {
            switchLocationChanging(true)
        } else {
            if currentStop.id != stopId {
                if !switchOnly { switchLocationChanging(false) }
                currentStop.id = stopId
                if let currentStop = GlobalController.getStopById(stopId) {
                    self.socketStatus = "connecting"
                    self.tabs = [Tab]()
                    self.socket.emit("tabStart", [currentStop.id, "*"] as [Any])
                    self.currentStop = currentStop
                }
            }
            if !connected {
                connect()
            }
            if let tabId = expandTab {
                expadndTabId = tabId
            }
        }
    }
}
