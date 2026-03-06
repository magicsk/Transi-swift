//
//  TimetableDatabase.swift
//  Transi
//
//  Created by magic_sk on 26/02/2026.
//

import CommonCrypto
import Foundation
import SwiftUI

enum TimetableDownloadState {
    case idle
    case checking
    case downloading
    case decompressing
    case ready
    case error(String)
}

class TimetableDatabase: ObservableObject {
    @Published var downloadState: TimetableDownloadState = .idle
    @Published var isReady = false

    private var baseDb: SQLiteDatabase?
    private var scheduleDb: SQLiteDatabase?
    private var plannerDb: SQLiteDatabase?
    private let dbDir: URL

    var isOfflineEnabled: Bool {
        UserDefaults.standard.bool(forKey: Stored.offlineTimetables)
    }

    var isPlannerOfflineEnabled: Bool {
        UserDefaults.standard.bool(forKey: Stored.offlineTripPlanner)
    }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        dbDir = appSupport.appendingPathComponent("timetable_db")
        try? FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
    }

    // MARK: - Database Lifecycle

    @discardableResult
    func openDatabases() -> Bool {
        let basePath = dbDir.appendingPathComponent("base.db").path
        let schedulePath = dbDir.appendingPathComponent("schedule.db").path
        let plannerPath = dbDir.appendingPathComponent("planner.db").path

        guard FileManager.default.fileExists(atPath: basePath),
              FileManager.default.fileExists(atPath: schedulePath)
        else {
            return false
        }

        baseDb = SQLiteDatabase(path: basePath)
        scheduleDb = SQLiteDatabase(path: schedulePath)

        guard baseDb != nil, scheduleDb != nil else {
            closeDatabases()
            return false
        }

        // ATTACH base.db to schedule connection for cross-DB joins
        scheduleDb?.execute("ATTACH DATABASE '\(basePath)' AS base")

        if isPlannerOfflineEnabled && FileManager.default.fileExists(atPath: plannerPath) {
            plannerDb = SQLiteDatabase(path: plannerPath)
            plannerDb?.execute("ATTACH DATABASE '\(basePath)' AS base")
            plannerDb?.execute("ATTACH DATABASE '\(schedulePath)' AS schedule")
        }

        DispatchQueue.main.async {
            self.isReady = true
            self.downloadState = .ready
        }
        return true
    }

    func closeDatabases() {
        baseDb = nil
        scheduleDb = nil
        plannerDb = nil
        DispatchQueue.main.async {
            self.isReady = false
            self.downloadState = .idle
        }
    }

    // MARK: - Download & Update

    func checkAndUpdate() {
        DispatchQueue.main.async {
            self.downloadState = .checking
        }

        fetchMagicApi(endpoint: "/timetable/manifest", type: TimetableManifest.self) { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(manifest):
                DispatchQueue.global(qos: .userInitiated).async {
                    self.processManifest(manifest)
                }
            case .failure:
                DispatchQueue.main.async {
                    if self.isReady {
                        self.downloadState = .ready
                    } else {
                        self.downloadState = .error("Failed to check for updates")
                    }
                }
            }
        }
    }

    private func processManifest(_ manifest: TimetableManifest) {
        let storedBaseSha = UserDefaults.standard.string(forKey: Stored.timetableBaseDbSha) ?? ""
        let storedScheduleSha = UserDefaults.standard.string(forKey: Stored.timetableScheduleDbSha) ?? ""
        let storedPlannerSha = UserDefaults.standard.string(forKey: Stored.tripPlannerDbSha) ?? ""

        let needsBase = manifest.databases.base.sha256 != storedBaseSha
        let needsSchedule = manifest.databases.schedule.sha256 != storedScheduleSha
        let needsPlanner = isPlannerOfflineEnabled && manifest.databases.planner?.sha256 != nil && manifest.databases.planner?.sha256 != storedPlannerSha

        if !needsBase && !needsSchedule && !needsPlanner {
            if !isReady {
                _ = openDatabases()
            } else {
                DispatchQueue.main.async {
                    self.downloadState = .ready
                }
            }
            return
        }

        closeDatabases()

        DispatchQueue.main.async {
            self.downloadState = .downloading
        }

        let group = DispatchGroup()
        var success = true

        if needsBase {
            group.enter()
            downloadAndDecompress(
                urlPath: manifest.databases.base.url,
                destination: dbDir.appendingPathComponent("base.db"),
                expectedSha: manifest.databases.base.sha256,
                storedShaKey: Stored.timetableBaseDbSha
            ) { ok in
                if !ok { success = false }
                group.leave()
            }
        }

        if needsSchedule {
            group.enter()
            downloadAndDecompress(
                urlPath: manifest.databases.schedule.url,
                destination: dbDir.appendingPathComponent("schedule.db"),
                expectedSha: manifest.databases.schedule.sha256,
                storedShaKey: Stored.timetableScheduleDbSha
            ) { ok in
                if !ok { success = false }
                group.leave()
            }
        }

        if needsPlanner, let plannerInfo = manifest.databases.planner {
            group.enter()
            downloadAndDecompress(
                urlPath: plannerInfo.url,
                destination: dbDir.appendingPathComponent("planner.db"),
                expectedSha: plannerInfo.sha256,
                storedShaKey: Stored.tripPlannerDbSha
            ) { ok in
                if !ok { success = false }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            if success {
                _ = self.openDatabases()
            } else {
                self.downloadState = .error("Download failed")
            }
        }
    }

    private func downloadAndDecompress(
        urlPath: String,
        destination: URL,
        expectedSha: String,
        storedShaKey: String,
        completion: @escaping (Bool) -> Void
    ) {
        let urlString = urlPath.hasPrefix("http") ? urlPath : "\(GlobalController.magicApiBaseUrl)\(urlPath)"
        guard let url = URL(string: urlString) else {
            completion(false)
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self, let data, error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200
            else {
                #if DEBUG
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                print("Download failed: HTTP \(status) for \(url)")
                #endif
                completion(false)
                return
            }

            // Verify SHA256 of compressed data
            let hash = self.sha256(data)
            guard hash == expectedSha else {
                #if DEBUG
                print("SHA256 mismatch: expected \(expectedSha), got \(hash)")
                #endif
                completion(false)
                return
            }

            DispatchQueue.main.async {
                self.downloadState = .decompressing
            }

            // Decompress gzip to file
            guard decompressGzipToFile(from: data, to: destination) else {
                completion(false)
                return
            }

            UserDefaults.standard.set(expectedSha, forKey: storedShaKey)
            completion(true)
        }.resume()
    }

    private func sha256(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Timetable Queries

    func queryRoutes(completion: @escaping ([Route]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let scheduleDb = self?.scheduleDb else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            // Use scheduleDb (which has base attached) to deduplicate by route_short_name,
            // keeping the route_id with the most trips.
            // Regional bus routes (feed='regional', type=3) get synthetic type 700
            // so categorizeRoutes puts them in regionalbuses instead of buses.
            let rows = scheduleDb.query("""
                SELECT r.rowid, r.route_short_name, r.route_long_name,
                    CASE WHEN r.feed = 'regional' AND r.route_type = 3 THEN 700 ELSE r.route_type END as route_type,
                    r.route_color, r.route_text_color
                FROM base.routes r
                WHERE r.rowid = (
                    SELECT br.rowid
                    FROM base.routes br
                    LEFT JOIN trips t ON br.route_id = t.route_id AND br.feed = t.feed
                    WHERE br.route_short_name = r.route_short_name
                    GROUP BY br.rowid
                    ORDER BY COUNT(t.trip_id) DESC
                    LIMIT 1
                )
                ORDER BY r.route_type,
                    CASE WHEN r.route_short_name GLOB '[0-9]*' THEN CAST(r.route_short_name AS INTEGER) ELSE 999999 END,
                    r.route_short_name
            """)

            let routes = rows.compactMap { row -> Route? in
                guard let rowid = row["rowid"] as? Int,
                      let shortName = row["route_short_name"] as? String,
                      let routeType = row["route_type"] as? Int
                else { return nil }

                let longName = row["route_long_name"] as? String ?? ""
                let color = row["route_color"] as? String
                let textColor = row["route_text_color"] as? String

                return Route(routeId: rowid, shortName: shortName, longName: longName, routeType: routeType, color: color, textColor: textColor)
            }

            DispatchQueue.main.async { completion(routes) }
        }
    }

    func queryDirections(routeRowid: Int, completion: @escaping ([Direction]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let baseDb = self?.baseDb, let scheduleDb = self?.scheduleDb else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            // Look up route_short_name to find ALL matching route_ids (handles duplicates)
            let nameRows = baseDb.query("SELECT route_short_name FROM routes WHERE rowid = ?", params: [routeRowid])
            guard let shortName = nameRows.first?["route_short_name"] as? String else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            let allRouteRows = baseDb.query("SELECT route_id, feed FROM routes WHERE route_short_name = ?", params: [shortName])
            if allRouteRows.isEmpty {
                DispatchQueue.main.async { completion([]) }
                return
            }

            // Query directions across all matching route_ids
            var allDirectionRows = [[String: Any]]()
            var hasRealDirectionIds = false
            for routeRow in allRouteRows {
                guard let routeId = routeRow["route_id"] as? String,
                      let feed = routeRow["feed"] as? String
                else { continue }

                let rows = scheduleDb.query("""
                    SELECT direction_id, trip_headsign, COUNT(*) as cnt
                    FROM trips WHERE route_id = ? AND feed = ?
                    GROUP BY direction_id, trip_headsign
                    ORDER BY direction_id, cnt DESC
                """, params: [routeId, feed])
                for row in rows {
                    if row["direction_id"] is Int { hasRealDirectionIds = true }
                }
                allDirectionRows.append(contentsOf: rows)
            }

            var directions = [Direction]()

            if hasRealDirectionIds {
                // Normal case: group by direction_id, pick most common headsign
                var headsignCounts = [Int: [String: Int]]()
                for row in allDirectionRows {
                    let dirId = row["direction_id"] as? Int ?? 0
                    guard let headsign = row["trip_headsign"] as? String,
                          let cnt = row["cnt"] as? Int
                    else { continue }
                    headsignCounts[dirId, default: [:]][headsign, default: 0] += cnt
                }
                for dirId in headsignCounts.keys.sorted() {
                    if let bestHeadsign = headsignCounts[dirId]?.max(by: { $0.value < $1.value })?.key {
                        directions.append(Direction(directionId: dirId, direction: bestHeadsign))
                    }
                }
            } else {
                // All direction_ids are NULL: use unique headsigns as directions
                var headsignCounts = [String: Int]()
                for row in allDirectionRows {
                    guard let headsign = row["trip_headsign"] as? String,
                          let cnt = row["cnt"] as? Int
                    else { continue }
                    headsignCounts[headsign, default: 0] += cnt
                }
                // Sort by trip count descending, assign synthetic IDs
                let sorted = headsignCounts.sorted { $0.value > $1.value }
                for (idx, entry) in sorted.enumerated() {
                    directions.append(Direction(directionId: -(idx + 1), direction: entry.key))
                }
            }

            DispatchQueue.main.async { completion(directions) }
        }
    }

    func queryDepartures(routeRowid: Int, directionId: Int, directionName: String, date: Date, completion: @escaping ([Departure]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, let baseDb = self.baseDb, let scheduleDb = self.scheduleDb else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            let useHeadsign = directionId < 0
            let allRoutes = self.allRouteVariants(for: routeRowid, baseDb: baseDb)
            guard let routeType = allRoutes.first?.routeType else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            let dateStr = date.toString()
            let dayOfWeek = self.dayOfWeekColumn(for: date)
            var departures = [Departure]()
            var tripIndex = 0

            for route in allRoutes {
                let serviceIds = self.activeServiceIds(feed: route.feed, date: dateStr, dayOfWeek: dayOfWeek, scheduleDb: scheduleDb)
                if serviceIds.isEmpty { continue }

                let placeholders = serviceIds.map { _ in "?" }.joined(separator: ",")
                let tripRows: [[String: Any]]
                if useHeadsign {
                    var tripParams: [Any] = [route.routeId, route.feed, directionName]
                    tripParams.append(contentsOf: serviceIds.sorted())
                    tripRows = scheduleDb.query("""
                        SELECT trip_id, trip_headsign FROM trips
                        WHERE route_id = ? AND feed = ? AND trip_headsign = ? AND service_id IN (\(placeholders))
                    """, params: tripParams)
                } else {
                    var tripParams: [Any] = [route.routeId, route.feed, directionId]
                    tripParams.append(contentsOf: serviceIds.sorted())
                    tripRows = scheduleDb.query("""
                        SELECT trip_id, trip_headsign FROM trips
                        WHERE route_id = ? AND feed = ? AND COALESCE(direction_id, 0) = ? AND service_id IN (\(placeholders))
                    """, params: tripParams)
                }

                for tripRow in tripRows {
                    guard let tripId = tripRow["trip_id"] as? String,
                          let headsign = tripRow["trip_headsign"] as? String
                    else { continue }

                    let stopTimeRows = scheduleDb.query("""
                        SELECT st.departure_time, st.stop_id, bs.stop_name
                        FROM stop_times st
                        LEFT JOIN base.stops bs ON st.stop_id = bs.stop_id AND st.feed = bs.feed
                        WHERE st.trip_id = ? AND st.feed = ?
                        ORDER BY st.stop_sequence
                    """, params: [tripId, route.feed])

                    guard let firstDepTime = stopTimeRows.first?["departure_time"] as? Int else { continue }

                    var dirDepartures = [DirectionDeparture]()
                    for (stopIdx, stRow) in stopTimeRows.enumerated() {
                        guard let depTime = stRow["departure_time"] as? Int,
                              let stopName = stRow["stop_name"] as? String
                        else { continue }
                        let stopId = stRow["stop_id"] as? String
                        dirDepartures.append(DirectionDeparture(
                            stationId: stopIdx,
                            stationName: stopName,
                            departure: depTime / 60,
                            stopCode: stopId
                        ))
                    }

                    departures.append(Departure(
                        tripId: tripIndex,
                        tripFlags: 0,
                        tripHeadsign: headsign,
                        departure: firstDepTime / 60,
                        routeType: routeType,
                        externalId: tripId,
                        directionDepartures: dirDepartures
                    ))
                    tripIndex += 1
                }
            }

            departures.sort { $0.departure < $1.departure }

            DispatchQueue.main.async { completion(departures) }
        }
    }

    func queryTimetableDetail(routeRowid: Int, directionId: Int, directionName: String, date: Date, gtfsStopId: String, completion: @escaping ([TimetableDetail]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, let baseDb = self.baseDb, let scheduleDb = self.scheduleDb else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            let useHeadsign = directionId < 0
            let allRoutes = self.allRouteVariants(for: routeRowid, baseDb: baseDb)
            let dateStr = date.toString()
            let dayOfWeek = self.dayOfWeekColumn(for: date)
            var details = [TimetableDetail]()

            for route in allRoutes {
                let serviceIds = self.activeServiceIds(feed: route.feed, date: dateStr, dayOfWeek: dayOfWeek, scheduleDb: scheduleDb)
                if serviceIds.isEmpty { continue }

                let placeholders = serviceIds.map { _ in "?" }.joined(separator: ",")
                let tripRows: [[String: Any]]
                if useHeadsign {
                    var params: [Any] = [route.routeId, route.feed, directionName]
                    params.append(contentsOf: serviceIds.sorted())
                    tripRows = scheduleDb.query("""
                        SELECT trip_id FROM trips
                        WHERE route_id = ? AND feed = ? AND trip_headsign = ? AND service_id IN (\(placeholders))
                    """, params: params)
                } else {
                    var params: [Any] = [route.routeId, route.feed, directionId]
                    params.append(contentsOf: serviceIds.sorted())
                    tripRows = scheduleDb.query("""
                        SELECT trip_id FROM trips
                        WHERE route_id = ? AND feed = ? AND COALESCE(direction_id, 0) = ? AND service_id IN (\(placeholders))
                    """, params: params)
                }

                for tripRow in tripRows {
                    guard let tripId = tripRow["trip_id"] as? String else { continue }

                    let stRows = scheduleDb.query("""
                        SELECT departure_time FROM stop_times
                        WHERE trip_id = ? AND feed = ? AND stop_id = ?
                    """, params: [tripId, route.feed, gtfsStopId])

                    for stRow in stRows {
                        guard let depTime = stRow["departure_time"] as? Int else { continue }
                        details.append(TimetableDetail(t: depTime / 60, tripId: 0))
                    }
                }
            }

            details.sort { $0.t < $1.t }

            DispatchQueue.main.async { completion(details) }
        }
    }

    func deleteDatabases() {
        closeDatabases()
        try? FileManager.default.removeItem(at: dbDir.appendingPathComponent("base.db"))
        try? FileManager.default.removeItem(at: dbDir.appendingPathComponent("schedule.db"))
        UserDefaults.standard.removeObject(forKey: Stored.timetableBaseDbSha)
        UserDefaults.standard.removeObject(forKey: Stored.timetableScheduleDbSha)
    }

    // MARK: - Helpers

    private struct RouteVariant {
        let routeId: String
        let feed: String
        let routeType: Int
    }

    private func allRouteVariants(for routeRowid: Int, baseDb: SQLiteDatabase) -> [RouteVariant] {
        let nameRows = baseDb.query("SELECT route_short_name FROM routes WHERE rowid = ?", params: [routeRowid])
        guard let shortName = nameRows.first?["route_short_name"] as? String else { return [] }

        return baseDb.query("SELECT route_id, feed, route_type FROM routes WHERE route_short_name = ?", params: [shortName])
            .compactMap { row in
                guard let routeId = row["route_id"] as? String,
                      let feed = row["feed"] as? String,
                      let routeType = row["route_type"] as? Int
                else { return nil }
                return RouteVariant(routeId: routeId, feed: feed, routeType: routeType)
            }
    }

    private func activeServiceIds(feed: String, date: String, dayOfWeek: String, scheduleDb: SQLiteDatabase) -> Set<String> {
        let calendarRows = scheduleDb.query("""
            SELECT service_id FROM calendar
            WHERE feed = ? AND start_date <= ? AND end_date >= ? AND \(dayOfWeek) = 1
        """, params: [feed, date, date])
        var serviceIds = Set(calendarRows.compactMap { $0["service_id"] as? String })

        let exceptionRows = scheduleDb.query("""
            SELECT service_id, exception_type FROM calendar_dates
            WHERE feed = ? AND date = ?
        """, params: [feed, date])
        for row in exceptionRows {
            guard let sid = row["service_id"] as? String,
                  let exType = row["exception_type"] as? Int
            else { continue }
            if exType == 1 { serviceIds.insert(sid) }
            if exType == 2 { serviceIds.remove(sid) }
        }

        return serviceIds
    }

    // MARK: - Trip Planner Queries

    func queryOfflineTrip(fromName: String, toName: String, date: Date, arrivalDeparture: ArrivalDeparture, completion: @escaping ([Journey]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, let scheduleDb = self.scheduleDb, let baseDb = self.baseDb else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            // 1. Convert stop RowIDs to GTFS stop_ids/feeds
            let fromStops = self.getGtfsStops(name: fromName, baseDb: baseDb)
            let toStops = self.getGtfsStops(name: toName, baseDb: baseDb)
            
            guard !fromStops.isEmpty, !toStops.isEmpty else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            var calendar = Calendar.current
            calendar.timeZone = TimeZone(identifier: "Europe/Bratislava") ?? TimeZone.current
            let startOfDay = calendar.startOfDay(for: date)
            let initialTimeInSeconds = Int(date.timeIntervalSince(startOfDay))
            let initialTime = initialTimeInSeconds / 60 // minutes since midnight
            let dayOfWeek = self.dayOfWeekColumn(for: date)
            let dateStr = date.toString()
            
            // 2. Simple Raptor implementation
            // For brevity, we'll implement a 1st round (direct trips) and 2nd round (1 transfer)
            // In a production app, we would have a full Raptor engine with transfers and multiple rounds.
            
            var journeys = [Journey]()
            
            // Round 1: Direct trips
            for fStop in fromStops {
                let serviceIds = self.activeServiceIds(feed: fStop.feed, date: dateStr, dayOfWeek: dayOfWeek, scheduleDb: scheduleDb)
                if serviceIds.isEmpty { continue }
                
                let placeholders = serviceIds.map { _ in "?" }.joined(separator: ",")
                var params: [Any] = [fStop.id, fStop.feed, initialTime]
                params.append(contentsOf: serviceIds.sorted())
                
                // Find trips that pass through fromStop after initialTime
                let tripsAtFrom = scheduleDb.query("""
                    SELECT st.trip_id, st.departure_time, st.stop_sequence, r.route_short_name, r.route_type, t.trip_headsign
                    FROM stop_times st
                    JOIN trips t ON st.trip_id = t.trip_id AND st.feed = t.feed
                    JOIN base.routes r ON t.route_id = r.route_id AND t.feed = r.feed
                    WHERE st.stop_id = ? AND st.feed = ? AND st.departure_time >= ? * 60
                    AND t.service_id IN (\(placeholders))
                    ORDER BY st.departure_time ASC LIMIT 50
                """, params: params)
                
                for tripRow in tripsAtFrom {
                    guard let tripId = tripRow["trip_id"] as? String,
                          let fSeq = tripRow["stop_sequence"] as? Int,
                          let fDep = tripRow["departure_time"] as? Int,
                          let routeShortName = tripRow["route_short_name"] as? String,
                          let routeType = tripRow["route_type"] as? Int,
                          let headsign = tripRow["trip_headsign"] as? String
                    else { continue }
                    
                    // Check if this trip reaches any of the destination stops
                    for tStop in toStops {
                        if tStop.feed != fStop.feed { continue }
                        
                        let destRow = scheduleDb.query("""
                            SELECT departure_time as arrival_time, stop_sequence FROM stop_times
                            WHERE trip_id = ? AND feed = ? AND stop_id = ? AND stop_sequence > ?
                            LIMIT 1
                        """, params: [tripId, fStop.feed, tStop.id, fSeq])
                        
                        if let row = destRow.first,
                           let tArr = row["arrival_time"] as? Int {
                            
                            let fromDetails = self.getStopDetails(stopId: fStop.id, feed: fStop.feed, baseDb: baseDb)
                            let toDetails = self.getStopDetails(stopId: tStop.id, feed: tStop.feed, baseDb: baseDb)
                            
                            let part = Part(
                                startStopName: fromDetails.name,
                                endStopName: toDetails.name,
                                startStopCode: fromDetails.platform,
                                endStopCode: toDetails.platform,
                                startDeparture: startOfDay.addingTimeInterval(TimeInterval(fDep)),
                                endArrival: startOfDay.addingTimeInterval(TimeInterval(tArr)),
                                routeType: routeType,
                                tripHeadsign: headsign,
                                routeShortName: routeShortName
                            )
                            
                            journeys.append(Journey(id: "offline-\(tripId)", parts: [part]))
                        }
                    }
                }
            }
            
            // Round 2: One transfer
            for fStop in fromStops {
                let serviceIds = self.activeServiceIds(feed: fStop.feed, date: dateStr, dayOfWeek: dayOfWeek, scheduleDb: scheduleDb)
                if serviceIds.isEmpty { continue }
                
                let placeholders = serviceIds.map { _ in "?" }.joined(separator: ",")
                var params: [Any] = [fStop.id, fStop.feed, initialTime]
                params.append(contentsOf: serviceIds.sorted())
                
                let tripsAtFrom = scheduleDb.query("""
                    SELECT st.trip_id, st.departure_time, st.stop_sequence, r.route_short_name, r.route_type, t.trip_headsign
                    FROM stop_times st
                    JOIN trips t ON st.trip_id = t.trip_id AND st.feed = t.feed
                    JOIN base.routes r ON t.route_id = r.route_id AND t.feed = r.feed
                    WHERE st.stop_id = ? AND st.feed = ? AND st.departure_time >= ? * 60
                    AND t.service_id IN (\(placeholders))
                    ORDER BY st.departure_time ASC LIMIT 30
                """, params: params)
                
                for tripRow in tripsAtFrom {
                    guard let tripId = tripRow["trip_id"] as? String,
                          let fSeq = tripRow["stop_sequence"] as? Int,
                          let fDep = tripRow["departure_time"] as? Int,
                          let fRouteShortName = tripRow["route_short_name"] as? String,
                          let fRouteType = tripRow["route_type"] as? Int,
                          let fHeadsign = tripRow["trip_headsign"] as? String
                    else { continue }
                    
                    for tStop in toStops {
                        if tStop.feed != fStop.feed { continue }
                        
                        let transferQuery = scheduleDb.query("""
                            SELECT st1.stop_id as arr_stop_id, st2.stop_id as dep_stop_id,
                                   st1.departure_time as transfer_arr, st2.departure_time as transfer_dep,
                                   st2.trip_id as dest_trip_id, st3.departure_time as dest_arr,
                                   r2.route_short_name as dest_route_short_name, r2.route_type as dest_route_type, t2.trip_headsign as dest_headsign
                            FROM stop_times st1
                            JOIN base.stops s1 ON st1.stop_id = s1.stop_id AND st1.feed = s1.feed
                            JOIN base.stops s2 ON s1.stop_name = s2.stop_name AND s1.feed = s2.feed
                            JOIN stop_times st2 ON s2.stop_id = st2.stop_id AND st2.feed = s2.feed
                            JOIN stop_times st3 ON st2.trip_id = st3.trip_id AND st2.feed = st3.feed
                            JOIN trips t2 ON st2.trip_id = t2.trip_id AND st2.feed = t2.feed
                            JOIN base.routes r2 ON t2.route_id = r2.route_id AND t2.feed = r2.feed
                            WHERE st1.trip_id = ? AND st1.feed = ? AND st1.stop_sequence > ?
                              AND st3.stop_id = ? AND st2.stop_sequence < st3.stop_sequence
                              AND st1.departure_time <= st2.departure_time
                              AND st2.departure_time - st1.departure_time < 1800
                              AND t2.service_id IN (\(placeholders))
                            ORDER BY st3.departure_time ASC
                            LIMIT 1
                        """, params: [tripId, fStop.feed, fSeq, tStop.id] + serviceIds.sorted())
                        
                        if let transfer = transferQuery.first,
                           let transferArrStopId = transfer["arr_stop_id"] as? String,
                           let transferDepStopId = transfer["dep_stop_id"] as? String,
                           let transferArr = transfer["transfer_arr"] as? Int,
                           let transferDep = transfer["transfer_dep"] as? Int,
                           let destTripId = transfer["dest_trip_id"] as? String,
                           let destArr = transfer["dest_arr"] as? Int,
                           let destRouteShortName = transfer["dest_route_short_name"] as? String,
                           let destRouteType = transfer["dest_route_type"] as? Int,
                           let destHeadsign = transfer["dest_headsign"] as? String {
                           
                           let fromDetails = self.getStopDetails(stopId: fStop.id, feed: fStop.feed, baseDb: baseDb)
                           let transferArrDetails = self.getStopDetails(stopId: transferArrStopId, feed: fStop.feed, baseDb: baseDb)
                           let transferDepDetails = self.getStopDetails(stopId: transferDepStopId, feed: fStop.feed, baseDb: baseDb)
                           let toDetails = self.getStopDetails(stopId: tStop.id, feed: tStop.feed, baseDb: baseDb)
                           
                           let part1 = Part(
                               startStopName: fromDetails.name,
                               endStopName: transferArrDetails.name,
                               startStopCode: fromDetails.platform,
                               endStopCode: transferArrDetails.platform,
                               startDeparture: startOfDay.addingTimeInterval(TimeInterval(fDep)),
                               endArrival: startOfDay.addingTimeInterval(TimeInterval(transferArr)),
                               routeType: fRouteType,
                               tripHeadsign: fHeadsign,
                               routeShortName: fRouteShortName
                           )
                           
                           var journeyParts = [part1]
                           
                           if transferArrStopId != transferDepStopId {
                               let walkPart = Part(
                                   startStopName: transferArrDetails.name,
                                   endStopName: transferDepDetails.name,
                                   startStopCode: transferArrDetails.platform,
                                   endStopCode: transferDepDetails.platform,
                                   startDeparture: startOfDay.addingTimeInterval(TimeInterval(transferArr)),
                                   endArrival: startOfDay.addingTimeInterval(TimeInterval(transferDep)),
                                   routeType: 64, // Walk
                                   tripHeadsign: "Walk to platform",
                                   routeShortName: nil
                               )
                               journeyParts.append(walkPart)
                           }
                           
                           let part2 = Part(
                               startStopName: transferDepDetails.name,
                               endStopName: toDetails.name,
                               startStopCode: transferDepDetails.platform,
                               endStopCode: toDetails.platform,
                               startDeparture: startOfDay.addingTimeInterval(TimeInterval(transferDep)),
                               endArrival: startOfDay.addingTimeInterval(TimeInterval(destArr)),
                               routeType: destRouteType,
                               tripHeadsign: destHeadsign,
                               routeShortName: destRouteShortName
                           )
                           
                           journeyParts.append(part2)
                           journeys.append(Journey(id: "offline-transfer-\(tripId)-\(destTripId)", parts: journeyParts))
                        }
                    }
                }
            }
            var uniqueJourneys = Array(Set(journeys))
            uniqueJourneys.sort { ($0.parts?.first?.startDeparture ?? Date()) < ($1.parts?.first?.startDeparture ?? Date()) }
            
            DispatchQueue.main.async {
                completion(uniqueJourneys.prefix(10).map { $0 })
            }
        }
    }

    private struct GtfsStop {
        let id: String
        let feed: String
    }

    private func getGtfsStops(name: String, baseDb: SQLiteDatabase) -> [GtfsStop] {
        let rows = baseDb.query("SELECT stop_id, feed FROM stops WHERE stop_name = ?", params: [name])
        return rows.compactMap { row in
            guard let id = row["stop_id"] as? String, let feed = row["feed"] as? String else { return nil }
            return GtfsStop(id: id, feed: feed)
        }
    }
    
    private func getStopDetails(stopId: String, feed: String, baseDb: SQLiteDatabase) -> (name: String, platform: String?) {
        let row = baseDb.query("SELECT stop_name, platform_code FROM stops WHERE stop_id = ? AND feed = ?", params: [stopId, feed])
        let name = row.first?["stop_name"] as? String ?? stopId
        let platform = row.first?["platform_code"] as? String
        return (name, platform)
    }

    private func dayOfWeekColumn(for date: Date) -> String {
        let weekday = Calendar(identifier: .gregorian).component(.weekday, from: date)
        switch weekday {
        case 1: return "sunday"
        case 2: return "monday"
        case 3: return "tuesday"
        case 4: return "wednesday"
        case 5: return "thursday"
        case 6: return "friday"
        case 7: return "saturday"
        default: return "monday"
        }
    }
}
