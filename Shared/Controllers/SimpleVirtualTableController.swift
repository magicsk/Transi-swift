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

    var connections = [Connection]()
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
            self?.updateConnections()
        })
    }

    private func stopUpdater() {
        updaterSubscription?.cancel()
        updaterSubscription = nil
        updater = nil
    }

    private func updateConnections() {
        let liveActivities = VirtualTableLiveActivityController.listAllTabActivities()
        for liveActivity in liveActivities {
            if var connection = connections.first(where: { t in
                t.id == liveActivity.connectionId && t.stopId == liveActivity.stopId
            }) {
                let oldDepartureTime = connection.departureTimeRemaining
                connection.departureTimeRemaining = getDepartureTimeRemainingText(
                    connection.departureTime, connection.departureTimeRaw, connection.type
                )
                connection.departureTimeRemainingShortened = getShortDepartureTimeRemainingText(
                    connection.departureTime, connection.departureTimeRaw, connection.type
                )
                let updatedConnection = connection
                if oldDepartureTime != connection.departureTimeRemaining {
                    Task {
                        await VirtualTableLiveActivityController.updateActivity(
                            id: liveActivity.id,
                            connection: updatedConnection,
                            vehicleInfo: self.vehicleInfo.first(where: { $0.issi == updatedConnection.busID })
                        )
                    }
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
            self.connections = [Connection]()
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
                    self.connections = [Connection]()
                    self.socketStatus = "error"
                }
                return
            }

            var newConnections = [Connection]()
            newConnections.append(contentsOf: self.connections)
            for platformObject in platformArray {
                if let _platform = platformObject["nastupiste"] as? Int,
                   let _stopId = platformObject["zastavka"] as? Int,
                   let connectionsJson = platformObject["tab"] as? [Any]
                {
                    var connections = [Connection]()
                    for object in connectionsJson {
                        if let tabJson = object as? [String: Any] {
                            if let connection = Connection(json: tabJson, platform: _platform, stopId: _stopId) {
                                if VirtualTableLiveActivityController.listAllTabActivities().contains(where: { la in
                                    la.connectionId == connection.id
                                }) {
                                    connections.append(connection)
                                }
                            }
                        }
                    }
                    let liveActivities = VirtualTableLiveActivityController.listAllTabActivities().filter {
                        la in la.platform == _platform
                    }
                    for liveActivity in liveActivities {
                        if let connection = connections.first(where: { t in t.id == liveActivity.connectionId })
                        {
                            Task {
                                await VirtualTableLiveActivityController.updateActivity(
                                    id: liveActivity.id,
                                    connection: connection,
                                    vehicleInfo: self.vehicleInfo.first(where: { $0.issi == connection.busID })
                                )
                            }
                        } else {
                            Task { await VirtualTableLiveActivityController.endActivity(liveActivity.id) }
                        }
                    }
                    newConnections.removeAll(where: {
                        $0.platform == _platform || $0.stopId != self.currentStop
                    })
                    newConnections.append(contentsOf: connections)
                }
            }
            self.connections = newConnections
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
