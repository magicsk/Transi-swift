//
//  TripPlannerController.swift
//  Transi
//
//  Created by magic_sk on 10/02/2024.
//

import CoreLocation
import Foundation

class TripPlannerController: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let saveDuration = UserDefaults.standard.integer(forKey: Stored.tripSaveDuration)
    private let searchTimestamp: TimeInterval = UserDefaults.standard.double(
        forKey: Stored.tripSearchTimestamp)
    @Published var trip = Trip()
    @Published var from: Stop = .empty
    @Published var to: Stop = .empty
    @Published var arrivalDeparture: ArrivalDeparture = .departure
    @Published var arrivalDepartureDate = Date()
    @Published var arrivalDepartureCustomDate = false
    @Published var loading: Bool = false
    @Published var loadingMore: Bool = false
    @Published var error: TripError?

    enum FetchSource {
        case initial
        case moreRApi
        case moreIApi
    }

    private var nextRApiSearchDate: Date?
    private var nextIApiSearchDate: Date?
    private var lastSearchDate = Date()

    override init() {
        super.init()
        loadSavedTrip()
    }

    func fetchTrip(source: FetchSource = .initial) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            guard let params = self.prepareFetchParameters(source: source) else { return }

            DispatchQueue.main.async {
                if source != .initial { self.loadingMore = true } else { self.loading = true }
            }

            print("fetching trip from \(params.fromId) to \(params.toId)")

            self.performFetches(
                requestBody: params.requestBody,
                iApiUrl: params.iApiUrl
            ) { rResult, iResult in

                self.handleFetchResults(
                    rResult: rResult,
                    iResult: iResult,
                    source: source
                )
            }
        }
    }

    private func prepareFetchParameters(source: FetchSource) -> FetchParams? {
        guard var fromId = from.stationId, var toId = to.stationId else { return nil }

        if fromId == -1 { fromId = GlobalController.getNearestStationId() }
        if toId == -1 { toId = GlobalController.getNearestStationId() }

        var fromStopId = self.from.id
        var toStopId = self.to.id
        if fromStopId == -1 { fromStopId = GlobalController.getNearestStopId() }
        if toStopId == -1 { toStopId = GlobalController.getNearestStopId() }

        let maxTransfers = UserDefaults.standard.integer(forKey: Stored.tripMaxTransfers)
        let maxWalkDuration = UserDefaults.standard.integer(forKey: Stored.tripMaxWalkDuration)

        let initialSearchDate = self.arrivalDepartureCustomDate ? self.arrivalDepartureDate : Date()

        if source == .initial {
            self.nextRApiSearchDate = initialSearchDate
            self.nextIApiSearchDate = initialSearchDate
        }

        var requestBody: TripReq? = nil
        var iApiUrl: String? = nil

        if source == .initial || source == .moreRApi {
            let rApiDate = self.nextRApiSearchDate ?? initialSearchDate
            let searchDateFormatted = rApiDate.formatted(.iso8601)

            let searchFrom = (arrivalDeparture == .departure) ? searchDateFormatted : nil
            let searchTo = (arrivalDeparture == .arrival) ? searchDateFormatted : nil

            requestBody = TripReq(
                max_walk_duration: maxWalkDuration,
                max_transfers: maxTransfers,
                search_from_hours: arrivalDeparture == .arrival ? 2 : nil,
                search_to_hours: arrivalDeparture == .departure ? 2 : nil,
                search_from: searchFrom,
                search_to: searchTo,
                from_station_id: [fromId],
                to_station_id: [toId]
            )
        }

        if source == .initial || source == .moreIApi {
            let iApiDate = self.nextIApiSearchDate ?? initialSearchDate
            let searchDateFormatted = String(iApiDate.formatted(.iso8601).split(separator: "T")[0])
            let searchTime = iApiDate.formatted(Date.FormatStyle().hour().minute(.twoDigits))

            var iApiEndpoint = URLComponents(string: "/ba/api/cepo")!
            iApiEndpoint.queryItems = [
                URLQueryItem(name: "v", value: "7"),
                URLQueryItem(name: "a", value: "g\(fromStopId)"),
                URLQueryItem(name: "b", value: "g\(toStopId)"),
                URLQueryItem(name: "pd", value: searchDateFormatted),
                URLQueryItem(name: "pt", value: searchTime),
                URLQueryItem(name: "pa", value: arrivalDeparture == .arrival ? "1" : "0"),
                URLQueryItem(name: "pl", value: "1.0-4.0"),
                URLQueryItem(name: "pp", value: "0"),
                URLQueryItem(name: "pc", value: "0"),
                URLQueryItem(name: "format", value: "0"),
                URLQueryItem(name: "op", value: "Planner"),
            ]
            iApiUrl = iApiEndpoint.url?.absoluteString
        }

        return FetchParams(
            fromId: fromId,
            toId: toId,
            requestBody: requestBody,
            iApiUrl: iApiUrl
        )
    }

    private func performFetches(
        requestBody: TripReq?, iApiUrl: String?,
        completion: @escaping (RApiTrip?, IApiTripResponse?) -> Void
    ) {
        let group = DispatchGroup()
        var rApiResult: RApiTrip?
        var iApiResult: IApiTripResponse?

        if let requestBody = requestBody {
            group.enter()

            func fetchRApi(body: TripReq, isRetry: Bool) {
                do {
                    let jsonBody = try JSONEncoder().encode(body)
                    fetchRApiPost(
                        endpoint: "/mobile/v1/raptor/", jsonBody: jsonBody, type: RApiTrip.self
                    ) { result in
                        switch result {
                        case .success(let data):
                            let isEmpty = data.journey?.isEmpty ?? true

                            if isEmpty && !isRetry {
                                var newBody = body
                                var didChange = false

                                if newBody.search_from_hours == 2 {
                                    newBody.search_from_hours = 8
                                    didChange = true
                                }
                                if newBody.search_to_hours == 2 {
                                    newBody.search_to_hours = 8
                                    didChange = true
                                }

                                if didChange {
                                    print("rApi empty, retrying with 8 hours...")
                                    fetchRApi(body: newBody, isRetry: true)
                                    return
                                }
                            }

                            rApiResult = data

                        case .failure(let err):
                            print("R-Api Error: \(err)")
                        }
                        group.leave()
                    }
                } catch {
                    print("Req Body Encode Error: \(error)")
                    group.leave()
                }
            }

            fetchRApi(body: requestBody, isRetry: false)
        }

        if let iApiUrl = iApiUrl {
            group.enter()
            fetchIApi(endpoint: iApiUrl, type: IApiTripResponse.self) { result in
                if case .success(let data) = result {
                    iApiResult = data
                } else if case .failure(let err) = result {
                    print("I-Api Error: \(err)")
                }
                group.leave()
            }
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            completion(rApiResult, iApiResult)
        }
    }

    private func handleFetchResults(
        rResult: RApiTrip?, iResult: IApiTripResponse?, source: FetchSource
    ) {
        let rJourneys = rResult?.journey ?? []
        let iJourneys = iResult?.journeys ?? []
        let twoHours: TimeInterval = 7200.0

        if rResult != nil || source == .moreRApi {
            if let current = self.nextRApiSearchDate {
                self.nextRApiSearchDate = current.addingTimeInterval(twoHours)
            }
        }

        if (iResult != nil || source == .moreIApi) && iJourneys.isEmpty {
            if let current = self.nextIApiSearchDate {
                self.nextIApiSearchDate = current.addingTimeInterval(3600)
            }
        }

        let newUnifiedJourneys = mapRApiToJourneys(rJourneys) + mapIApiToJourneys(iJourneys)

        if !iJourneys.isEmpty {
            let mappedIJourneys = mapIApiToJourneys(iJourneys)
            if let last = mappedIJourneys.last?.parts?.first?.startDeparture {
                self.nextIApiSearchDate = last.addingTimeInterval(60)
            }
        }

        DispatchQueue.main.async {
            self.loading = false
            self.loadingMore = false

            if source == .initial && newUnifiedJourneys.isEmpty {
                self.error = .noJourneys
                return
            }

            if source == .initial {

                let uniqueJourneys = Array(Set(newUnifiedJourneys)).sorted {
                    ($0.parts?.first?.startDeparture ?? Date())
                        < ($1.parts?.first?.startDeparture ?? Date())
                }

                let timestamp = Date().timeIntervalSince1970
                self.lastSearchDate = Date()

                let newTrip = Trip(journey: uniqueJourneys)
                self.trip = newTrip

                UserDefaults.standard.save(customObject: newTrip, forKey: Stored.trip)
                UserDefaults.standard.setValue(timestamp, forKey: Stored.tripSearchTimestamp)

            } else {
                let combinedJourneys = (self.trip.journey ?? []) + newUnifiedJourneys
                let uniqueJourneys = Array(Set(combinedJourneys)).sorted {
                    ($0.parts?.first?.startDeparture ?? Date())
                        < ($1.parts?.first?.startDeparture ?? Date())
                }
                self.trip.journey = uniqueJourneys
                UserDefaults.standard.save(customObject: self.trip, forKey: Stored.trip)
            }
        }
    }

    func loadMoreTripsIfNeeded(_ journey: Journey) {
        let lastRJourney = trip.journey?.last(where: { $0.id.hasPrefix("r-") })
        let lastIJourney = trip.journey?.last(where: { $0.id.hasPrefix("i-") })

        if journey.id == lastRJourney?.id {
            print("fetching more rApi")
            fetchTrip(source: .moreRApi)
        }

        if journey.id == lastIJourney?.id {
            print("fetching more iApi")
            fetchTrip(source: .moreIApi)
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
            if let cachedTrip = UserDefaults.standard.retrieve(
                object: Trip.self, forKey: Stored.trip)
            {
                DispatchQueue.main.async {
                    self.trip = cachedTrip
                }
            }
        }
    }

    public func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard locations.last != nil else { return }
        DispatchQueue.main.async {
            if self.from == .empty { self.from = .actualLocation }
        }
    }
}
