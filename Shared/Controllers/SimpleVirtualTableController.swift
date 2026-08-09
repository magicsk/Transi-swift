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
            .path("/rt/sio2"),
            .version(.three),
            .log(false),
            .reconnects(true),
            .reconnectAttempts(-1),
            .reconnectWaitMax(1),
            .reconnectWait(1),
        ]
    )
    private var socket: SocketIOClient
    private var connected = false
    private var updater: Timer.TimerPublisher?
    private var updaterSubscription: AnyCancellable?
    private var updaterRegionalConnections: Timer.TimerPublisher?
    private var updaterRegionalConnectionsSubscription: AnyCancellable?
    private var reconnect: Bool = false
    private let connectionsProcessingQueue = DispatchQueue(
        label: "eu.magicsk.transi.simpleConnectionsProcessingQueue")

    var connections = [Connection]()
    private var internalConnections = [Connection]()
    private var internalRegionalConnections = [Connection]()
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
        #if DEBUG
        print("\(currentStop) is being deinitialized")
        #endif
    }

    private func startUpdater() {
        stopUpdater()
        updateConnections()
        Task {
            await self.fetchRegionalLiveDepartures()
        }
        updater = Timer.publish(every: 10, on: .main, in: .common)
        updaterSubscription = updater?.autoconnect().sink(receiveValue: { [weak self] _ in
            self?.updateConnections()
        })

        updaterRegionalConnections = Timer.publish(every: 50, on: .main, in: .common)
        updaterRegionalConnectionsSubscription = updaterRegionalConnections?.autoconnect().sink(
            receiveValue: { [weak self] _ in
                Task {
                    await self?.fetchRegionalLiveDepartures()
                }
            })
    }

    private func stopUpdater() {
        updaterSubscription?.cancel()
        updaterSubscription = nil
        updater = nil
        updaterRegionalConnectionsSubscription?.cancel()
        updaterRegionalConnectionsSubscription = nil
        updaterRegionalConnections = nil
    }

    private func updateConnections() {
        let liveActivities = VirtualTableLiveActivityController.listAllTabActivities()
        for index in connections.indices {
            let connection = connections[index]
            let oldDepartureTime = connection.departureTimeRemaining
            var updatedConnection = connection
            updatedConnection.departureTimeRemaining = getDepartureTimeRemainingText(
                connection.departureTime, connection.departureTimeRaw, connection.type
            )
            updatedConnection.departureTimeRemainingShortened = getShortDepartureTimeRemainingText(
                connection.departureTime, connection.departureTimeRaw, connection.type
            )

            guard oldDepartureTime != updatedConnection.departureTimeRemaining else { continue }
            connections[index] = updatedConnection
            updateLiveActivities(
                matching: updatedConnection,
                in: liveActivities
            )
        }
    }

    private func fetchRegionalLiveDepartures() async {
        guard let stop = GlobalController.getStopById(currentStop), let stationId = stop.stationId else {
            #if DEBUG
            print("Current stop has no stationId. Cannot fetch regional departures.")
            #endif
            return
        }

        let dateString = actualDateString()
        let calendar = Calendar.current
        let now = Date()
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)

        fetchBApi(
            endpoint: "/mobile/v1/station/\(stationId)/timetable/\(dateString)/\(minutes)/1",
            type: RegionalConnectionsResponse.self
        ) { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                var newRegionalConnections = response.current.map {
                    Connection(from: $0, for: stop)
                }
                newRegionalConnections.removeAll { connection in
                    connection.departureTimeRaw < (Date().timeIntervalSince1970 + 15)
                        || connection.type != "online"
                }

                self.connectionsProcessingQueue.async { [weak self] in
                    guard let self = self else { return }
                    self.internalRegionalConnections = newRegionalConnections
                    self.sortAndPublishConnections(endMissingActivities: false)
                }
            case .failure(let err):
                #if DEBUG
                print("Error fetching or decoding regional departures. \(err)")
                #endif
            }
        }
    }

    private func getRegionalConnection(_ connection: Connection) -> Connection? {
        return internalRegionalConnections.first(where: {
            $0.line == connection.line && $0.type == "online"
                && $0.departureTimeCP == connection.departureTimeCP
        })
    }

    private func sortAndPublishConnections(endMissingActivities: Bool) {
        var regionalConnectionsToRemove = [String]()
        var connectionsForPublish = internalConnections.map { connection in
            if var regionalConnection = getRegionalConnection(connection) {
                regionalConnectionsToRemove.append(regionalConnection.id)
                if connection.type == "online" {
                    return connection
                }
                regionalConnection.platform = connection.platform
                return regionalConnection
            }
            return connection
        }

        let newRegionalConnections = internalRegionalConnections.filter {
            $0.departureTimeCP < Date().timeIntervalSince1970
                && !regionalConnectionsToRemove.contains($0.id)
        }
        connectionsForPublish.append(contentsOf: newRegionalConnections)

        connectionsForPublish.sort { a, b in
            if a.departureTimeRaw == b.departureTimeRaw {
                return a.id < b.id
            } else {
                return a.departureTimeRaw < b.departureTimeRaw
            }
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.connections = connectionsForPublish
            self.socketStatus = "connected"
            self.updateLiveActivities(endMissingActivities: endMissingActivities)
        }
    }

    private func updateLiveActivities(endMissingActivities: Bool) {
        let liveActivities = VirtualTableLiveActivityController.listAllTabActivities()
            .filter { $0.stopId == currentStop }
        for liveActivity in liveActivities {
            if let connection = connections.first(where: {
                $0.matchesLiveActivityReference(liveActivity.reference)
            }) {
                updateLiveActivities(matching: connection, in: [liveActivity])
            } else if endMissingActivities {
                Task { await VirtualTableLiveActivityController.endActivity(liveActivity.id) }
            }
        }
    }

    private func updateLiveActivities(matching connection: Connection, in liveActivities: [LiveActivityTab]) {
        for liveActivity in liveActivities where connection.matchesLiveActivityReference(liveActivity.reference) {
            Task { [weak self] in
                guard let self = self else { return }
                await VirtualTableLiveActivityController.updateActivity(
                    id: liveActivity.id,
                    connection: connection,
                    vehicleInfo: self.vehicleInfo.first(where: { $0.issi == connection.busID })
                )
            }
        }
    }

    private func updateLiveActivitiesForVehicleInfo(_ updatedVehicleInfo: VehicleInfo) {
        let liveActivities = VirtualTableLiveActivityController.listAllTabActivities()
            .filter { $0.stopId == currentStop }
        for connection in connections where connection.busID == updatedVehicleInfo.issi {
            updateLiveActivities(matching: connection, in: liveActivities)
        }
    }

    func connect() {
        #if DEBUG
        print("atempting to connect... \(currentStop)")
        #endif
        if socket.status == .connected {
            socket.emit("tabStart", [currentStop, "*"] as [Any])
            socket.emit("infoStart")
            startUpdater()
        } else if socket.status != .connecting {
            socket.connect()
        }
    }

    func disconnect(reconnect: Bool = false) {
        if socket.status == .disconnected || socket.status == .notConnected {
            if reconnect {
                connect()
            } else {
                stopUpdater()
            }
            return
        }
        self.reconnect = reconnect
        socket.disconnect()
    }

    func startListeners() {
        socket.on(clientEvent: .statusChange) { [weak self] _, _ in
            guard let self = self else { return }
            let connectionStatus = self.socket.status.description
            if connectionStatus != "connected" {
                self.socketStatus = self.socket.status.description
            }
        }

        socket.on(clientEvent: .connect) { [weak self] _, _ in
            guard let self = self else { return }
            self.connected = true
            DispatchQueue.main.async { [weak self] in
                self?.startUpdater()
            }
        }

        socket.on(clientEvent: .disconnect) { [weak self] _, _ in
            guard let self = self else { return }
            DispatchQueue.main.async { [weak self] in
                self?.connections = [Connection]()
                self?.vehicleInfo = [VehicleInfo]()
            }
            self.connectionsProcessingQueue.async { [weak self] in
                self?.internalConnections = [Connection]()
                self?.internalRegionalConnections = [Connection]()
            }
            self.connected = false
            if self.reconnect {
                self.reconnect = false
                self.connect()
            } else {
                self.stopUpdater()
            }
        }

        socket.on("cack") { [weak self] _, _ in
            guard let self = self else { return }
            #if DEBUG
            print("cack")
            #endif
            self.connected = true
            self.socket.emit("tabStart", [self.currentStop, "*"] as [Any])
            self.socket.emit("infoStart")
        }

        socket.on("tabs") { [weak self] data, _ in
            guard let self = self else { return }
            guard let platformArray = data.first as? [[String: Any]] else {
                #if DEBUG
                print("Error: Could not cast incoming data to the expected [[String: Any]] structure.")
                #endif
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.connections = [Connection]()
                    self.socketStatus = "error"
                }
                return
            }

            self.connectionsProcessingQueue.async { [weak self] in
                guard let self = self else { return }
                var newConnections = [Connection]()
                var platformsToUpdate = Set<Int>()

                for platformObject in platformArray {
                    if let _platform = platformObject["nastupiste"] as? Int,
                       let _stopId = platformObject["zastavka"] as? Int,
                       let connectionsJson = platformObject["tab"] as? [Any]
                    {
                        platformsToUpdate.insert(_platform)
                        for object in connectionsJson {
                            if let tabJson = object as? [String: Any] {
                                if let connection = Connection(json: tabJson, platform: _platform, stopId: _stopId) {
                                    newConnections.append(connection)
                                }
                            }
                        }
                    }
                }

                self.internalConnections.removeAll { connection in
                    platformsToUpdate.contains(connection.platform)
                }
                self.internalConnections.append(contentsOf: newConnections)
                self.sortAndPublishConnections(endMissingActivities: true)
            }
        }
        socket.on("vInfo") { [weak self] data, _ in
            guard let self = self else { return }
            if let vehicleInfoJson = data[0] as? [String: Any] {
                if let newVehicleInfo = VehicleInfo(json: vehicleInfoJson) {
                    DispatchQueue.main.async { [weak self] in
                        guard let self = self else { return }
                        if let index = self.vehicleInfo.firstIndex(where: { $0.issi == newVehicleInfo.issi }) {
                            if self.vehicleInfo[index] != newVehicleInfo {
                                self.vehicleInfo[index] = newVehicleInfo
                                self.updateLiveActivitiesForVehicleInfo(newVehicleInfo)
                            }
                        } else {
                            self.vehicleInfo.append(newVehicleInfo)
                            self.updateLiveActivitiesForVehicleInfo(newVehicleInfo)
                        }
                    }
                }
            }
        }
    }

    func stopListeners() {
        socket.removeAllHandlers()
    }
}
