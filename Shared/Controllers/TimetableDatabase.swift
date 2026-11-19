import CommonCrypto
import Foundation
import SwiftUI
#if os(iOS) && canImport(BackgroundTasks)
import BackgroundTasks
#endif

enum TimetableDownloadState {
    case idle
    case checking
    case downloading
    case decompressing
    case ready
    case error(String)
}

struct TimetableDatabaseStatus {
    let sizeBytes: Int64
    let updatedAt: Date
}

class TimetableDatabase: ObservableObject {
    @Published var downloadState: TimetableDownloadState = .idle
    @Published var downloadProgress: Double?
    @Published var downloadDetail: String?
    @Published var isReady = false
    /// Schedule sha256 of the newest published database seen this session; nil until a manifest arrives.
    /// Read and written on the main thread.
    private(set) var latestScheduleSha: String?

    private var baseDb: SQLiteDatabase?
    private var scheduleDb: SQLiteDatabase?
    private let dbDir: URL
    private let updateLock = NSLock()
    private var updateInFlight = false
    private var updateCompletions = [(Bool) -> Void]()
    private let downloadProgressLock = NSLock()
    private var downloadFractions = [String: Double]()
    private var progressObservations = [NSKeyValueObservation]()
    private var activeDownloadTasks = [URLSessionDataTask]()

    #if os(iOS) && canImport(BackgroundTasks)
    private var continuedProcessingTask: AnyObject?
    private var registeredContinuedProcessingIdentifiers = Set<String>()
    #endif

    /// Manifest-check throttle: skip refetch if last successful check was within this window.
    /// Server already sets `Cache-Control: max-age=300` on /timetable/manifest.
    private static let manifestCheckTTL: TimeInterval = 300

    var isOfflineEnabled: Bool {
        UserDefaults.standard.bool(forKey: Stored.offlineTimetables)
    }

    var isPlannerOfflineEnabled: Bool {
        UserDefaults.standard.bool(forKey: Stored.offlineTripPlanner)
    }

    var shouldMaintainOfflineDatabase: Bool {
        isOfflineEnabled || isPlannerOfflineEnabled
    }

    /// Whether the local database is the newest one known: it matches the latest manifest, or none was fetched.
    var isLatest: Bool {
        latestScheduleSha.map { $0 == UserDefaults.standard.string(forKey: Stored.timetableScheduleDbSha) } ?? true
    }

    private var allowsCellularDatabaseUpdates: Bool {
        UserDefaults.standard.bool(forKey: Stored.timetableAllowCellularUpdates)
    }

