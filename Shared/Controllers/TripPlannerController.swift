//
//  TripPlannerController.swift
//  Transi
//
//  Created by magic_sk on 10/02/2024.
//

import CoreLocation
import Foundation

struct RecentTripSearch: Codable, Equatable, Identifiable {
    let from: Stop
    let to: Stop
    let arrivalDeparture: ArrivalDeparture
    let arrivalDepartureDate: Date
    let arrivalDepartureCustomDate: Bool
    var trip: Trip?
    var tripSavedAt: Date?

    var id: String { "\(from.id):\(to.id)" }
    var cacheID: String {
        let dateID = arrivalDepartureCustomDate
            ? String(arrivalDepartureDate.timeIntervalSinceReferenceDate.bitPattern)
            : "now"
        return "\(id):\(arrivalDeparture.rawValue):\(dateID)"
    }

    private enum CodingKeys: String, CodingKey {
        case from
        case to
        case arrivalDeparture
        case arrivalDepartureDate
        case arrivalDepartureCustomDate
        case trip
        case tripSavedAt
    }

    init(
        from: Stop,
        to: Stop,
        arrivalDeparture: ArrivalDeparture = .departure,
        arrivalDepartureDate: Date = Date(),
        arrivalDepartureCustomDate: Bool = false,
        trip: Trip? = nil,
        tripSavedAt: Date? = nil
    ) {
        self.from = from
        self.to = to
        self.arrivalDeparture = arrivalDeparture
        self.arrivalDepartureDate = arrivalDepartureDate
        self.arrivalDepartureCustomDate = arrivalDepartureCustomDate
        self.trip = trip
        self.tripSavedAt = tripSavedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        from = try container.decode(Stop.self, forKey: .from)
        to = try container.decode(Stop.self, forKey: .to)
        arrivalDeparture = try container.decodeIfPresent(
            ArrivalDeparture.self,
            forKey: .arrivalDeparture
        ) ?? .departure
        arrivalDepartureDate = try container.decodeIfPresent(
            Date.self,
            forKey: .arrivalDepartureDate
        ) ?? Date()
        arrivalDepartureCustomDate = try container.decodeIfPresent(
            Bool.self,
            forKey: .arrivalDepartureCustomDate
        ) ?? false
        trip = try container.decodeIfPresent(Trip.self, forKey: .trip)
        tripSavedAt = try container.decodeIfPresent(Date.self, forKey: .tripSavedAt)
    }

}

class TripPlannerController: NSObject, ObservableObject, CLLocationManagerDelegate {
    private static let recentSearchLimit = 10
    private let recentSearchQueue = DispatchQueue(label: "eu.magicsk.Transi.recentSearches", qos: .utility)
    @Published var trip = Trip()
    @Published var from: Stop = .empty
    @Published var to: Stop = .empty
    @Published var arrivalDeparture: ArrivalDeparture = .departure
    @Published var arrivalDepartureDate = Date()
    @Published var arrivalDepartureCustomDate = false
    @Published var loading: Bool = false
    @Published var loadingMore: Bool = false
    @Published var error: TripError?
    @Published private(set) var recentSearches = [RecentTripSearch]()

    enum FetchSource {
        case initial
        case moreRApi
        case moreIApi
    }

    private var nextRApiSearchDate: Date?
    private var nextIApiSearchDate: Date?
    private var lastSearchDate = Date()
    private let searchGenerationLock = NSLock()
    private var searchGeneration = 0

    override init() {
        super.init()
        loadSavedTrip()
    }

