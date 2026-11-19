import Foundation

/// One service day's timetable, indexed for `OfflineTimetableRouter`. Stops and trips are
/// referred to by their index in `stops` and `trips`.
struct OfflineRoutingContext {
    /// Time zero of the day's service-day seconds, see `serviceDayStart(for:)`.
    let dayStart: Date
    let stops: [OfflineStop]
    let stopIndexById: [String: Int32]
    let trips: [OfflineTrip]
    let routes: [OfflineRoute]
    /// The routes serving each stop, with the stop's position on the route.
    let routesAtStop: [[OfflineRouteStop]]
    /// Stops within the walk limit of each stop, nearest first.
    let footpaths: [[OfflineFootpath]]

    static func build(scheduleDb: SQLiteDatabase, baseDb: SQLiteDatabase, date: Date, maxWalkDuration: Int) -> OfflineRoutingContext {
        let calendar = bratislavaCalendar()
        let dayStart = calendar.startOfDay(for: date)
        let dateString = gtfsDateString(for: dayStart)
        let dayColumn = dayOfWeekColumn(for: dayStart)
        let stops = loadStops(baseDb: baseDb)
        var stopIndexById = [String: Int32](minimumCapacity: stops.count)
        for (index, stop) in stops.enumerated() {
            stopIndexById[stop.id] = Int32(index)
        }
        let active = activeServiceIdsByFeed(scheduleDb: scheduleDb, date: dateString, dayColumn: dayColumn)
        let (trips, routes) = loadRoutes(scheduleDb: scheduleDb, activeServiceIdsByFeed: active, stopIndexById: stopIndexById)
        var routesAtStop = Array(repeating: [OfflineRouteStop](), count: stops.count)
        for (routeIndex, route) in routes.enumerated() {
            for (position, stop) in route.stops.enumerated() {
                routesAtStop[Int(stop)].append(OfflineRouteStop(route: Int32(routeIndex), position: Int32(position)))
            }
        }
        return OfflineRoutingContext(
            dayStart: serviceDayStart(for: dayStart),
            stops: stops,
            stopIndexById: stopIndexById,
            trips: trips,
            routes: routes,
            routesAtStop: routesAtStop,
            footpaths: buildFootpaths(stops: stops, maxWalkDuration: maxWalkDuration)
        )
    }

    /// GTFS times count from noon minus 12 hours of the service day: midnight, except on the days
    /// the clocks change, which have 23 or 25 hours.
    static func serviceDayStart(for date: Date) -> Date {
        bratislavaCalendar().date(bySettingHour: 12, minute: 0, second: 0, of: date)!.addingTimeInterval(-12 * 60 * 60)
    }

    /// The `stop_times` arrival expression. Databases built before arrival times were kept have
    /// no such column; arrival equals departure there, as it does where the column is NULL.
    static func arrivalTimeColumn(scheduleDb: SQLiteDatabase) -> String {
        let hasArrivalTimes = scheduleDb.query("PRAGMA table_info(stop_times)").contains { $0["name"] as? String == "arrival_time" }
        return hasArrivalTimes ? "COALESCE(st.arrival_time, st.departure_time)" : "st.departure_time"
    }

    private static func loadStops(baseDb: SQLiteDatabase) -> [OfflineStop] {
        var stops = [OfflineStop]()
        baseDb.forEachRow("SELECT stop_id, feed, stop_name, stop_lat, stop_lon, platform_code, zone_id FROM stops ORDER BY stop_id, feed") { row in
            guard let id = row.string(0), let feed = row.string(1), let name = row.string(2) else { return }
            stops.append(OfflineStop(
                id: id,
                feed: feed,
                name: name,
                lat: row.double(3),
                lon: row.double(4),
                platform: row.string(5),
                zone: row.string(6)
            ))
        }
        return stops
    }

