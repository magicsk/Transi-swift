//
//  SimpleVirtualTableController.swift
//  Transi
//
//  Created by magic_sk on 10/02/2024.
//

import Combine
import CoreLocation
import SocketIO
import SwiftUI

class SimpleVirtualTableController: ObservableObject {
    private let manager = SocketManager(
        socketURL: URL(string: GlobalController.iApiBaseUrl)!,
        config: [
            .path("/rt/sio2/"),
            .version(.two), .forceWebsockets(true),
            .log(false),
            .reconnectAttempts(-1),
            .reconnectWaitMax(1),
            .reconnectWait(1),
        ]
    )
    private var socket: SocketIOClient
    private var connected = false
    private var updater: Timer.TimerPublisher?
    private var updaterSubscription: AnyCancellable?
    private var reconnect: Bool = false

    var tabs = [Tab]()
    var vehicleInfo = [VehicleInfo]()
    var socketStatus = "unknown"
    var currentStop: Int

    private var cancellables = Set<AnyCancellable>()

    init(stop: Int) {
        socket = manager.defaultSocket
        currentStop = stop
        startListeners()
        connect()
    }

    deinit {
        print("\(currentStop) is being deinitialized")
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
        let liveActivities = VirtualTableLiveActivityController.listAllTabActivities()
        for liveActivity in liveActivities {
            if var tab = tabs.first(where: { t in t.id == liveActivity.tabId && t.stopId == liveActivity.stopId }) {
                let oldDepartureTime = tab.departureTimeRemaining
                tab.departureTimeRemaining = getDepartureTimeRemainingText(tab.departureTime, tab.departureTimeRaw, tab.type)
                tab.departureTimeRemainingShortened = getShortDepartureTimeRemainingText(tab.departureTime, tab.departureTimeRaw, tab.type)
                let updatedTab = tab
                if oldDepartureTime != tab.departureTimeRemaining {
                    Task { await VirtualTableLiveActivityController.updateActivity(
                        id: liveActivity.id,
                        tab: updatedTab,
                        vehicleInfo: self.vehicleInfo.first(where: { $0.issi == updatedTab.busID })
                    ) }
                }
            }
        }
    }

    func connect() {
        print("atempting to connect... \(currentStop)")
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
            if connectionStatus != "connected" {
                self.socketStatus = self.socket.status.description
            }
        }

        socket.on(clientEvent: .connect) { _, _ in
            self.connected = true
            self.startUpdater()
        }

        socket.on(clientEvent: .disconnect) { _, _ in
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

        socket.on("cack") { _, _ in
            print("cack")
            self.socket.emit("tabStart", [self.currentStop, "*"] as [Any])
            self.socket.emit("infoStart")
        }

        socket.on("tabs") { data, _ in
            guard let platformArray = data.first as? [[String: Any]] else {
                print("Error: Could not cast incoming data to the expected [[String: Any]] structure.")
                DispatchQueue.main.async {
                    self.tabs = [Tab]()
                    self.socketStatus = "error"
                }
                return
            }
            
            var newTabs = [Tab]()
            newTabs.append(contentsOf: self.tabs)
            for platformObject in platformArray {
                if let _platform = platformObject["nastupiste"] as? Int,
                   let _stopId = platformObject["zastavka"] as? Int,
                   let tabsJson = platformObject["tab"] as? [Any]
                {
                    var tabs = [Tab]()
                    for object in tabsJson {
                        if let tabJson = object as? [String: Any] {
                            if let tab = Tab(json: tabJson, platform: _platform, stopId: _stopId) {
                                if VirtualTableLiveActivityController.listAllTabActivities().contains(where: { la in la.tabId == tab.id }) {
                                    tabs.append(tab)
                                }
                            }
                        }
                    }
                    let liveActivities = VirtualTableLiveActivityController.listAllTabActivities().filter { la in la.platform == _platform }
                    for liveActivity in liveActivities {
                        if let tab = tabs.first(where: { t in t.id == liveActivity.tabId }) {
                            Task { await VirtualTableLiveActivityController.updateActivity(
                                id: liveActivity.id,
                                tab: tab,
                                vehicleInfo: self.vehicleInfo.first(where: { $0.issi == tab.busID })
                            ) }
                        } else {
                            Task { await VirtualTableLiveActivityController.endActivity(liveActivity.id) }
                        }
                    }
                    newTabs.removeAll(where: { $0.platform == _platform || $0.stopId != self.currentStop })
                    newTabs.append(contentsOf: tabs)
                }
            }
            self.tabs = newTabs
            self.socketStatus = "connected"
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
}
