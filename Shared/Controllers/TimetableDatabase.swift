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
    private let dbDir: URL

    var isOfflineEnabled: Bool {
        UserDefaults.standard.bool(forKey: Stored.offlineTimetables)
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

        DispatchQueue.main.async {
            self.isReady = true
            self.downloadState = .ready
        }
        return true
    }

    func closeDatabases() {
        baseDb = nil
        scheduleDb = nil
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

        let needsBase = manifest.databases.base.sha256 != storedBaseSha
        let needsSchedule = manifest.databases.schedule.sha256 != storedScheduleSha

        if !needsBase && !needsSchedule {
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