    func fetchTrip(source: FetchSource = .initial, recordSearch: Bool = true) {
        let selectedFrom = from
        let selectedTo = to

        if source == .initial {
            guard selectedFrom.name?.isEmpty == false, selectedTo.name?.isEmpty == false else {
                return
            }
        }

        if source == .initial && recordSearch {
            if !arrivalDepartureCustomDate { arrivalDepartureDate = Date() }
            rememberCurrentSearch()
        }

        let generation = generation(for: source)

        if source == .initial && UserDefaults.standard.bool(forKey: Stored.offlineTripPlanner) && GlobalController.timetableDatabase.isReady {
            fetchOfflineTrip(from: selectedFrom, to: selectedTo, generation: generation)
            return
        }

        guard let params = prepareFetchParameters(
            source: source,
            from: selectedFrom,
            to: selectedTo
        ) else { return }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            DispatchQueue.main.async {
                guard self.isCurrentSearch(generation) else { return }
                if source != .initial { self.loadingMore = true } else { self.loading = true }
            }

            #if DEBUG
            print("fetching trip from \(params.fromId) to \(params.toId)")
            #endif

            self.performFetches(
                requestBody: params.requestBody,
                iApiUrl: params.iApiUrl
            ) { rResult, iResult in

                self.handleFetchResults(
                    rResult: rResult,
                    iResult: iResult,
                    source: source,
                    generation: generation
                )
            }
        }
    }

    private func fetchOfflineTrip(from: Stop, to: Stop, generation: Int) {
        DispatchQueue.main.async {
            guard self.isCurrentSearch(generation) else { return }
            self.loading = true
            self.error = nil // Clear error on new search
        }
        let initialSearchDate = arrivalDepartureDate

        GlobalController.timetableDatabase.queryOfflineTrip(
            fromName: from.name ?? "",
            toName: to.name ?? "",
            date: initialSearchDate,
            arrivalDeparture: arrivalDeparture,
            maxTransfers: UserDefaults.standard.integer(forKey: Stored.tripMaxTransfers),
            maxWalkDuration: UserDefaults.standard.integer(forKey: Stored.tripMaxWalkDuration)
        ) { [weak self] journeys in
            guard let self = self else { return }

            DispatchQueue.main.async {
                guard self.isCurrentSearch(generation) else { return }
                self.loading = false
                if journeys.isEmpty {
                    self.trip = Trip()
                    self.error = .noJourneys
                } else {
                    self.error = nil // Clear any previous errors
                    let newTrip = Trip(journey: journeys)
                    self.trip = newTrip
                    self.cacheTripForCurrentSearch(newTrip)
                }
            }
        }
    }

    private func prepareFetchParameters(source: FetchSource, from: Stop, to: Stop) -> FetchParams? {
        guard var fromId = from.stationId, var toId = to.stationId else { return nil }

        if fromId == -1 { fromId = GlobalController.getNearestStationId() }
        if toId == -1 { toId = GlobalController.getNearestStationId() }

        var fromStopId = from.id
        var toStopId = to.id
        if fromStopId == -1 { fromStopId = GlobalController.getNearestStopId() }
        if toStopId == -1 { toStopId = GlobalController.getNearestStopId() }

        let maxTransfers = UserDefaults.standard.integer(forKey: Stored.tripMaxTransfers)
        let maxWalkDuration = UserDefaults.standard.integer(forKey: Stored.tripMaxWalkDuration)

        let initialSearchDate = arrivalDepartureDate

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
                                    #if DEBUG
                                print("rApi empty, retrying with 8 hours...")
                                #endif
                                    fetchRApi(body: newBody, isRetry: true)
                                    return
                                }
                            }

                            rApiResult = data

                        case .failure(let err):
                            #if DEBUG
                            print("R-Api Error: \(err)")
                            #endif
                        }
                        group.leave()
                    }
                } catch {
                    #if DEBUG
                    print("Req Body Encode Error: \(error)")
                    #endif
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
                    #if DEBUG
                    print("I-Api Error: \(err)")
                    #endif
                }
                group.leave()
            }
        }

        group.notify(queue: .global(qos: .userInitiated)) {
            completion(rApiResult, iApiResult)
        }
    }

    private func handleFetchResults(
        rResult: RApiTrip?, iResult: IApiTripResponse?, source: FetchSource,
        generation: Int
    ) {
        let rJourneys = rResult?.journey ?? []
        let iJourneys = iResult?.journeys ?? []
        let mappedIJourneys = mapIApiToJourneys(iJourneys)
        let newUnifiedJourneys = mapRApiToJourneys(rJourneys) + mappedIJourneys

        DispatchQueue.main.async {
            guard self.isCurrentSearch(generation) else { return }

            if rResult != nil || source == .moreRApi {
                if let current = self.nextRApiSearchDate {
                    self.nextRApiSearchDate = current.addingTimeInterval(7200)
                }
            }

            if (iResult != nil || source == .moreIApi) && iJourneys.isEmpty {
                if let current = self.nextIApiSearchDate {
                    self.nextIApiSearchDate = current.addingTimeInterval(3600)
                }
            } else if let last = mappedIJourneys.last?.parts?.first?.startDeparture {
                self.nextIApiSearchDate = last.addingTimeInterval(60)
            }

            self.loading = false
            self.loadingMore = false

            if source == .initial && newUnifiedJourneys.isEmpty {
                self.trip = Trip()
                self.error = .noJourneys
                return
            }

            if source == .initial {

                let uniqueJourneys = Array(Set(newUnifiedJourneys)).sorted {
                    ($0.parts?.first?.startDeparture ?? Date())
                        < ($1.parts?.first?.startDeparture ?? Date())
                }

                self.lastSearchDate = Date()

                let newTrip = Trip(journey: uniqueJourneys)
                self.trip = newTrip
                self.cacheTripForCurrentSearch(newTrip)


            } else {
                let combinedJourneys = (self.trip.journey ?? []) + newUnifiedJourneys
                let uniqueJourneys = Array(Set(combinedJourneys)).sorted {
                    ($0.parts?.first?.startDeparture ?? Date())
                        < ($1.parts?.first?.startDeparture ?? Date())
                }
                self.trip.journey = uniqueJourneys
                self.cacheTripForCurrentSearch(self.trip)
            }
        }
    }

    func loadMoreTripsIfNeeded(_ journey: Journey) {
        let lastRJourney = trip.journey?.last(where: { $0.id.hasPrefix("r-") })
        let lastIJourney = trip.journey?.last(where: { $0.id.hasPrefix("i-") })

        if journey.id == lastRJourney?.id {
            #if DEBUG
            print("fetching more rApi")
            #endif
            fetchTrip(source: .moreRApi)
        }

        if journey.id == lastIJourney?.id {
            #if DEBUG
            print("fetching more iApi")
            #endif
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

    func showRecentSearch(_ search: RecentTripSearch) {
        guard let search = recentSearches.first(where: { $0.id == search.id }) else { return }
        from = search.from
        to = search.to
        arrivalDeparture = search.arrivalDeparture
        arrivalDepartureDate = search.arrivalDepartureDate
        arrivalDepartureCustomDate = true
        if let cachedTrip = search.trip {
            _ = generation(for: .initial)
            trip = cachedTrip
            loading = false
            loadingMore = false
            error = nil
            preparePagination(for: cachedTrip)
        } else {
            fetchTrip(recordSearch: false)
        }
    }

    func clearRecentSearches() {
        _ = generation(for: .initial)
        loading = false
        loadingMore = false
        error = nil
        recentSearches.removeAll()
        recentSearchQueue.async {
            UserDefaults.standard.removeObject(forKey: Stored.tripRecentSearches)
        }
    }

    func currentSearchMatchesCriteria() -> Bool {
        let currentID = RecentTripSearch(from: from, to: to).id
        guard let search = recentSearches.first(where: { $0.id == currentID }) else {
            return false
        }
        return search.arrivalDeparture == arrivalDeparture
            && (!arrivalDepartureCustomDate
                || search.arrivalDepartureDate == arrivalDepartureDate)
    }

    private func rememberCurrentSearch() {
        guard from.name?.isEmpty == false, to.name?.isEmpty == false else { return }

        var savedFrom = from
        var savedTo = to
        savedFrom.score = nil
        savedTo.score = nil
        let search = RecentTripSearch(
            from: savedFrom,
            to: savedTo,
            arrivalDeparture: arrivalDeparture,
            arrivalDepartureDate: arrivalDepartureDate,
            arrivalDepartureCustomDate: arrivalDepartureCustomDate
        )

        recentSearches.removeAll { $0.id == search.id }
        recentSearches.insert(search, at: 0)
        recentSearches = Array(recentSearches.prefix(Self.recentSearchLimit))
        let searches = recentSearches
        recentSearchQueue.async {
            UserDefaults.standard.removeObject(forKey: Stored.trip)
            UserDefaults.standard.save(customObject: searches, forKey: Stored.tripRecentSearches)
        }

        assert(
            recentSearches.first == search
                && recentSearches.count <= Self.recentSearchLimit
                && Set(recentSearches.map(\.id)).count == recentSearches.count
        )
    }

    private func cacheTripForCurrentSearch(_ trip: Trip) {
        let currentID = RecentTripSearch(from: from, to: to, trip: nil).id
        guard let index = recentSearches.firstIndex(where: { $0.id == currentID }) else { return }
        recentSearches[index].trip = trip
        let savedAt = Date()
        recentSearches[index].tripSavedAt = savedAt
        let searches = recentSearches
        let cacheID = searches[index].cacheID
        recentSearchQueue.async {
            UserDefaults.standard.save(customObject: searches, forKey: Stored.tripRecentSearches)
            UserDefaults.standard.set(cacheID, forKey: Stored.tripSearchID)
        }
        assert(recentSearches[index].trip == trip)
    }

    private func preparePagination(for trip: Trip) {
        nextRApiSearchDate = trip.journey?
            .last(where: { $0.id.hasPrefix("r-") })?
            .parts?.first?.startDeparture.addingTimeInterval(60)
        nextIApiSearchDate = trip.journey?
            .last(where: { $0.id.hasPrefix("i-") })?
            .parts?.first?.startDeparture.addingTimeInterval(60)
    }

    private func generation(for source: FetchSource) -> Int {
        searchGenerationLock.withLock {
            if source == .initial { searchGeneration += 1 }
            return searchGeneration
        }
    }

    private func isCurrentSearch(_ generation: Int) -> Bool {
        searchGenerationLock.withLock { generation == searchGeneration }
    }

    func loadSavedTrip() {
        let generation = searchGenerationLock.withLock { searchGeneration }
        recentSearchQueue.async {
            let defaults = UserDefaults.standard
            let saveDuration = defaults.integer(forKey: Stored.tripSaveDuration)
            let now = Date()
            func canRestore(_ savedAt: Date?) -> Bool {
                saveDuration == -1 || (saveDuration > 0 && savedAt.map {
                    now.timeIntervalSince($0) < Double(saveDuration) * 3600
                } == true)
            }
            var searches = Array((defaults.retrieve(
                object: [RecentTripSearch].self, forKey: Stored.tripRecentSearches
            ) ?? []).prefix(Self.recentSearchLimit))
            for index in searches.indices where !canRestore(searches[index].tripSavedAt) {
                searches[index].trip = nil
            }
            let savedCacheID = defaults.string(forKey: Stored.tripSearchID)
            let legacySavedAt = Date(timeIntervalSince1970: defaults.double(forKey: Stored.tripSearchTimestamp))
            let legacyTrip = canRestore(legacySavedAt)
                ? defaults.retrieve(object: Trip.self, forKey: Stored.trip) : nil
            if let index = searches.firstIndex(where: { $0.cacheID == savedCacheID }),
                searches[index].tripSavedAt == nil, let legacyTrip
            {
                searches[index].trip = legacyTrip
                searches[index].tripSavedAt = legacySavedAt
            }
            let restoredSearch = searches.first(where: { $0.cacheID == savedCacheID }) ?? searches.first
            let savedSearches = searches
            DispatchQueue.main.async {
                guard self.isCurrentSearch(generation) else { return }
                self.recentSearches = savedSearches
                guard self.to == .empty,
                    self.from == .empty || self.from == .actualLocation
                else { return }
                if let restoredSearch {
                    self.from = restoredSearch.from
                    self.to = restoredSearch.to
                    self.arrivalDeparture = restoredSearch.arrivalDeparture
                    self.arrivalDepartureDate = restoredSearch.arrivalDepartureDate
                    self.arrivalDepartureCustomDate = true
                    self.trip = restoredSearch.trip ?? Trip()
                } else if let legacyTrip {
                    self.trip = legacyTrip
                }
                self.preparePagination(for: self.trip)
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
