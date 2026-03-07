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

    func checkAndUpdate() { print("--- checkAndUpdate CALLED ---")
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

    func activeServiceIds(feed: String, date: String, dayOfWeek: String, scheduleDb: SQLiteDatabase) -> Set<String> {
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

    func queryOfflineTrip(fromName: String, toName: String, date: Date, arrivalDeparture: ArrivalDeparture, maxTransfers: Int = 1, maxWalkDuration: Int = 15, completion: @escaping ([Journey]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let scheduleDb = self.scheduleDb, let baseDb = self.baseDb else {
                DispatchQueue.main.async { completion([]) }
                return
            }
            
            let dateStr = date.toString()
            let dayOfWeek = self.dayOfWeekColumn(for: date)
            var serviceIds = Set<String>()
            for feed in ["city", "regional", "trains"] {
                serviceIds.formUnion(self.activeServiceIds(feed: feed, date: dateStr, dayOfWeek: dayOfWeek, scheduleDb: scheduleDb))
            }
            
            print("EXECUTING NEW BFS ENGINE"); let engine = OfflineRoutingEngine(scheduleDb: scheduleDb, baseDb: baseDb, timetableDb: self)
            let journeys = engine.planTrip(fromName: fromName, toName: toName, date: date, maxTransfers: maxTransfers, maxWalkDuration: maxWalkDuration)
            
            DispatchQueue.main.async {
                completion(journeys)
            }
        }

    }

    private struct GtfsStop {
        let id: String
        let feed: String
    }

    private func getZonesForTrip(tripId: String, feed: String, startSeq: Int, endSeq: Int, scheduleDb: SQLiteDatabase) -> [String] {
        let rows = scheduleDb.query("""
            SELECT DISTINCT s.zone_id 
            FROM stop_times st
            JOIN base.stops s ON st.stop_id = s.stop_id AND st.feed = s.feed
            WHERE st.trip_id = ? AND st.feed = ? 
              AND st.stop_sequence >= ? AND st.stop_sequence <= ?
              AND s.zone_id IS NOT NULL AND s.zone_id != ''
        """, params: [tripId, feed, startSeq, endSeq])
        
        return rows.compactMap { $0["zone_id"] as? String }
    }

    private func distanceBetween(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6371e3
        let phi1 = lat1 * Double.pi / 180
        let phi2 = lat2 * Double.pi / 180
        let deltaPhi = (lat2 - lat1) * Double.pi / 180
        let deltaLambda = (lon2 - lon1) * Double.pi / 180
        let a = sin(deltaPhi / 2) * sin(deltaPhi / 2) + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2)
        return r * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
    
    private func getGtfsStops(name: String, baseDb: SQLiteDatabase) -> [GtfsStop] {
        var searchName = name
        if name == "Autobusová stanica" {
            searchName = "Bratislava, AS"
        }
        
        var rows = baseDb.query("SELECT stop_id, feed FROM stops WHERE stop_name = ?", params: [searchName])
        
        if rows.isEmpty {
            let parts = name.split(separator: ",")
            if parts.count > 1 {
                let cleanName = parts[1].trimmingCharacters(in: .whitespaces)
                rows = baseDb.query("SELECT stop_id, feed FROM stops WHERE stop_name LIKE ?", params: ["%" + cleanName + "%"])
            } else {
                rows = baseDb.query("SELECT stop_id, feed FROM stops WHERE stop_name LIKE ?", params: ["%" + name + "%"])
            }
        }
        
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

    func dayOfWeekColumn(for date: Date) -> String {
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

class OfflineRoutingEngine {
    let scheduleDb: SQLiteDatabase
    let baseDb: SQLiteDatabase
    let timetableDb: TimetableDatabase
    
    init(scheduleDb: SQLiteDatabase, baseDb: SQLiteDatabase, timetableDb: TimetableDatabase) {
        self.scheduleDb = scheduleDb
        self.baseDb = baseDb
        self.timetableDb = timetableDb
    }

    struct StopInfo: Hashable {
        let id: String
        let name: String
        let normalizedName: String
        let lat: Double
        let lon: Double
        let platform: String?
        let feed: String
    }
    
    struct MemStopTime {
        let stopId: String
        let arrival: Int
        let departure: Int
        let seq: Int
    }

    struct MemTrip {
        let id: String
        let feed: String
        let routeShortName: String
        let routeType: Int
        let headsign: String
        var stopTimes: [MemStopTime]
    }
    
    private func distanceBetween(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6371e3
        let phi1 = lat1 * Double.pi / 180
        let phi2 = lat2 * Double.pi / 180
        let deltaPhi = (lat2 - lat1) * Double.pi / 180
        let deltaLambda = (lon2 - lon1) * Double.pi / 180
        let a = sin(deltaPhi / 2) * sin(deltaPhi / 2) + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2)
        return r * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    private func normalizeStopName(_ name: String) -> String {
        return name.replacingOccurrences(of: "Bratislava, ", with: "")
                   .replacingOccurrences(of: "Rovinka, ", with: "")
                   .replacingOccurrences(of: "Dunajská Lužná, ", with: "")
                   .replacingOccurrences(of: "Miloslavov, ", with: "")
    }

    private func getStops(name: String) -> [StopInfo] {
        var searchName = name
        if name == "Autobusová stanica" { searchName = "Bratislava, AS" }
        
        var rows = baseDb.query("SELECT stop_id, stop_name, stop_lat, stop_lon, platform_code, feed FROM stops WHERE stop_name = ?", params: [searchName])
        
        if rows.isEmpty {
            let parts = name.split(separator: ",")
            if parts.count > 1 {
                let cleanName = parts[1].trimmingCharacters(in: .whitespaces)
                rows = baseDb.query("SELECT stop_id, stop_name, stop_lat, stop_lon, platform_code, feed FROM stops WHERE stop_name LIKE ?", params: ["%" + cleanName + "%"])
            } else {
                rows = baseDb.query("SELECT stop_id, stop_name, stop_lat, stop_lon, platform_code, feed FROM stops WHERE stop_name LIKE ?", params: ["%" + name + "%"])
            }
        }
        
        return rows.compactMap { row in
            guard let id = row["stop_id"] as? String,
                  let sname = row["stop_name"] as? String,
                  let lat = row["stop_lat"] as? Double,
                  let lon = row["stop_lon"] as? Double,
                  let feed = row["feed"] as? String else { return nil }
            return StopInfo(id: id, name: sname, normalizedName: normalizeStopName(sname), lat: lat, lon: lon, platform: row["platform_code"] as? String, feed: feed)
        }
    }

    struct GraphState {
        let stopId: String
        let time: Int
        let parts: [Part]
        let zones: Set<String>
        let transitLegs: Int
        let lastTripId: String?
    }

    func planTrip(fromName: String, toName: String, date: Date, maxTransfers: Int, maxWalkDuration: Int) -> [Journey] {
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let logFile = docDir.appendingPathComponent("routing_log.txt")
        
        let fromStops = getStops(name: fromName)
        let toStops = getStops(name: toName)
        
        let calendar = Calendar.current
        let startOfSearchDay = calendar.startOfDay(for: date)
        let initialTimeInSeconds = Int(date.timeIntervalSince(startOfSearchDay))
        
        var logStr = "--- PLAN TRIP START ---\n"
        logStr += "From: \(fromName), To: \(toName)\n"
        logStr += "Initial Time: \(initialTimeInSeconds)\n"
        
        if fromStops.isEmpty || toStops.isEmpty { 
            logStr += "Missing stops!\n"
            try? logStr.write(to: logFile, atomically: true, encoding: .utf8)
            return [] 
        }
        
        var journeys = [Journey]()
        let toStopIds = Set(toStops.map { $0.id })
        
        let allStopsRows = baseDb.query("SELECT stop_id, stop_name, stop_lat, stop_lon, platform_code, feed, zone_id FROM stops")
        var allStops = [String: StopInfo]()
        var stopsByName = [String: [StopInfo]]()
        var zonesByStop = [String: String]()
        for row in allStopsRows {
            guard let id = row["stop_id"] as? String, let sname = row["stop_name"] as? String, let lat = row["stop_lat"] as? Double, let lon = row["stop_lon"] as? Double, let feed = row["feed"] as? String else { continue }
            let info = StopInfo(id: id, name: sname, normalizedName: normalizeStopName(sname), lat: lat, lon: lon, platform: row["platform_code"] as? String, feed: feed)
            allStops[id] = info
            stopsByName[info.normalizedName, default: []].append(info)
            if let z = row["zone_id"] as? String, !z.isEmpty { zonesByStop[id] = z }
        }

        var foundJourneys = [Journey]()
        var currentDayOffset = 0
        while foundJourneys.count < 5 && currentDayOffset < 2 {
            let evalDay = startOfSearchDay.addingTimeInterval(TimeInterval(currentDayOffset * 86400))
            let dateStr = evalDay.toString()
            let dayOfWeek = timetableDb.dayOfWeekColumn(for: evalDay)
            
            var sids = Set<String>()
            for feed in ["city", "regional", "trains"] {
                sids.formUnion(timetableDb.activeServiceIds(feed: feed, date: dateStr, dayOfWeek: dayOfWeek, scheduleDb: scheduleDb))
            }
            
            logStr += "Day \(currentDayOffset), Service IDs: \(sids.count)\n"
            if sids.isEmpty { currentDayOffset += 1; continue }
            
            let placeholders = sids.map { _ in "?" }.joined(separator: ",")
            var params: [Any] = []
            params.append(contentsOf: Array(sids))
            
            let q = """
                SELECT st.trip_id, st.stop_id, st.departure_time, st.departure_time as arrival_time, st.stop_sequence, 
                       r.route_short_name, r.route_type, t.trip_headsign, st.feed
                FROM stop_times st
                JOIN trips t ON st.trip_id = t.trip_id AND st.feed = t.feed
                JOIN base.routes r ON t.route_id = r.route_id AND t.feed = r.feed
                WHERE t.service_id IN (\(placeholders))
"""
            let rows = scheduleDb.query(q, params: params)
            var tripsDict = [String: MemTrip]()
            for row in rows {
                guard let tId = row["trip_id"] as? String, let sId = row["stop_id"] as? String, let dep = row["departure_time"] as? Int, let arr = row["arrival_time"] as? Int, let seq = row["stop_sequence"] as? Int, let rS = row["route_short_name"] as? String, let rT = row["route_type"] as? Int, let h = row["trip_headsign"] as? String, let f = row["feed"] as? String else { continue }
                let adjustedDep = dep + (currentDayOffset * 86400)
                let adjustedArr = arr + (currentDayOffset * 86400)
                let st = MemStopTime(stopId: sId, arrival: adjustedArr, departure: adjustedDep, seq: seq)
                if tripsDict[tId] != nil { tripsDict[tId]!.stopTimes.append(st) }
                else { tripsDict[tId] = MemTrip(id: tId, feed: f, routeShortName: rS, routeType: rT, headsign: h, stopTimes: [st]) }
            }
            
            var tripsByStop = [String: [(tripId: String, seq: Int, dep: Int, stopId: String)]]()
            for (tId, trip) in tripsDict {
                for st in trip.stopTimes {
                    tripsByStop[st.stopId, default: []].append((tripId: tId, seq: st.seq, dep: st.departure, stopId: st.stopId))
                }
            }
            
            let dayStartTime = (currentDayOffset == 0) ? initialTimeInSeconds : (currentDayOffset * 86400)
            
            var startTripsAtOrigin = [(tripId: String, seq: Int, dep: Int, stopId: String)]()
            for fs in fromStops {
                startTripsAtOrigin.append(contentsOf: tripsByStop[fs.id] ?? [])
            }
            startTripsAtOrigin = startTripsAtOrigin.filter { $0.dep >= dayStartTime }.sorted { $0.dep < $1.dep }
            
            logStr += "Found \(startTripsAtOrigin.count) starting trips at origin.\n"
            
            let startTripCandidates = startTripsAtOrigin.prefix(20)
            
            for startCandidate in startTripCandidates {
                var bestArrLocal = [String: Int]()
                var journeysForThisStart = [Journey]()
                var activeStates = [GraphState(stopId: startCandidate.stopId, time: startCandidate.dep, parts: [], zones: [], transitLegs: 0, lastTripId: nil)]
                
                let maxLegs = 6
                for leg in 1...maxLegs {
                    if activeStates.isEmpty { break }
                    var nextStates = [GraphState]()
                    for state in activeStates {
                        guard let currStopData = allStops[state.stopId] else { continue }
                        var origins = [(id: String, time: Int, part: Part?)]()
                        origins.append((id: state.stopId, time: state.time, part: nil))
                        if !state.parts.isEmpty {
                            for target in stopsByName[currStopData.normalizedName] ?? [] {
                                if target.id == state.stopId { continue }
                                let walkPart = Part(startStopName: currStopData.name, endStopName: target.name, startStopCode: currStopData.platform, endStopCode: target.platform, startDeparture: startOfSearchDay.addingTimeInterval(TimeInterval(state.time)), endArrival: startOfSearchDay.addingTimeInterval(TimeInterval(state.time + 60)), routeType: 64, tripHeadsign: "Walk to platform", routeShortName: nil)
                                origins.append((id: target.id, time: state.time + 60, part: walkPart))
                            }
                        }
                        
                        for origin in origins {
                            let passingTrips = tripsByStop[origin.id] ?? []
                            for pt in passingTrips {
                                if pt.tripId == state.lastTripId { continue }
                                if pt.dep < origin.time || pt.dep > origin.time + 14400 { continue }
                                guard let trip = tripsDict[pt.tripId] else { continue }
                                for st in trip.stopTimes where st.seq > pt.seq {
                                    if st.arrival < (bestArrLocal[st.stopId] ?? 2000000) {
                                        bestArrLocal[st.stopId] = st.arrival
                                        var nParts = state.parts
                                        if let wp = origin.part { nParts.append(wp) }
                                        let p = Part(startStopName: allStops[origin.id]?.name ?? origin.id, endStopName: allStops[st.stopId]?.name ?? st.stopId, startStopCode: allStops[origin.id]?.platform, endStopCode: allStops[st.stopId]?.platform, startDeparture: startOfSearchDay.addingTimeInterval(TimeInterval(pt.dep)), endArrival: startOfSearchDay.addingTimeInterval(TimeInterval(st.arrival)), routeType: trip.routeType, tripHeadsign: trip.headsign, routeShortName: trip.routeShortName)
                                        nParts.append(p)
                                        var nZones = state.zones
                                        for tst in trip.stopTimes where tst.seq >= pt.seq && tst.seq <= st.seq {
                                            if let z = zonesByStop[tst.stopId] { nZones.insert(z) }
                                        }
                                        if toStopIds.contains(st.stopId) {
                                            journeysForThisStart.append(Journey(id: UUID().uuidString, parts: nParts, zones: Array(nZones).sorted()))
                                        } else if leg < maxLegs {
                                            nextStates.append(GraphState(stopId: st.stopId, time: st.arrival, parts: nParts, zones: nZones, transitLegs: leg, lastTripId: pt.tripId))
                                        }
                                    }
                                }
                            }
                        }
                    }
                    activeStates = nextStates
                    if !journeysForThisStart.isEmpty { break }
                }
                if let best = journeysForThisStart.sorted(by: { ($0.parts?.last?.endArrival ?? Date()) < ($1.parts?.last?.endArrival ?? Date()) }).first {
                    journeys.append(best)
                }
                if journeys.count >= 5 { break }
            }
            currentDayOffset += 1
        }
        
        journeys.sort { ($0.parts?.first?.startDeparture ?? Date()) < ($1.parts?.first?.startDeparture ?? Date()) }
        logStr += "Found \(journeys.count) final journeys.\n"
        try? logStr.write(to: logFile, atomically: true, encoding: .utf8)
        return Array(unique(journeys).prefix(10))
    }
    
    private func unique(_ journeys: [Journey]) -> [Journey] {
        var result = [Journey]()
        for j in journeys {
            if !result.contains(where: { $0 == j }) { result.append(j) }
        }
        return result
    }
}