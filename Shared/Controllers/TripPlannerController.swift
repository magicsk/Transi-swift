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
    private var nextOfflineSearchDate: Date?
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

        if source == .initial {
            // The local engine when it's on and has the newest timetables, else our server (which falls back to the
            // local engine or the online APIs when it fails).
            let database = GlobalController.timetableDatabase
            let useLocal = UserDefaults.standard.bool(forKey: Stored.offlineTripPlanner) && database.isReady && database.isLatest
            fetchOfflineTrip(from: selectedFrom, to: selectedTo, generation: generation, onServer: !useLocal)
            return
        }

        fetchOnlineTrip(source: source, from: selectedFrom, to: selectedTo, generation: generation)
    }

    /// The R-API and I-API search. Returns false when a stop has no station, so nothing was fetched.
    @discardableResult
    private func fetchOnlineTrip(source: FetchSource, from selectedFrom: Stop, to selectedTo: Stop, generation: Int) -> Bool {
        guard let params = prepareFetchParameters(
            source: source,
            from: selectedFrom,
            to: selectedTo
        ) else { return false }
        let stops = GlobalController.stopsListProvider.stops

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
                    generation: generation,
                    stops: stops
                )
            }
        }
        return true
    }

    /// A planner search by stop names, on our server (`s-` journeys) or the local engine (`o-` journeys). Both page
    /// the same way; a continuing page asks the source its first page came from.
    private func fetchOfflineTrip(from: Stop, to: Stop, generation: Int, append: Bool = false, onServer: Bool = false) {
        let searchDate: Date
        if append {
            guard !loadingMore, let nextDate = nextOfflineSearchDate else { return }
            searchDate = nextDate
            DispatchQueue.main.async {
                guard self.isCurrentSearch(generation) else { return }
                self.loadingMore = true
            }
        } else {
            searchDate = arrivalDepartureDate
            DispatchQueue.main.async {
                guard self.isCurrentSearch(generation) else { return }
                self.loading = true
                self.error = nil // Clear error on new search
            }
        }

        // Resolve "Actual location" (id=-1) to the nearest plannable stop's name, the stop the online path plans
        // from too; the nearest stop can be a railway station the planners don't know.
        let resolvedFromName: String
        if from.id == -1 {
            let nearestId = GlobalController.getNearestPlannableStopId()
            resolvedFromName = GlobalController.getStopById(nearestId)?.name ?? ""
        } else {
            resolvedFromName = from.name ?? ""
        }
        let resolvedToName: String
        if to.id == -1 {
            let nearestId = GlobalController.getNearestPlannableStopId()
            resolvedToName = GlobalController.getStopById(nearestId)?.name ?? ""
        } else {
            resolvedToName = to.name ?? ""
        }

        if resolvedFromName.isEmpty || resolvedToName.isEmpty {
            DispatchQueue.main.async {
                self.loading = false
                self.loadingMore = false
                if !append { self.error = .noJourneys }
            }
            return
        }

        let maxTransfers = UserDefaults.standard.integer(forKey: Stored.tripMaxTransfers)
        let maxWalkDuration = UserDefaults.standard.integer(forKey: Stored.tripMaxWalkDuration)
        let arrivingAfter = append && arrivalDeparture == .arrival ? searchDate : nil

        let handleJourneys = { [weak self] (journeys: [Journey]) in
            guard let self = self else { return }

            DispatchQueue.main.async {
                guard self.isCurrentSearch(generation) else { return }
                self.loading = false
                self.loadingMore = false
                if append {
                    let existing = self.trip.journey ?? []
                    let existingSet = Set(existing)
                    let newJourneys = journeys.filter { !existingSet.contains($0) }
                    self.advanceOfflineSearchDate(after: searchDate, journeys: journeys, continuing: true)
                    guard !newJourneys.isEmpty else { return }
                    self.trip.journey = self.sortedOfflineJourneys(existing + newJourneys)
                    self.cacheTripForCurrentSearch(self.trip)
                } else if journeys.isEmpty {
                    self.trip = Trip()
                    self.error = .noJourneys
                } else {
                    self.error = nil // Clear any previous errors
                    self.advanceOfflineSearchDate(after: searchDate, journeys: journeys, continuing: false)
                    let newTrip = Trip(journey: self.sortedOfflineJourneys(journeys))
                    self.trip = newTrip
                    self.cacheTripForCurrentSearch(newTrip)
                }
            }
        }

        guard onServer else {
            GlobalController.timetableDatabase.queryOfflineTrip(
                fromName: resolvedFromName, toName: resolvedToName, date: searchDate, arrivalDeparture: arrivalDeparture,
                maxTransfers: maxTransfers, maxWalkDuration: maxWalkDuration, arrivingAfter: arrivingAfter,
                completion: handleJourneys
            )
            return
        }

        var query = URLComponents()
        query.queryItems = [
            URLQueryItem(name: "from", value: resolvedFromName),
            URLQueryItem(name: "to", value: resolvedToName),
            URLQueryItem(name: "date", value: searchDate.formatted(.iso8601)),
            URLQueryItem(name: "mode", value: arrivalDeparture.rawValue),
            URLQueryItem(name: "max_transfers", value: String(maxTransfers)),
            URLQueryItem(name: "max_walk", value: String(maxWalkDuration)),
        ] + (arrivingAfter.map { [URLQueryItem(name: "arriving_after", value: $0.formatted(.iso8601))] } ?? [])
        // URLComponents leaves "+" alone, which servers read as a space.
        let encodedQuery = query.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B") ?? ""
        fetchMagicApi(endpoint: "/timetable/trip?\(encodedQuery)", type: ServerTrip.self, timeout: MAGIC_API_FALLBACK_TIMEOUT) { [weak self] result in
            guard let self, self.isCurrentSearch(generation) else { return }
            switch result {
            case let .success(serverTrip):
                handleJourneys(serverTrip.journeys)
            case .failure where append:
                self.loadingMore = false
            case .failure:
                // Our server is down or broken: the local engine when it has timetables, else the online APIs.
                if GlobalController.timetableDatabase.isReady {
                    self.fetchOfflineTrip(from: from, to: to, generation: generation)
                } else if !self.fetchOnlineTrip(source: .initial, from: from, to: to, generation: generation) {
                    self.loading = false
                    self.error = .noJourneys
                }
            }
        }
    }

    /// Start the next offline page where this page's search window ended, so no journey is
    /// skipped. A window widened for sparse service ends after its last journey. Like online
    /// paging, arrive-by pages move forward too: the next date is the lower bound of the next
    /// page's arrivals (the first page's covered up to the requested time), so its journeys
    /// list below.
    private func advanceOfflineSearchDate(after searchDate: Date, journeys: [Journey], continuing: Bool) {
        let window = TimeInterval(OfflineRoutingEngine.searchWindowSeconds)
        let widestWindow = TimeInterval(OfflineRoutingEngine.maxSearchWindowSeconds)
        switch arrivalDeparture {
        case .departure:
            let latestDeparture = journeys.compactMap { $0.parts?.first?.startDeparture }.max()
            nextOfflineSearchDate = latestDeparture.map { max(searchDate + window, $0 + 1) }
                ?? searchDate + widestWindow
        case .arrival:
            let latestArrival = journeys.compactMap { $0.parts?.last?.endArrival }.max()
            if continuing {
                nextOfflineSearchDate = latestArrival.map { max(searchDate + window, $0) } ?? searchDate + widestWindow
            } else {
                nextOfflineSearchDate = max(searchDate, latestArrival ?? searchDate)
            }
        }
    }

    /// Arrive-by offline pages are cut by arrival time, so the list follows arrival too: a later page never lands
    /// above rows already shown.
    private func sortedOfflineJourneys(_ journeys: [Journey]) -> [Journey] {
        guard arrivalDeparture == .arrival else { return sortedJourneys(journeys) }
        return journeys.sorted {
            let lhs = $0.parts?.last?.endArrival ?? .distantFuture, rhs = $1.parts?.last?.endArrival ?? .distantFuture
            return lhs != rhs ? lhs < rhs : journeyStartDate($0) > journeyStartDate($1)
        }
    }

    private func sortedJourneys(_ journeys: [Journey]) -> [Journey] {
        journeys.sorted {
            journeyStartDate($0) < journeyStartDate($1)
        }
    }

    private func journeyStartDate(_ journey: Journey) -> Date {
        journey.parts?.first?.startDeparture ?? .distantFuture
    }

    private func prepareFetchParameters(source: FetchSource, from: Stop, to: Stop) -> FetchParams? {
        let initialSearchDate = arrivalDepartureDate
        let isInitial = source == .initial

        guard let params = Self.fetchParameters(
            from: from,
            to: to,
            rApiDate: isInitial ? initialSearchDate : nextRApiSearchDate ?? initialSearchDate,
            iApiDate: isInitial ? initialSearchDate : nextIApiSearchDate ?? initialSearchDate,
            arrivalDeparture: arrivalDeparture,
            includeRApi: isInitial || source == .moreRApi,
            includeIApi: isInitial || source == .moreIApi
        ) else { return nil }

        if isInitial {
            self.nextRApiSearchDate = initialSearchDate
            self.nextIApiSearchDate = initialSearchDate
        }
        return params
    }

    /// Builds the R-API body and I-API URL for a search with the user's transfer and walk settings,
    /// resolving the actual location (-1) to the nearest station and stop. Nil when a stop has no station.
    private static func fetchParameters(
        from: Stop, to: Stop, rApiDate: Date, iApiDate: Date, arrivalDeparture: ArrivalDeparture,
        includeRApi: Bool, includeIApi: Bool
    ) -> FetchParams? {
        guard var fromId = from.stationId, var toId = to.stationId else { return nil }

        if fromId == -1 { fromId = GlobalController.getNearestStationId() }
        if toId == -1 { toId = GlobalController.getNearestStationId() }

        var fromStopId = from.id
        var toStopId = to.id
        if fromStopId == -1 { fromStopId = GlobalController.getNearestPlannableStopId() }
        if toStopId == -1 { toStopId = GlobalController.getNearestPlannableStopId() }

        let maxTransfers = UserDefaults.standard.integer(forKey: Stored.tripMaxTransfers)
        let maxWalkDuration = UserDefaults.standard.integer(forKey: Stored.tripMaxWalkDuration)

        var requestBody: TripReq? = nil
        var iApiUrl: String? = nil

        if includeRApi {
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

        if includeIApi {
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
        generation: Int, stops: [Stop]
    ) {
        let rJourneys = rResult?.journey ?? []
        let iJourneys = iResult?.journeys ?? []
        let mappedIJourneys = mapIApiToJourneys(iJourneys, stops: stops)
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

                let uniqueJourneys = self.sortedJourneys(Array(Set(newUnifiedJourneys)))

                self.lastSearchDate = Date()

                let newTrip = Trip(journey: uniqueJourneys)
                self.trip = newTrip
                self.cacheTripForCurrentSearch(newTrip)


            } else {
                let combinedJourneys = (self.trip.journey ?? []) + newUnifiedJourneys
                let uniqueJourneys = self.sortedJourneys(Array(Set(combinedJourneys)))
                self.trip.journey = uniqueJourneys
                self.cacheTripForCurrentSearch(self.trip)
            }
        }
    }

    /// Journeys from `from` to `to` leaving around `date`, soonest first, for the followed trip's other connections.
    /// Leaves the planner's own search alone. Online (R-API and I-API) unless the offline planner is on and ready;
    /// falls back to the offline timetables when the online search finds nothing and they are ready.
    /// Call on the main thread; completes on it, with no journeys when nothing was found.
    func searchJourneys(from: Stop, to: Stop, at date: Date, completion: @escaping ([Journey]) -> Void) {
        let database = GlobalController.timetableDatabase
        func soonestFirst(_ journeys: [Journey]) -> [Journey] {
            Array(Set(journeys))
                .sorted { ($0.parts?.first?.startDeparture ?? date) < ($1.parts?.first?.startDeparture ?? date) }
        }
        func searchOffline() {
            database.queryOfflineTrip(
                fromName: from.name ?? "",
                toName: to.name ?? "",
                date: date,
                arrivalDeparture: .departure,
                maxTransfers: UserDefaults.standard.integer(forKey: Stored.tripMaxTransfers),
                maxWalkDuration: UserDefaults.standard.integer(forKey: Stored.tripMaxWalkDuration)
            ) { completion(soonestFirst($0)) }
        }
        func finish(_ journeys: [Journey]) {
            if journeys.isEmpty && database.isReady { searchOffline() } else { completion(journeys) }
        }

        if UserDefaults.standard.bool(forKey: Stored.offlineTripPlanner) && database.isReady {
            searchOffline()
            return
        }
        let params = Self.fetchParameters(
            from: from, to: to, rApiDate: date, iApiDate: date, arrivalDeparture: .departure,
            includeRApi: true, includeIApi: true
        )
        let stops = GlobalController.stopsListProvider.stops

        // fetchRApiPost may wait for the session token, so start it off the main thread.
        DispatchQueue.global(qos: .userInitiated).async {
            self.performFetches(requestBody: params?.requestBody, iApiUrl: params?.iApiUrl) { rResult, iResult in
                let journeys = soonestFirst(
                    self.mapRApiToJourneys(rResult?.journey ?? [])
                        + self.mapIApiToJourneys(iResult?.journeys ?? [], stops: stops)
                )
                DispatchQueue.main.async { finish(journeys) }
            }
        }
    }

    /// Loads every stop of an R-API leg and the delay in seconds of its trip's run on the road now, whatever
    /// the leg's date (nil when none is running).
    /// Call on the main thread; completes on it with nil stops when the leg has no trip id or the fetch fails.
    func fetchStops(for part: Part, completion: @escaping (_ stops: [PartStop]?, _ delaySeconds: Int?) -> Void) {
        guard let tripId = part.tripId else {
            completion(nil, nil)
            return
        }
        let stops = GlobalController.stopsListProvider.stops
        // fetchBApi may wait for the session token, so start it off the main thread.
        DispatchQueue.global(qos: .userInitiated).async {
            fetchBApi(endpoint: "/mobile/v1/trip/\(tripId)/", type: BApiTrip.self) { result in
                guard case .success(let trip) = result else {
                    completion(nil, nil)
                    return
                }
                DispatchQueue.global(qos: .userInitiated).async {
                    let partStops = trip.partStops(for: part, stops: stops)
                    DispatchQueue.main.async {
                        completion(partStops, trip.tripDelay)
                    }
                }
            }
        }
    }

    func loadMoreTripsIfNeeded(_ journey: Journey) {
        let lastOfflineJourney = trip.journey?.last(where: { $0.id.hasPrefix("o-") || $0.id.hasPrefix("s-") })
        if journey.id == lastOfflineJourney?.id {
            #if DEBUG
            print("fetching more offline")
            #endif
            let generation = searchGenerationLock.withLock { searchGeneration }
            fetchOfflineTrip(from: from, to: to, generation: generation, append: true, onServer: journey.id.hasPrefix("s-"))
            return
        }

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
        nextOfflineSearchDate = nil
        let offlineJourneys = trip.journey?.filter { $0.id.hasPrefix("o-") || $0.id.hasPrefix("s-") } ?? []
        if !offlineJourneys.isEmpty {
            advanceOfflineSearchDate(after: arrivalDepartureDate, journeys: offlineJourneys, continuing: false)
        }
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