    private var databaseSessionConfiguration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.default
        configuration.allowsCellularAccess = allowsCellularDatabaseUpdates
        return configuration
    }

    private var databaseNetworkFailureMessage: String {
        allowsCellularDatabaseUpdates
            ? "Failed to update timetable database"
            : "Connect to Wi-Fi or allow cellular database updates"
    }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        dbDir = appSupport.appendingPathComponent("timetable_db")
        try? FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)

        if shouldMaintainOfflineDatabase {
            _ = openDatabases()
            checkAndUpdate()
        }
    }

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

        scheduleDb?.execute("ATTACH DATABASE '\(basePath)' AS base")
        guard hasUsableTimetableData() else {
            closeDatabases()
            return false
        }

        DispatchQueue.main.async {
            self.isReady = true
            self.downloadState = .ready
        }
        return true
    }

    func closeDatabases() {
        cancelActiveDownloads()
        baseDb = nil
        scheduleDb = nil
        DispatchQueue.main.async {
            self.isReady = false
            self.downloadState = .idle
            self.downloadProgress = nil
            self.downloadDetail = nil
        }
    }

    func checkAndUpdate(
        force: Bool = false,
        allowBackgroundContinuation: Bool = true,
        completion: ((Bool) -> Void)? = nil
    ) {
        guard shouldMaintainOfflineDatabase else {
            completion?(false)
            return
        }
        guard beginUpdate(completion: completion) else { return }

        if allowBackgroundContinuation {
            submitContinuedProcessingTaskIfAvailable()
        }

        // Throttle: skip if we successfully fetched the manifest within the TTL window.
        if !force && isReady {
            let lastCheck = UserDefaults.standard.double(forKey: Stored.timetableLastCheckTimestamp)
            if lastCheck > 0 && Date().timeIntervalSince1970 - lastCheck < Self.manifestCheckTTL {
                finishUpdate(success: true)
                return
            }
        }

        DispatchQueue.main.async {
            self.downloadState = .checking
        }

        fetchManifest { [weak self] result in
            guard let self else { return }
            switch result {
            case let .success(manifest):
                self.latestScheduleSha = manifest.databases.schedule.sha256
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Stored.timetableLastCheckTimestamp)
                DispatchQueue.global(qos: .userInitiated).async {
                    self.processManifest(manifest)
                }
            case .failure:
                DispatchQueue.main.async {
                    if self.isReady {
                        self.downloadState = .ready
                    } else {
                        self.downloadState = .error(self.databaseNetworkFailureMessage)
                    }
                }
                self.finishUpdate(success: self.isReady)
            }
        }
    }

    private func processManifest(_ manifest: TimetableManifest) {
        let storedBaseSha = UserDefaults.standard.string(forKey: Stored.timetableBaseDbSha) ?? ""
        let storedScheduleSha = UserDefaults.standard.string(forKey: Stored.timetableScheduleDbSha) ?? ""

        var needsBase = manifest.databases.base.sha256 != storedBaseSha
        var needsSchedule = manifest.databases.schedule.sha256 != storedScheduleSha

        if !needsBase && !needsSchedule {
            if isReady {
                DispatchQueue.main.async {
                    self.downloadState = .ready
                }
                finishUpdate(success: true)
                return
            }
            if openDatabases() {
                finishUpdate(success: true)
                return
            }
            // Stored SHAs claim we are up to date but the local databases are
            // missing or unusable — re-download both.
            UserDefaults.standard.removeObject(forKey: Stored.timetableBaseDbSha)
            UserDefaults.standard.removeObject(forKey: Stored.timetableScheduleDbSha)
            needsBase = true
            needsSchedule = true
        }

        DispatchQueue.main.async {
            self.downloadState = .downloading
        }

        let group = DispatchGroup()
        let successLock = NSLock()
        var success = true
        beginDownloadProgress(files: [
            needsBase ? "base.db" : nil,
            needsSchedule ? "schedule.db" : nil,
        ].compactMap { $0 })

        if needsBase {
            group.enter()
            downloadAndDecompress(
                urlPath: manifest.databases.base.url,
                destination: dbDir.appendingPathComponent("base.db"),
                expectedSha: manifest.databases.base.sha256,
                storedShaKey: Stored.timetableBaseDbSha
            ) { ok in
                if !ok {
                    successLock.lock()
                    success = false
                    successLock.unlock()
                }
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
                if !ok {
                    successLock.lock()
                    success = false
                    successLock.unlock()
                }
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            guard let self else { return }
            if success {
                self.closeDatabases()
                if !self.openDatabases() {
                    UserDefaults.standard.removeObject(forKey: Stored.timetableBaseDbSha)
                    UserDefaults.standard.removeObject(forKey: Stored.timetableScheduleDbSha)
                    self.downloadState = .error("Downloaded timetable database is empty or invalid")
                    self.finishUpdate(success: false)
                } else {
                    self.finishUpdate(success: true)
                }
            } else {
                self.downloadState = .error(self.databaseNetworkFailureMessage)
                self.finishUpdate(success: false)
            }
        }
    }

    private func fetchManifest(completion: @escaping (Result<TimetableManifest, Error>) -> Void) {
        guard let url = URL(string: "\(GlobalController.magicApiBaseUrl)/timetable/manifest") else {
            completion(.failure(NSError(domain: "TimetableDatabase", code: -1)))
            return
        }

        let session = URLSession(configuration: databaseSessionConfiguration)
        session.dataTask(with: url) { data, _, error in
            defer { session.finishTasksAndInvalidate() }
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            guard let data else {
                DispatchQueue.main.async {
                    completion(.failure(NSError(domain: "TimetableDatabase", code: -2)))
                }
                return
            }
            do {
                let decoder = JSONDecoder()
                decoder.keyDecodingStrategy = .convertFromSnakeCase
                let manifest = try decoder.decode(TimetableManifest.self, from: data)
                DispatchQueue.main.async { completion(.success(manifest)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }.resume()
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

        let fileName = destination.lastPathComponent
        let session = URLSession(configuration: databaseSessionConfiguration)
        let task = session.dataTask(with: url) { [weak self] data, response, error in
            defer { session.finishTasksAndInvalidate() }
            guard let self else {
                completion(false)
                return
            }
            guard let data, error == nil,
                  let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200
            else {
                completion(false)
                return
            }

            let hash = self.sha256(data)
            guard hash == expectedSha else {
                completion(false)
                return
            }
            self.setDownloadFraction(fileName, fraction: 1, detail: "\(fileName) downloaded")

            DispatchQueue.main.async {
                self.downloadState = .decompressing
                self.downloadDetail = "Installing \(fileName)"
                self.updateContinuedProcessingProgress()
            }

            let tempURL = destination.appendingPathExtension("tmp")
            do {
                try decompressGzipToFile(from: data, to: tempURL)
                if FileManager.default.fileExists(atPath: destination.path) {
                    try FileManager.default.removeItem(at: destination)
                }
                try FileManager.default.moveItem(at: tempURL, to: destination)
                UserDefaults.standard.set(expectedSha, forKey: storedShaKey)
                completion(true)
            } catch {
                try? FileManager.default.removeItem(at: tempURL)
                completion(false)
            }
        }
        trackDownloadTask(task, fileName: fileName)
        task.resume()
    }

    private func beginUpdate(completion: ((Bool) -> Void)?) -> Bool {
        updateLock.lock()
        defer { updateLock.unlock() }
        if let completion {
            updateCompletions.append(completion)
        }
        if updateInFlight {
            return false
        }
        updateInFlight = true
        return true
    }

    private func finishUpdate(success: Bool) {
        downloadProgressLock.lock()
        let observations = progressObservations
        progressObservations.removeAll()
        activeDownloadTasks.removeAll()
        downloadFractions.removeAll()
        downloadProgressLock.unlock()
        observations.forEach { $0.invalidate() }

        updateLock.lock()
        updateInFlight = false
        let completions = updateCompletions
        updateCompletions.removeAll()
        updateLock.unlock()

        DispatchQueue.main.async {
            self.downloadProgress = nil
            self.downloadDetail = nil
            self.completeContinuedProcessingTask(success: success)
        }
        completions.forEach { $0(success) }
    }

    private func beginDownloadProgress(files: [String]) {
        downloadProgressLock.lock()
        downloadFractions = Dictionary(uniqueKeysWithValues: files.map { ($0, 0.0) })
        downloadProgressLock.unlock()
        DispatchQueue.main.async {
            self.downloadProgress = files.isEmpty ? nil : 0
            self.downloadDetail = files.isEmpty ? nil : "Starting download"
            self.updateContinuedProcessingProgress()
        }
    }

    private func trackDownloadTask(_ task: URLSessionDataTask, fileName: String) {
        let observation = task.progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak self] progress, _ in
            self?.setDownloadFraction(fileName, fraction: progress.fractionCompleted, detail: "Downloading \(fileName)")
        }
        downloadProgressLock.lock()
        activeDownloadTasks.append(task)
        progressObservations.append(observation)
        downloadProgressLock.unlock()
    }

    private func setDownloadFraction(_ fileName: String, fraction: Double, detail: String) {
        downloadProgressLock.lock()
        if downloadFractions[fileName] != nil {
            downloadFractions[fileName] = max(0, min(1, fraction))
        }
        let values = Array(downloadFractions.values)
        downloadProgressLock.unlock()

        let progress = values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
        DispatchQueue.main.async {
            self.downloadProgress = progress
            self.downloadDetail = detail
            self.updateContinuedProcessingProgress()
        }
    }

    private func cancelActiveDownloads() {
        downloadProgressLock.lock()
        let tasks = activeDownloadTasks
        activeDownloadTasks.removeAll()
        downloadProgressLock.unlock()
        tasks.forEach { $0.cancel() }
    }

    private func submitContinuedProcessingTaskIfAvailable() {
        #if os(iOS) && canImport(BackgroundTasks)
        if #available(iOS 26.0, *) {
            submitContinuedProcessingTask()
        }
        #endif
    }

    private func updateContinuedProcessingProgress() {
        #if os(iOS) && canImport(BackgroundTasks)
        if #available(iOS 26.0, *),
           let task = continuedProcessingTask as? BGContinuedProcessingTask {
            let fraction = downloadProgress ?? 0
            task.progress.totalUnitCount = 100
            task.progress.completedUnitCount = Int64(max(0, min(1, fraction)) * 100)
            task.updateTitle(
                "Updating Timetables",
                subtitle: downloadDetail ?? "Preparing offline database"
            )
        }
        #endif
    }

    private func completeContinuedProcessingTask(success: Bool) {
        #if os(iOS) && canImport(BackgroundTasks)
        if #available(iOS 26.0, *),
           let task = continuedProcessingTask as? BGContinuedProcessingTask {
            task.progress.completedUnitCount = success ? task.progress.totalUnitCount : task.progress.completedUnitCount
            task.setTaskCompleted(success: success)
            continuedProcessingTask = nil
        }
        #endif
    }

    #if os(iOS) && canImport(BackgroundTasks)
    @available(iOS 26.0, *)
    private func submitContinuedProcessingTask() {
        let bundleId = Bundle.main.bundleIdentifier ?? "eu.magicsk.Transi"
        let identifier = "\(bundleId).timetable.continued.\(UUID().uuidString)"
        guard registerContinuedProcessingHandler(identifier: identifier) else { return }

        let request = BGContinuedProcessingTaskRequest(
            identifier: identifier,
            title: "Updating Timetables",
            subtitle: "Preparing offline database"
        )
        request.strategy = .queue
        request.requiredResources = []

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            #if DEBUG
            print("Failed to submit timetable background task: \(error)")
            #endif
        }
    }

    @available(iOS 26.0, *)
    private func registerContinuedProcessingHandler(identifier: String) -> Bool {
        if registeredContinuedProcessingIdentifiers.contains(identifier) {
            return true
        }

        let didRegister = BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { [weak self] task in
            self?.handleContinuedProcessingTask(task)
        }
        if didRegister {
            registeredContinuedProcessingIdentifiers.insert(identifier)
        }
        return didRegister
    }

    @available(iOS 26.0, *)
    private func handleContinuedProcessingTask(_ task: BGTask) {
        guard let task = task as? BGContinuedProcessingTask else {
            task.setTaskCompleted(success: false)
            return
        }

        continuedProcessingTask = task
        DispatchQueue.main.async {
            self.updateContinuedProcessingProgress()
        }

        task.expirationHandler = { [weak self, weak task] in
            self?.cancelActiveDownloads()
            task?.setTaskCompleted(success: false)
            self?.continuedProcessingTask = nil
        }

        checkAndUpdate(force: true, allowBackgroundContinuation: false)
    }
    #endif

    private func sha256(_ data: Data) -> String {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
                    data.withUnsafeBytes { buffer in _ = CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash) }
        return hash.map { String(format: "%02x", $0) }.joined()
    }
    func queryRoutes(completion: @escaping ([Route]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let scheduleDb = self?.scheduleDb else {
                DispatchQueue.main.async { completion([]) }
                return
            }

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

                return Route(routeId: rowid, shortName: shortName, longName: longName, routeType: routeType, color: color, textColor: textColor, source: .offline)
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
                var headsignCounts = [String: Int]()
                for row in allDirectionRows {
                    guard let headsign = row["trip_headsign"] as? String,
                          let cnt = row["cnt"] as? Int
                    else { continue }
                    headsignCounts[headsign, default: 0] += cnt
                }
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

    var databaseStatus: TimetableDatabaseStatus? {
        var sizeBytes: Int64 = 0
        var updatedAt: Date?
        for fileName in ["base.db", "schedule.db"] {
            let path = dbDir.appendingPathComponent(fileName).path
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: path) else {
                return nil
            }
            sizeBytes += (attributes[.size] as? NSNumber)?.int64Value ?? 0
            if let modified = attributes[.modificationDate] as? Date {
                updatedAt = max(updatedAt ?? modified, modified)
            }
        }
        guard let updatedAt else { return nil }
        return TimetableDatabaseStatus(sizeBytes: sizeBytes, updatedAt: updatedAt)
    }

    func deleteDatabases() {
        closeDatabases()
        try? FileManager.default.removeItem(at: dbDir.appendingPathComponent("base.db"))
        try? FileManager.default.removeItem(at: dbDir.appendingPathComponent("schedule.db"))
        UserDefaults.standard.removeObject(forKey: Stored.timetableBaseDbSha)
        UserDefaults.standard.removeObject(forKey: Stored.timetableScheduleDbSha)
        UserDefaults.standard.removeObject(forKey: Stored.timetableLastCheckTimestamp)
    }

    private func hasUsableTimetableData() -> Bool {
        guard let baseDb, let scheduleDb else { return false }
        let stopCount = (baseDb.query("SELECT COUNT(*) AS count FROM stops").first?["count"] as? Int) ?? 0
        let routeCount = (baseDb.query("SELECT COUNT(*) AS count FROM routes").first?["count"] as? Int) ?? 0
        let tripCount = (scheduleDb.query("SELECT COUNT(*) AS count FROM trips").first?["count"] as? Int) ?? 0
        let stopTimeCount = (scheduleDb.query("SELECT COUNT(*) AS count FROM stop_times").first?["count"] as? Int) ?? 0
        return stopCount > 0 && routeCount > 0 && tripCount > 0 && stopTimeCount > 0
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

    func queryOfflineTrip(fromName: String, toName: String, date: Date, arrivalDeparture: ArrivalDeparture, maxTransfers: Int = 1, maxWalkDuration: Int = 15, arrivingAfter: Date? = nil, completion: @escaping ([Journey]) -> Void) {
        // Callers are on the main thread, which owns the published stops list; snapshot it before going off main.
        let imhdStops = GlobalController.stopsListProvider.stops
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self, let scheduleDb = self.scheduleDb, let baseDb = self.baseDb else {
                DispatchQueue.main.async { completion([]) }
                return
            }

            let engine = OfflineRoutingEngine(scheduleDb: scheduleDb, baseDb: baseDb)
            let journeys = engine.planTrip(
                fromName: fromName,
                toName: toName,
                date: date,
                arrivalDeparture: arrivalDeparture,
                maxTransfers: maxTransfers,
                maxWalkDuration: maxWalkDuration,
                imhdStops: imhdStops,
                arrivingAfter: arrivingAfter
            )

            DispatchQueue.main.async {
                completion(journeys)
            }
        }
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
