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
    /// `connections` before the train departures took the place of the board's trains, for a train followed by
    /// the board's name or minute. Read on the main thread.
    private(set) var board = [Connection]()
    private var internalConnections = [Connection]()
    private var internalRegionalConnections = [Connection]()
    private var internalTrains = [TrainDeparture]()
    var vehicleInfo = [VehicleInfo]()
    var socketStatus = "unknown"
    var currentStop: Int
    /// Called on the main thread after `connections` or `vehicleInfo` change.
    var onUpdate: (() -> Void)?
    /// From each connect or drop until the socket's board arrives; meanwhile `connections` hold at most the
    /// regional departures, without the city's vehicles.
    private var awaitsSocketBoardSince: Date? = Date()
    /// Whether `connections` show the whole board: the socket's arrived since it last connected, or did not within
    /// 10 s, as at stops outside the city, which have only regional departures. Read on the main thread.
    var hasWholeBoard: Bool { awaitsSocketBoardSince.map { Date().timeIntervalSince($0) >= 10 } ?? true }
    /// False for boards that only read departures, like the trip detail's, so they never update or end the
    /// table's Live Activities for this stop.
    let updatesLiveActivities: Bool

    private var cancellables = Set<AnyCancellable>()

    init(stop: Int, updatesLiveActivities: Bool = true) {
        socket = manager.defaultSocket
        currentStop = stop
        self.updatesLiveActivities = updatesLiveActivities
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
        fetchTrainDepartures()
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
                self?.fetchTrainDepartures()
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
        let liveActivities = updatesLiveActivities ? VirtualTableLiveActivityController.listAllTabActivities() : []
        for index in connections.indices {
            let updatedConnection = countedDown(connections[index])
            guard connections[index].departureTimeRemaining != updatedConnection.departureTimeRemaining else { continue }
            connections[index] = updatedConnection
            updateLiveActivities(
                matching: updatedConnection,
                in: liveActivities
            )
        }
        // An activity no row lists right now, on a board row a listed train hides or on a train while its refresh
        // fails, counts down from what it shows.
        for liveActivity in liveActivities where liveActivity.stopId == currentStop
            && !connections.contains(where: { $0.matchesLiveActivityReference(liveActivity.reference) })
        {
            guard let shown = VirtualTableLiveActivityController.shownState(liveActivity.id) else { continue }
            let connection = countedDown(shown.connection)
            guard connection.departureTimeRemaining != shown.connection.departureTimeRemaining else { continue }
            Task {
                await VirtualTableLiveActivityController.updateActivity(
                    id: liveActivity.id, connection: connection, vehicleInfo: shown.vehicleInfo
                )
            }
        }
    }

    /// `connection` with its countdown at now.
    private func countedDown(_ connection: Connection) -> Connection {
        var connection = connection
        connection.departureTimeRemaining = getDepartureTimeRemainingText(
            connection.departureTime, connection.departureTimeRaw, connection.type
        )
        connection.departureTimeRemainingShortened = getShortDepartureTimeRemainingText(
            connection.departureTime, connection.departureTimeRaw, connection.type
        )
        return connection
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
                        || terminates(connection, at: stop.name)
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

    private func fetchTrainDepartures() {
        guard let stop = GlobalController.getStopById(currentStop) else { return }
        fetchTrains(at: stop) { [weak self] trains in
            self?.connectionsProcessingQueue.async { [weak self] in
                guard let self = self else { return }
                // A failed refresh leaves the board's own trains; only a fresh list ends a train's Live Activity.
                self.internalTrains = trains ?? []
                self.sortAndPublishConnections(endMissingActivities: false, endMissingTrainActivities: trains != nil)
            }
        }
    }

    private func getRegionalConnection(_ connection: Connection) -> Connection? {
        return internalRegionalConnections.first(where: { isSameDeparture($0, connection, within: 0) })
    }

    /// `endMissingActivities` ends Live Activities whose row left the socket's board, and
    /// `endMissingTrainActivities` those whose train left the train departures: each is whole for its own rows.
    private func sortAndPublishConnections(endMissingActivities: Bool, endMissingTrainActivities: Bool = false) {
        var connectionsForPublish = internalConnections.map { connection in
            if connection.type != "online", var regionalConnection = getRegionalConnection(connection) {
                regionalConnection.platform = connection.platform
                return regionalConnection
            }
            return connection
        }

        let newRegionalConnections = internalRegionalConnections.filter { regionalConnection in
            regionalConnection.departureTimeCP < Date().timeIntervalSince1970
                && !internalConnections.contains {
                    $0.type == "online"
                        ? isSameDeparture($0, regionalConnection)
                        : isSameDeparture($0, regionalConnection, within: 0)
                }
        }
        connectionsForPublish.append(contentsOf: newRegionalConnections)
        let board = connectionsForPublish
        connectionsForPublish = mergeTrainDepartures(
            internalTrains, at: currentStop, into: connectionsForPublish, now: Date().timeIntervalSince1970
        )

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
            self.board = board
            self.socketStatus = "connected"
            // Only the socket's board ends missing activities: unlike the regional departures, it is whole.
            if endMissingActivities { self.awaitsSocketBoardSince = nil }
            self.updateLiveActivities(
                endMissingActivities: endMissingActivities, endMissingTrainActivities: endMissingTrainActivities
            )
            self.onUpdate?()
        }
    }

    private func updateLiveActivities(endMissingActivities: Bool, endMissingTrainActivities: Bool) {
        guard updatesLiveActivities else { return }
        let liveActivities = VirtualTableLiveActivityController.listAllTabActivities()
            .filter { $0.stopId == currentStop }
        for liveActivity in liveActivities {
            if let connection = connections.first(where: { $0.matchesLiveActivityReference(liveActivity.reference) }) {
                updateLiveActivities(matching: connection, in: [liveActivity])
            } else if let row = board.first(where: { $0.matchesLiveActivityReference(liveActivity.reference) }) {
                // One followed on a board row keeps it under a train listed by another name or minute.
                updateLiveActivities(matching: countedDown(row), in: [liveActivity])
            } else if liveActivity.connectionId.hasPrefix(trainDepartureIdPrefix),
                      let shown = VirtualTableLiveActivityController.shownState(liveActivity.id),
                      let row = connections.first(where: { $0.standsIn(for: shown.connection) })
            {
                // A followed train ŽSR has no delay for yet shows as the live IDS BK row standing in for it.
                Task {
                    await VirtualTableLiveActivityController.updateActivity(
                        id: liveActivity.id, connection: row, vehicleInfo: shown.vehicleInfo
                    )
                }
            } else {
                // A train's activity ends once fresh train departures lack it or, while they fail (as while ŽSR
                // is down), a minute after the departure it last showed.
                let ends = liveActivity.connectionId.hasPrefix(trainDepartureIdPrefix)
                    ? endMissingTrainActivities
                        || VirtualTableLiveActivityController.shownState(liveActivity.id)?.connection.departureTimeRaw
                        ?? 0 < Date().timeIntervalSince1970 - 60
                    : endMissingActivities
                if ends { Task { await VirtualTableLiveActivityController.endActivity(liveActivity.id) } }
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
        guard updatesLiveActivities else { return }
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
                self?.awaitsSocketBoardSince = Date()
                self?.startUpdater()
            }
        }

        socket.on(clientEvent: .disconnect) { [weak self] _, _ in
            guard let self = self else { return }
            DispatchQueue.main.async { [weak self] in
                self?.connections = [Connection]()
                self?.vehicleInfo = [VehicleInfo]()
                self?.awaitsSocketBoardSince = Date()
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
                                self.onUpdate?()
                            }
                        } else {
                            self.vehicleInfo.append(newVehicleInfo)
                            self.updateLiveActivitiesForVehicleInfo(newVehicleInfo)
                            self.onUpdate?()
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
