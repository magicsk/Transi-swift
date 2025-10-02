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
    private var updaterRegionalTabs: Timer.TimerPublisher?
    private var updaterRegionalTabsSubscription: AnyCancellable?
    private var publisheDebouncer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var reconnect: Bool = false
    private var expadndTabId: String? = nil
    private let tabsProcessingQueue = DispatchQueue(label: "eu.magicsk.transi.tabsProcessingQueue")

    @Published var tabs = [Tab]()
    var internalTabs = [Tab]()
    var internalRegionalTabs = [Tab]()
    @Published var vehicleInfo = [VehicleInfo]()
    @Published var changeLocation = true
    @Published var currentStop: Stop = .example
    @Published var socketStatus = "unknown"
    @Published var lastExpandedTab: Tab? = nil

    init() {
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
        Task {
            await self.fetchRegionalLiveDepartures()
        }
        updater = Timer.publish(every: 10, on: .current, in: .common)
        updaterSubscription = updater?.autoconnect().sink(receiveValue: { [weak self] _ in
            self?.updateTabs()
        })

        updaterRegionalTabs = Timer.publish(every: 50, on: .current, in: .common)
        updaterRegionalTabsSubscription = updaterRegionalTabs?.autoconnect().sink(receiveValue: { [weak self] _ in
            Task {
                await self?.fetchRegionalLiveDepartures()
            }
        })
    }

    private func stopUpdater() {
        updaterSubscription?.cancel()
        updaterSubscription = nil
        updater = nil
        updaterRegionalTabsSubscription?.cancel()
        updaterRegionalTabsSubscription = nil
        updaterRegionalTabs = nil
    }

    private func updateTabs() {
        //  print("update")
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

    private func fetchRegionalLiveDepartures() async {
        guard let stationId = currentStop.stationId else {
            print("Current stop has no stationId. Cannot fetch regional departures.")
            return
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyyMMdd"
        let dateString = dateFormatter.string(from: Date())

        let calendar = Calendar.current
        let now = Date()
        let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)

        fetchBApi(
            endpoint: "/mobile/v1/station/\(stationId)/timetable/\(dateString)/\(minutes)/1",
            type: RegionalTabsResponse.self
        ) { result in

            switch result {
            case let .success(response):
                var newRegionalTabs = response.current.map { Tab(from: $0, for: self.currentStop) }
                newRegionalTabs.removeAll { tab in
                    tab.departureTimeRaw < (Date().timeIntervalSince1970 + 15) || tab.type != "online"
                }

                self.internalRegionalTabs = newRegionalTabs
                self.sortAndPublishTabs()
            case let .failure(err):
                print("Error fetching or decoding regional departures. \(err)")
            }
        }
    }

    private func getRegionalTab(_ tab: Tab) -> Tab? {
        return internalRegionalTabs.first(where: { $0.line == tab.line && $0.type == "online" && $0.departureTimeCP == tab.departureTimeCP })
    }

    private func sortAndPublishTabs() {
        DispatchQueue.global(qos: .userInteractive).async { [weak self] in
            guard let self = self else { return }
            print("run", self.internalTabs.count)
            var tabsForPublish: [Tab] = []
            var regionalTabsToRemove: [String] = []
            tabsForPublish.append(contentsOf: self.internalTabs)

            tabsForPublish = self.internalTabs.map { tab in
                if var regionalTab = self.getRegionalTab(tab) {
                    print("Replacing \(tab.id) with \(regionalTab.id)")
                    regionalTabsToRemove.append(regionalTab.id)
                    if tab.type == "online" {
                        return tab
                    }
                    regionalTab.platform = tab.platform
                    return regionalTab
                }
                return tab
            }
            print(regionalTabsToRemove)
            let newRegionalTabs = self.internalRegionalTabs.filter { $0.departureTimeCP < Date().timeIntervalSince1970 && !regionalTabsToRemove.contains($0.id) }
            print(newRegionalTabs)
            tabsForPublish.append(contentsOf: newRegionalTabs)
            
            tabsForPublish.sort { tab1, tab2 in
                if tab1.departureTimeRaw == tab2.departureTimeRaw {
                    return tab1.id < tab2.id
                } else {
                    return tab1.departureTimeRaw < tab2.departureTimeRaw
                }
            }
            
            DispatchQueue.main.async {
                self.tabs = tabsForPublish
                self.socketStatus = "connected"
            }
        }
    }

    func connect() {
        if socket.status == .notConnected || socket.status == .disconnected {
            print("Socket not connected, attempting to connect...")
            socket.connect()
        }
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
            print("connect")
            DispatchQueue.main.async {
                self.startUpdater()
            }
        }

        socket.on(clientEvent: .disconnect) { _, _ in
            DispatchQueue.main.async {
                self.tabs = [Tab]()
                self.internalTabs = [Tab]()
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
            print("cack")
            self.connected = true
            self.socket.emit("tabStart", [self.currentStop.id, "*"] as [Any])
            self.socket.emit("infoStart")
        }

        socket.on("tabs") { data, _ in
            self.tabsProcessingQueue.async {
                guard let platformArray = data.first as? [[String: Any]] else {
                    print("Error: Could not cast incoming data to the expected [[String: Any]] structure.")
                    DispatchQueue.main.async {
                        self.tabs = [Tab]()
                        self.internalTabs = [Tab]()
                        self.socketStatus = "error"
                    }
                    return
                }

                var newTabs = [Tab]()
                var platformsToUpdate = Set<Int>()

                for platformObject in platformArray {
                    if let _platform = platformObject["nastupiste"] as? Int,
                       let _stopId = platformObject["zastavka"] as? Int,
                       let tabsJson = platformObject["tab"] as? [Any]
                    {
                        platformsToUpdate.insert(_platform)
                        for object in tabsJson {
                            if let tabJson = object as? [String: Any] {
                                if var tab = Tab(json: tabJson, platform: _platform, stopId: _stopId) {
                                    if tab.id == self.expadndTabId {
                                        tab.expanded = true
                                        self.expadndTabId = nil
                                    }
                                    newTabs.append(tab)
                                }
                            }
                        }
                    }
                }

                self.internalTabs.removeAll { tab in
                    platformsToUpdate.contains(tab.platform)
                }

                self.internalTabs.append(contentsOf: newTabs)
                self.sortAndPublishTabs()
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

    func changeStop(_ stopId: Int, switchOnly: Bool = false, expandTab: String? = nil) {
        if stopId == -1 {
            switchLocationChanging(true)
        } else {
            if currentStop.id != stopId {
                if !switchOnly { switchLocationChanging(false) }
                currentStop.id = stopId
                if let currentStop = GlobalController.getStopById(stopId) {
                    self.currentStop = currentStop
                    disconnect(reconnect: true)
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
