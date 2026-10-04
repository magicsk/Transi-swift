//
//  PartLiveTracker.swift
//  Transi
//
//  Created by magic_sk on 04/10/2026.
//

import Foundation

extension Part {
    /// This leg's departure on a stop's live board: the same line and platform, scheduled within 3 minutes
    /// (the board's timetable can differ from the planner's), the closest in time, then by headsign. Once
    /// `busID`, the vehicle already followed, is known, only it matches, so the line's next departure never
    /// takes its place. Regional rows have an unknown platform (-1).
    func liveConnection(
        in connections: [Connection], platform: Int?, scheduled: Date, busID: String? = nil
    ) -> Connection? {
        let time = scheduled.timeIntervalSince1970
        func rank(_ connection: Connection) -> (TimeInterval, Int) {
            (abs(connection.departureTimeCP - time), connection.headsign == tripHeadsign ? 0 : 1)
        }
        return connections
            .filter {
                $0.line == routeShortName && abs($0.departureTimeCP - time) <= 180
                    && (platform == nil || $0.platform == platform || $0.platform == -1)
                    && (busID == nil || $0.busID == busID)
            }
            .min { rank($0) < rank($1) }
    }
}

/// Follows one transit leg's vehicle on a stop's live departure board. It opens its own socket, so run it
/// only while the trip detail or the trip Live Activity needs it, and call `stop()` when done.
final class PartLiveTracker {
    private var controller: SimpleVirtualTableController?
    /// The vehicle followed since the first live match; nil until then.
    private var busID: String?

    /// Watches `part` at `stop` (the boarding stop by default) and calls `onUpdate` on the main thread with
    /// its departure there, or nil while it is not on the board. Follows the first vehicle matched live, or
    /// `busID` from an earlier tracker, and never switches to another one. Nil for walks and stops missing
    /// from the stops list. Call on the main thread.
    init?(
        part: Part, at stop: PartStop? = nil, busID: String? = nil,
        onUpdate: @escaping (Connection?, VehicleInfo?) -> Void
    ) {
        let target = stop ?? part.stops?.first
        let platformLabel = target?.platform ?? part.startStopCode
        guard part.routeType != 64,
              let boardStop = target?.stopId.flatMap(GlobalController.getStopById)
                  ?? GlobalController.stopsListProvider.stops.stop(
                      stationId: stop == nil ? part.startStationId : nil,
                      name: target?.name ?? part.startStopName,
                      platform: platformLabel
                  )
        else { return nil }

        let platform = boardStop.platformLabels?.first { $0.label == platformLabel }.flatMap { Int($0.id) }
        let scheduled = target?.time ?? part.startDeparture
        self.busID = busID
        // Only reads the board: the table's Live Activities for this stop stay with their own controllers.
        let controller = SimpleVirtualTableController(stop: boardStop.id, updatesLiveActivities: false)
        controller.onUpdate = { [weak self, weak controller] in
            guard let self, let controller else { return }
            let connection = part.liveConnection(
                in: controller.connections, platform: platform, scheduled: scheduled, busID: self.busID
            )
            if self.busID == nil, let connection, connection.type == "online" {
                self.busID = connection.busID
            }
            onUpdate(connection, connection.flatMap { connection in
                controller.vehicleInfo.first { $0.issi == connection.busID }
            })
        }
        self.controller = controller
    }

    func stop() {
        controller?.onUpdate = nil
        controller?.disconnect()
        controller = nil
    }

    deinit {
        stop()
    }
}
