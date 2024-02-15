//
//  self.swift
//  Transi
//
//  Created by magic_sk on 10/02/2024.
//

import CoreLocation
import Foundation

class TripPlannerController: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let saveDuration = UserDefaults.standard.integer(forKey: Stored.tripSaveDuration)
    private let searchTimestamp: TimeInterval = UserDefaults.standard.double(forKey: Stored.tripSearchTimestamp)
    @Published var trip = Trip()
    @Published var from: Stop = .empty
    @Published var to: Stop = .empty
    @Published var arrivalDeparture: ArrivalDeparture = .departure
    @Published var arrivalDepartureDate = Date()
    @Published var arrivalDepartureCustomDate = false
    @Published var loading: Bool = false
    @Published var loadingMore: Bool = false
    @Published var error: TripError?

    var lastSearchDate = Date()

    override init() {
        super.init()
        loadSavedTrip()
    }

    func fetchTrip(more: Bool = false) {
        DispatchQueue.global(qos: .userInitiated).async { [self] in
            if var fromId = from.stationId, var toId = to.stationId {
                DispatchQueue.main.async {
                    if more {
                        self.loadingMore = true
                    } else {
                        self.loading = true
                    }
                }
                if fromId == -1 { fromId = GlobalController.getNearestStationId() }
                if toId == -1 { toId = GlobalController.getNearestStationId() }

                let maxTransfers = UserDefaults.standard.integer(forKey: Stored.tripMaxTransfers)
                let maxWalkDuration = UserDefaults.standard.integer(forKey: Stored.tripMaxWalkDuration)

                print("fetching trip from \(fromId) to \(toId)")

                let searchDate = more ?
                    self.lastSearchDate.addingTimeInterval(.init(7200.0)) :
                    self.arrivalDepartureCustomDate ?
                    self.arrivalDepartureDate :
                    nil
                let searchDateFormatted = searchDate != nil ? searchDate!.formatted(.iso8601) : nil
                let searchFrom = arrivalDeparture == ArrivalDeparture.departure ? searchDateFormatted : nil
                let searchTo = arrivalDeparture == ArrivalDeparture.arrival ? searchDateFormatted : nil

                let requestBody = TripReq(
                    max_walk_duration: maxWalkDuration,
                    max_transfers: maxTransfers,
                    search_from_hours: arrivalDeparture == ArrivalDeparture.arrival ? 2 : nil,
                    search_to_hours: arrivalDeparture == ArrivalDeparture.departure ? 2 : nil,
                    search_from: searchFrom,
                    search_to: searchTo,
                    from_station_id: [fromId],
                    to_station_id: [toId]
                )

                do {
                    let jsonEncoder = JSONEncoder()
                    let jsonBody = try jsonEncoder.encode(requestBody)
                    print(String(data: jsonBody, encoding: String.Encoding.utf8)! as String)

                    var request = URLRequest(url: URL(string: "\(GlobalController.rApiBaseUrl)/mobile/v1/raptor/")!)
                    request.httpMethod = "POST"
                    request.setValue("\(String(describing: jsonBody.count))", forHTTPHeaderField: "Content-Length")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Dalvik/2.1.0 (Linux; U; Android 12; Pixel 6)", forHTTPHeaderField: "User-Agent")
                    request.setValue(GlobalController.rApiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue(GlobalController.getSessionToken(), forHTTPHeaderField: "x-session")
                    request.httpBody = jsonBody

                    GlobalController.fetchData(request: request, type: Trip.self) { trip in
                        print("fetched trip \(trip.journey?.count ?? 0)")
                        if trip.journey?.count ?? 0 < 1 {
                            DispatchQueue.main.async {
                                self.loading = false
                                self.error = .noJourneys
                            }
                        } else {
                            let timestamp = Date().timeIntervalSince1970
                            self.lastSearchDate = searchDate ?? Date()
                            UserDefaults.standard.save(customObject: trip, forKey: Stored.trip)
                            UserDefaults.standard.setValue(timestamp, forKey: Stored.tripSearchTimestamp)
                            DispatchQueue.main.async {
                                self.loading = false
                                if more {
                                    self.trip.journey?.append(contentsOf: trip.journey!)
                                } else {
                                    self.trip = trip
                                }
                            }
                        }
                    }
                } catch {
                    DispatchQueue.main.async {
                        self.loading = false
                        self.error = .basic
                    }
                }
            }
        }
    }

    func loadMoreTripsIfNeeded(_ journey: Journey) {
        if journey.journeyGuid == trip.journey?.last?.journeyGuid {
            fetchTrip(more: true)
        }
    }
    
    func fetchTripToActualStop() {
        if LocationProvider.lastLocation != nil {
            from = .actualLocation
        }
        to = GlobalController.virtualTable.currentStop
        fetchTrip()
    }

    func loadSavedTrip() {
        let dateOfLastTrip = Date(timeIntervalSince1970: searchTimestamp)
        let differenceInHours = Date.now.timeIntervalSince(dateOfLastTrip) / 3600
        if saveDuration == -1 || Int(differenceInHours) < saveDuration {
            if let cachedTrip = UserDefaults.standard.retrieve(object: Trip.self, forKey: Stored.trip) {
                DispatchQueue.main.async {
                    self.trip = cachedTrip
                }
            }
        }
    }

    public func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard locations.last != nil else { return }
        print("got new location trip")
        DispatchQueue.main.async {
            if self.from == .empty { self.from = .actualLocation }
        }
    }
}
