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
    private var updaterRegionalConnections: Timer.TimerPublisher?
    private var updaterRegionalConnectionsSubscription: AnyCancellable?
    private var cancellables = Set<AnyCancellable>()
    private var reconnect: Bool = false
    private var loadedStatus: Int = 0
    private var expandedConnectionId: String? = nil
    private let connectionsProcessingQueue = DispatchQueue(
        label: "eu.magicsk.transi.connectionsProcessingQueue")

    @Published var connections = [Connection]()
    private var internalConnections = [Connection]()
    private var internalRegionalConnections = [Connection]()
    @Published var vehicleInfo = [VehicleInfo]()
    @Published var changeLocation = true
    @Published var currentStop: Stop = .empty
    @Published var socketStatus: SocketIOStatus = .notConnected
    @Published var connectionsEmpty = false
    @Published var lastExpandedConnection: Connection? = nil
    @Published var infoTexts = [String]()
    @Published var unreadInfoCount = 0
    private var readInfoTexts: Set<String> {
        didSet {
            if let data = try? JSONEncoder().encode(Array(readInfoTexts)) {
                UserDefaults.standard.set(data, forKey: "readInfoTexts")
            }
        }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "readInfoTexts"),
            let stored = try? JSONDecoder().decode([String].self, from: data)
        {
            readInfoTexts = Set(stored)
        } else {
            readInfoTexts = []
        }
        manager = SocketManager(
            socketURL: URL(string: GlobalController.iApiBaseUrl)!,
            config: [
                .path("/rt/sio2"),
                .version(.two),
                .log(false),
                .reconnects(true),
                .reconnectAttempts(-1),
                .reconnectWaitMax(1),
                .reconnectWait(1),
            ]
        )
        socket = manager.defaultSocket
        startListeners()
    }

    private func startUpdater() {
        stopUpdater()
        loadedStatus = 0
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
        //  print("update")
        for index in connections.indices {
            let connection = connections[index]
            let oldTimeRemaining = connection.departureTimeRemaining
            let updatedTimeRemaining = getDepartureTimeRemainingText(
                connection.departureTime,
                connection.departureTimeRaw,
                connection.type
            )
            if oldTimeRemaining != updatedTimeRemaining {
                DispatchQueue.main.async {
                    if self.connections.indices.contains(index) {
                        self.connections[index].departureTimeRemaining = updatedTimeRemaining
                    }
                }
            }
        }
    }

    private func fetchRegionalLiveDepartures() async {
        guard let stationId = currentStop.stationId else {
            print("Current stop has no stationId. Cannot fetch regional departures.")
            loadedStatus += 1
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateString = dateFormatter.string(from: Date())

        let calendar = Calendar.current
        let now = Date()
        let minutes =
            calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)

        fetchBApi(
            endpoint: "/mobile/v1/station/\(stationId)/timetable/\(dateString)/\(minutes)/1",
            type: RegionalConnectionsResponse.self
        ) { result in

            switch result {
            case .success(let response):
                var newRegionalConnections = response.current.map {
                    Connection(from: $0, for: self.currentStop)
                }
                newRegionalConnections.removeAll { connection in
                    connection.departureTimeRaw < (Date().timeIntervalSince1970 + 15)
                        || connection.type != "online"
                }

                self.internalRegionalConnections = newRegionalConnections
                self.sortAndPublishConnections()
            case .failure(let err):
                print("Error fetching or decoding regional departures. \(err)")
            }
            self.loadedStatus += 1
        }
    }

    private func getRegionalConnection(_ connection: Connection) -> Connection? {
        return internalRegionalConnections.first(where: {
            $0.line == connection.line && $0.type == "online"
                && $0.departureTimeCP == connection.departureTimeCP
        })
    }

    private func sortAndPublishConnections() {
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            var connectionsForPublish: [Connection] = []
            var regionalConnectionsToRemove: [String] = []
            connectionsForPublish.append(contentsOf: self.internalConnections)

            connectionsForPublish = self.internalConnections.map { connection in
                if var regionalConnection = self.getRegionalConnection(connection) {
                    // print("Replacing \(connection.id) with \(regionalConnection.id)")
                    regionalConnectionsToRemove.append(regionalConnection.id)
                    if connection.type == "online" {
                        return connection
                    }
                    regionalConnection.platform = connection.platform
                    return regionalConnection
                }
                return connection
            }
            let newRegionalConnections = self.internalRegionalConnections.filter {
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

            DispatchQueue.main.async {
                self.connections = connectionsForPublish
                print("connections", self.connections)
                print("socket.status", self.socket.status)
                if self.socket.status == .connected {
                    self.socketStatus = .connected
                    if self.loadedStatus > 1 {
                        self.connectionsEmpty =
                            self.connections.isEmpty && self.internalConnections.isEmpty
                            && self.internalRegionalConnections.isEmpty
                    }
                } else {
                    self.disconnect(reconnect: true)
                }
            }
        }
    }

    func connect() {
        if socket.status == .connected {
            print("Socket already connected, requesting fresh data...")
            self.socket.emit("tabStart", [self.currentStop.id, "*"] as [Any])
            self.socket.emit("infoStart")
            self.startUpdater()
        } else if socket.status == .connecting {
            print("Socket is connecting, will request data on connect event...")
        } else {
            print("Socket not connected, attempting to connect...")
            socket.connect()
        }
    }

    func disconnect(reconnect: Bool = false) {
        if socket.status == .disconnected || socket.status == .notConnected {
            if reconnect {
                self.connect()
            }
            return
        }
        self.reconnect = reconnect
        socket.disconnect()
    }

    func startListeners() {
        socket.on(clientEvent: .statusChange) { _, _ in
            let connectionStatus = self.socket.status
            DispatchQueue.main.async {
                print(connectionStatus.description)
                if connectionStatus != .connected {
                    self.socketStatus = connectionStatus
                }
            }
        }

        socket.on(clientEvent: .connect) { _, _ in
            print("connect")
            DispatchQueue.main.async {
                self.startUpdater()
            }
        }

        socket.on(clientEvent: .disconnect) { _, _ in
            DispatchQueue.main.async {
                self.connected = false
                self.stopUpdater()
                if self.reconnect {
                    self.reconnect = false
                    self.connect()
                }
            }
        }

        socket.on("cack") { _, _ in
            print("cack")
            self.connected = true
            self.socket.emit("tabStart", [self.currentStop.id, "*"] as [Any])
            self.socket.emit("infoStart")
        }

        socket.on("tabs") { data, _ in
            print("tabs")
            self.connectionsProcessingQueue.async {
                guard let platformArray = data.first as? [[String: Any]] else {
                    print(
                        "Error: Could not cast incoming data to the expected [[String: Any]] structure."
                    )
                    self.loadedStatus += 1
                    DispatchQueue.main.async {
                        self.connections = [Connection]()
                        self.internalConnections = [Connection]()
                    }
                    return
                }

                var newConnections = [Connection]()
                var platformsToUpdate = Set<Int>()

                for platformObject in platformArray {
                    if let _platform = platformObject["nastupiste"] as? Int,
                        let _stopId = platformObject["zastavka"] as? Int,
                        let connectionsJson = platformObject["tab"] as? [Any]
                    {
                        platformsToUpdate.insert(_platform)
                        for object in connectionsJson {
                            if let connectionJson = object as? [String: Any] {
                                if var connection = Connection(
                                    json: connectionJson, platform: _platform, stopId: _stopId
                                ) {
                                    if connection.id == self.expandedConnectionId {
                                        connection.expanded = true
                                        self.expandedConnectionId = nil
                                    }
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
                self.loadedStatus += 1
                self.sortAndPublishConnections()
            }
        }

        socket.on("vInfo") { data, _ in
            if let vehicleInfoJson = data[0] as? [String: Any] {
                if let newVehicleInfo = VehicleInfo(json: vehicleInfoJson) {
                    self.vehicleInfo.append(newVehicleInfo)
                }
            }
        }

        socket.on("iText") { data, _ in
            if let texts = data.first as? [String] {
                let filtered = texts.filter { !$0.isEmpty }
                DispatchQueue.main.async {
                    self.infoTexts = filtered
                    self.unreadInfoCount = filtered.filter { !self.readInfoTexts.contains($0) }.count
                }
            }
        }
    }

    func stopListeners() {
        socket.removeAllHandlers()
    }

    func markInfoTextsRead() {
        readInfoTexts.formUnion(infoTexts)
        unreadInfoCount = 0
    }

    func switchLocationChanging(_ value: Bool) {
        if value {
            changeLocation = true
            changeStop(GlobalController.getNearestStopId(), switchOnly: true)
        } else {
            changeLocation = false
        }
    }

    func changeStop(_ stopId: Int, switchOnly: Bool = false, expandConnection: String? = nil) {
        if stopId == -1 {
            switchLocationChanging(true)
        } else {
            if currentStop.id != stopId {
                if !switchOnly { switchLocationChanging(false) }
                currentStop.id = stopId
                if let currentStop = GlobalController.getStopById(stopId) {
                    self.currentStop = currentStop
                    self.connections = [Connection]()
                    self.internalConnections = [Connection]()
                    self.internalRegionalConnections = [Connection]()
                    self.vehicleInfo = [VehicleInfo]()
                    self.connectionsEmpty = false
                    disconnect(reconnect: true)
                }
            }
            if !connected {
                connect()
            }
            if let connectionId = expandConnection {
                expandedConnectionId = connectionId
            }
        }
    }
}