    /// The day's trips, and the routes they form: trips with the same stop sequence, split so
    /// that none overtakes an earlier one.
    private static func loadRoutes(
        scheduleDb: SQLiteDatabase,
        activeServiceIdsByFeed: [String: Set<String>],
        stopIndexById: [String: Int32]
    ) -> (trips: [OfflineTrip], routes: [OfflineRoute]) {
        var clauses = [String]()
        var params = [Any]()
        for feed in ["city", "regional", "trains"] {
            guard let ids = activeServiceIdsByFeed[feed], !ids.isEmpty else { continue }
            let sortedIds = ids.sorted()
            clauses.append("(t.feed = ? AND t.service_id IN (\(sortedIds.map { _ in "?" }.joined(separator: ","))))")
            params.append(feed)
            params.append(contentsOf: sortedIds)
        }
        guard !clauses.isEmpty else { return ([], []) }

        // An ORDER BY would sort every row in a temporary B-tree. Rows normally arrive grouped by
        // trip and in stop order (the stop_times primary key), so group them here and sort only a
        // trip that is not.
        var trips = [OfflineTrip]()
        var stopTimes = [[(sequence: Int, stop: Int32, departure: Int32, arrival: Int32)]]()
        var tripIndexByKey = [String: Int]()
        var currentFeed = ""
        var currentTripId = ""
        var current = -1
        scheduleDb.forEachRow("""
            SELECT st.feed, st.trip_id, st.stop_id, st.departure_time, \(arrivalTimeColumn(scheduleDb: scheduleDb)),
                   st.stop_sequence, t.trip_headsign, r.route_short_name, r.route_type
            FROM stop_times st
            JOIN trips t ON st.trip_id = t.trip_id AND st.feed = t.feed
            JOIN base.routes r ON t.route_id = r.route_id AND t.feed = r.feed
            WHERE \(clauses.joined(separator: " OR "))
        """, params: params) { row in
            guard let feed = row.string(0),
                  let tripId = row.string(1),
                  let stop = row.string(2).flatMap({ stopIndexById[$0] }),
                  let headsign = row.string(6),
                  let routeShortName = row.string(7) else { return }
            if feed != currentFeed || tripId != currentTripId {
                currentFeed = feed
                currentTripId = tripId
                let key = "\(feed):\(tripId)"
                if let index = tripIndexByKey[key] {
                    current = index
                } else {
                    current = trips.count
                    tripIndexByKey[key] = current
                    trips.append(OfflineTrip(key: key, routeShortName: routeShortName, routeType: row.int(8), headsign: headsign))
                    stopTimes.append([])
                }
            }
            stopTimes[current].append((row.int(5), stop, Int32(row.int(3)), Int32(row.int(4))))
        }

        // Group by stop sequence, in trip order so route indices do not depend on hashing.
        var patternIndex = [[Int32]: Int]()
        var patterns = [(stops: [Int32], trips: [Int])]()
        var timetables = [(departures: [Int32], arrivals: [Int32])]()
        for (trip, var times) in stopTimes.enumerated() {
            if !zip(times, times.dropFirst()).allSatisfy({ $0.sequence < $1.sequence }) {
                times.sort { $0.sequence < $1.sequence }
            }
            timetables.append((times.map(\.departure), times.map(\.arrival)))
            guard times.count > 1 else { continue }
            let stops = times.map(\.stop)
            if let index = patternIndex[stops] {
                patterns[index].trips.append(trip)
            } else {
                patternIndex[stops] = patterns.count
                patterns.append((stops, [trip]))
            }
        }
        var routes = [OfflineRoute]()
        for pattern in patterns {
            let sorted = pattern.trips.sorted { (timetables[$0].departures[0], $0) < (timetables[$1].departures[0], $1) }
            var groups = [[Int]]()
            for trip in sorted {
                let times = timetables[trip]
                let group = groups.firstIndex { group in
                    let last = timetables[group[group.count - 1]]
                    return zip(last.departures, times.departures).allSatisfy { $0 <= $1 }
                        && zip(last.arrivals, times.arrivals).allSatisfy { $0 <= $1 }
                }
                if let group {
                    groups[group].append(trip)
                } else {
                    groups.append([trip])
                }
            }
            for group in groups {
                routes.append(OfflineRoute(
                    stops: pattern.stops,
                    trips: group.map { Int32($0) },
                    departures: group.flatMap { timetables[$0].departures },
                    arrivals: group.flatMap { timetables[$0].arrivals }
                ))
            }
        }
        return (trips, routes)
    }

