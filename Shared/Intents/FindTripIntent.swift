//
//  FindTripIntent.swift
//  Transi
//
//  Created by magic_sk on 06/03/2026.
//

import AppIntents
import Foundation

struct FindTripIntent: AppIntent {
    static var title: LocalizedStringResource = "Find a Trip"
    static var description = IntentDescription("Search for public transit trips between two stops.")

    @Parameter(title: "From", description: "The starting stop")
    var from: String

    @Parameter(title: "To", description: "The destination stop")
    var to: String

    @Parameter(title: "Time", description: "When you want to travel")
    var date: Date?

    static var parameterSummary: some ParameterSummary {
        Summary("Find trip from \(\.$from) to \(\.$to) at \(\.$date)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        let fromStop = GlobalController.stopsListProvider.getStopFromName(from)
        let toStop = GlobalController.stopsListProvider.getStopFromName(to)
        
        guard let fromStop = fromStop, let toStop = toStop else {
            return .result(value: ["Stop not found"])
        }
        
        let planner = GlobalController.tripPlanner
        planner.from = fromStop
        planner.to = toStop
        planner.arrivalDepartureDate = date ?? Date()
        planner.arrivalDepartureCustomDate = date != nil
        
        // Use the offline query directly to get results for the intent
        return await withCheckedContinuation { continuation in
            GlobalController.timetableDatabase.queryOfflineTrip(
                fromName: fromStop.name ?? "",
                toName: toStop.name ?? "",
                date: date ?? Date(),
                arrivalDeparture: .departure,
                maxTransfers: 1,
                maxWalkDuration: 15
            ) { journeys in
                if journeys.isEmpty {
                    continuation.resume(returning: .result(value: ["No journeys found offline."]))
                } else {
                    let results = journeys.compactMap { journey -> String? in
                        guard let part = journey.parts?.first else { return nil }
                        let dep = part.startDeparture.formatted(date: .omitted, time: .shortened)
                        let arr = part.endArrival.formatted(date: .omitted, time: .shortened)
                        return "\(part.routeShortName ?? "?") (\(dep) - \(arr))"
                    }
                    continuation.resume(returning: .result(value: results))
                }
            }
        }
    }
}
