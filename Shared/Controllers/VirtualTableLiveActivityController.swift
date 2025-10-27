//
//  VirtualTableLiveActivityController.swift
//  Transi
//
//  Created by magic_sk on 24/02/2024.
//

import ActivityKit
import AudioToolbox
import Foundation
import UIKit

enum LiveActivityManagerError: Error {
    case failedToGetId
}

struct LiveActivityTab {
    let id: String
    let connectionId: String
    let platform: Int
    let stopId: Int
    var controller: SimpleVirtualTableController?
}

enum VirtualTableLiveActivityController {
    static var liveActivities = [LiveActivityTab]()

    @discardableResult
    static func startActivity(_ connection: Connection, _ vehicleInfo: VehicleInfo?) throws -> String {
        GlobalController.startBackgroundMode()
        var activity: Activity<VirtualTableActivityAttributes>?
        let initialState = VirtualTableActivityAttributes.ContentState(connection: connection, vehicleInfo: vehicleInfo)
        do {
            activity = try Activity.request(
                attributes: VirtualTableActivityAttributes(),
                contentState: initialState,
                pushType: nil
            )
            guard let id = activity?.id else { throw LiveActivityManagerError.failedToGetId }
            let reuseController = liveActivities.first(where: { la in
                la.stopId == connection.stopId
            })
            liveActivities.append(
                LiveActivityTab(
                    id: id,
                    connectionId: connection.id,
                    platform: connection.platform,
                    stopId: connection.stopId,
                    controller: reuseController?.controller ?? SimpleVirtualTableController(stop: connection.stopId)
                )
            )
            return id
        } catch {
            throw error
        }
    }

    static func activateExistingActitivites() {
        let activities = Activity<VirtualTableActivityAttributes>.activities
        GlobalController.cancelApplicationQuitNotification()
        if !activities.isEmpty {
            GlobalController.startBackgroundMode()
            activities.forEach { activity in
                let connection = activity.contentState.connection
                let reuseController = liveActivities.first(where: { la in
                    la.stopId == connection.stopId
                })
                liveActivities.append(
                    LiveActivityTab(
                        id: activity.id,
                        connectionId: connection.id,
                        platform: connection.platform,
                        stopId: connection.stopId,
                        controller: reuseController?.controller ?? SimpleVirtualTableController(stop: connection.stopId)
                    )
                )
            }
        }
    }

    static func listAllActivities() -> [String] {
        let activities = Activity<VirtualTableActivityAttributes>.activities
        return activities.map {
            $0.id
        }
    }

    static func listAllTabActivities() -> [LiveActivityTab] {
        let activities = listAllActivities()
        liveActivities = liveActivities.filter { liveActivity in
            let containts = activities.contains(liveActivity.id)
            if !containts {
                liveActivity.controller?.disconnect()
            }
            return containts
        }
        if liveActivities.isEmpty && GlobalController.appState.phase == .background {
            GlobalController.stopBackgroundMode()
        }
        return liveActivities
    }

    static func endAllActivities() async {
        for activity in Activity<VirtualTableActivityAttributes>.activities {
            await activity.end(dismissalPolicy: .immediate)
        }
    }

    static func endActivity(_ id: String) async {
        await Activity<VirtualTableActivityAttributes>.activities.first(where: { $0.id == id })?.end(dismissalPolicy: .immediate)
        if Activity<VirtualTableActivityAttributes>.activities.isEmpty {
            GlobalController.stopBackgroundMode()
        }
    }

    static func updateActivity(id: String, connection: Connection, vehicleInfo: VehicleInfo?) async {
        let updatedContentState =
            VirtualTableActivityAttributes.ContentState(
                connection: connection,
                vehicleInfo: vehicleInfo
            )
        let activity = Activity<VirtualTableActivityAttributes>.activities.first(where: { $0.id == id })
        let oldConnection = activity?.contentState.connection

        var alertConfig: AlertConfiguration?
        let departureTimeRemainingRaw = Int(connection.departureTimeRaw - Date().timeIntervalSince1970)
        let liveActivitySounds = UserDefaults.standard.bool(forKey: Stored.liveActivitiesSounds)

        let isNew = oldConnection?.lastStopName != connection.lastStopName || oldConnection?.delayText != connection.delayText || oldConnection?.departureTimeRemaining != connection.departureTimeRemaining
        if departureTimeRemainingRaw < 200, isNew {
            let vehicleText = vehicleInfo != nil ? "\n\(vehicleInfo!.type) #\(String(connection.busID.dropFirst(2)))" : ""
            alertConfig = AlertConfiguration(
                title: "\(connection.line) ▶ \(connection.headsign) in \(connection.departureTimeRemaining)",
                body: "\(connection.lastStopName)\n\(connection.delayText)\(vehicleText)",
                sound: .named("")
            )
        }
        await activity?.update(using: updatedContentState, alertConfiguration: alertConfig)
        if alertConfig != nil, liveActivitySounds, GlobalController.appState.phase == .background, await UIApplication.shared.isProtectedDataAvailable {
            AudioServicesPlayAlertSound(SystemSoundID(1111))
        }
    }
}