    private static func activeServiceIdsByFeed(scheduleDb: SQLiteDatabase, date: String, dayColumn: String) -> [String: Set<String>] {
        var result = [String: Set<String>]()
        for feed in ["city", "regional", "trains"] {
            let calendarRows = scheduleDb.query("""
                SELECT service_id FROM calendar
                WHERE feed = ? AND start_date <= ? AND end_date >= ? AND \(dayColumn) = 1
            """, params: [feed, date, date])
            var ids = Set(calendarRows.compactMap { $0["service_id"] as? String })
            let exceptionRows = scheduleDb.query("SELECT service_id, exception_type FROM calendar_dates WHERE feed = ? AND date = ?", params: [feed, date])
            for row in exceptionRows {
                guard let serviceId = row["service_id"] as? String,
                      let type = row["exception_type"] as? Int else { continue }
                if type == 1 { ids.insert(serviceId) }
                if type == 2 { ids.remove(serviceId) }
            }
            result[feed] = ids
        }
        return result
    }

    private static func buildFootpaths(stops: [OfflineStop], maxWalkDuration: Int) -> [[OfflineFootpath]] {
        var footpaths = Array(repeating: [OfflineFootpath](), count: stops.count)
        guard maxWalkDuration > 0 else { return footpaths }
        let limit = maxWalkDuration * 60
        let maxMeters = Double(limit) * OfflineWalk.metersPerSecond
        let cellSize = maxMeters / 111_000.0
        var buckets = [WalkGridKey: [Int]]()
        for (index, stop) in stops.enumerated() {
            buckets[gridKey(lat: stop.lat, lon: stop.lon, cellSize: cellSize), default: []].append(index)
        }

        for (index, stop) in stops.enumerated() {
            let latDelta = maxMeters / 111_000.0
            let lonDelta = maxMeters / max(1.0, 111_000.0 * cos(stop.lat * .pi / 180))
            let minLatCell = gridCoord(stop.lat - latDelta, cellSize: cellSize)
            let maxLatCell = gridCoord(stop.lat + latDelta, cellSize: cellSize)
            let minLonCell = gridCoord(stop.lon - lonDelta, cellSize: cellSize)
            let maxLonCell = gridCoord(stop.lon + lonDelta, cellSize: cellSize)
            for latCell in minLatCell...maxLatCell {
                for lonCell in minLonCell...maxLonCell {
                    for otherIndex in buckets[WalkGridKey(lat: latCell, lon: lonCell)] ?? [] {
                        let other = stops[otherIndex]
                        guard otherIndex != index,
                              abs(other.lat - stop.lat) < latDelta,
                              abs(other.lon - stop.lon) < lonDelta else { continue }
                        let seconds = OfflineWalk.seconds(forMeters: haversineMeters(lat1: stop.lat, lon1: stop.lon, lat2: other.lat, lon2: other.lon))
                        if seconds <= limit {
                            footpaths[index].append(OfflineFootpath(stop: Int32(otherIndex), seconds: Int32(seconds)))
                        }
                    }
                }
            }
            footpaths[index].sort { ($0.seconds, $0.stop) < ($1.seconds, $1.stop) }
        }
        return footpaths
    }

    private struct WalkGridKey: Hashable {
        let lat: Int
        let lon: Int
    }

    private static func gridKey(lat: Double, lon: Double, cellSize: Double) -> WalkGridKey {
        WalkGridKey(lat: gridCoord(lat, cellSize: cellSize), lon: gridCoord(lon, cellSize: cellSize))
    }

    private static func gridCoord(_ value: Double, cellSize: Double) -> Int {
        Int(floor(value / cellSize))
    }

    static func dayOfWeekColumn(for date: Date) -> String {
        switch bratislavaCalendar().component(.weekday, from: date) {
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

    private static func bratislavaCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = bratislavaTimeZone()
        return calendar
    }

    private static func bratislavaTimeZone() -> TimeZone {
        TimeZone(identifier: "Europe/Bratislava")!
    }

    private static func gtfsDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = bratislavaCalendar()
        formatter.timeZone = bratislavaTimeZone()
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    private static func haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6371e3
        let phi1 = lat1 * .pi / 180
        let phi2 = lat2 * .pi / 180
        let dPhi = (lat2 - lat1) * .pi / 180
        let dLam = (lon2 - lon1) * .pi / 180
        let a = sin(dPhi / 2) * sin(dPhi / 2) + cos(phi1) * cos(phi2) * sin(dLam / 2) * sin(dLam / 2)
        return r * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
