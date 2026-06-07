import Foundation

struct OfflineRoutingContext {
    let serviceDate: Date
    let dayStart: Date
    let stopsById: [String: OfflineStop]
    let zonesByStopId: [String: String]
    let tripsByKey: [String: OfflineTrip]
    let stopTimesByStopId: [String: [OfflineStopTime]]
    let walkLinksByStopId: [String: [OfflineWalkLink]]

    static func build(scheduleDb: SQLiteDatabase, baseDb: SQLiteDatabase, date: Date, maxWalkDuration: Int) -> OfflineRoutingContext {
        let calendar = bratislavaCalendar()
        let dayStart = calendar.startOfDay(for: date)
        let dateString = gtfsDateString(for: dayStart)
        let dayColumn = dayOfWeekColumn(for: dayStart)
        let stops = loadStops(baseDb: baseDb)
        let active = activeServiceIdsByFeed(scheduleDb: scheduleDb, date: dateString, dayColumn: dayColumn)
        let trips = loadTrips(scheduleDb: scheduleDb, activeServiceIdsByFeed: active)
        let sortedStops = stops.values.sorted(by: stopSort)
        let walkLinks = buildWalkLinks(stops: sortedStops, maxWalkDuration: maxWalkDuration)
        var stopTimesByStop = [String: [OfflineStopTime]]()
        for trip in trips.values {
            for stopTime in trip.stopTimes {
                stopTimesByStop[stopTime.stopId, default: []].append(stopTime)
            }
        }
        for stopId in stopTimesByStop.keys {
            stopTimesByStop[stopId]?.sort(by: stopTimeSort)
        }
        return OfflineRoutingContext(
            serviceDate: dayStart,
            dayStart: dayStart,
            stopsById: stops,
            zonesByStopId: Dictionary(uniqueKeysWithValues: stops.compactMap { key, stop in stop.zone.map { (key, $0) } }),
            tripsByKey: trips,
            stopTimesByStopId: stopTimesByStop,
            walkLinksByStopId: walkLinks
        )
    }

    private static func loadStops(baseDb: SQLiteDatabase) -> [String: OfflineStop] {
        let rows = baseDb.query("SELECT stop_id, feed, stop_name, stop_lat, stop_lon, platform_code, zone_id FROM stops")
        var stops = [String: OfflineStop]()
        for row in rows {
            guard let id = row["stop_id"] as? String,
                  let feed = row["feed"] as? String,
                  let name = row["stop_name"] as? String,
                  let lat = row["stop_lat"] as? Double,
                  let lon = row["stop_lon"] as? Double else { continue }
            stops[id] = OfflineStop(
                id: id,
                feed: feed,
                name: name,
                normalizedName: normalizeStopName(name),
                lat: lat,
                lon: lon,
                platform: row["platform_code"] as? String,
                zone: row["zone_id"] as? String
            )
        }
        return stops
    }

    private static func loadTrips(scheduleDb: SQLiteDatabase, activeServiceIdsByFeed: [String: Set<String>]) -> [String: OfflineTrip] {
        var clauses = [String]()
        var params = [Any]()
        for feed in ["city", "regional", "trains"] {
            guard let ids = activeServiceIdsByFeed[feed], !ids.isEmpty else { continue }
            let sortedIds = ids.sorted()
            clauses.append("(t.feed = ? AND t.service_id IN (\(sortedIds.map { _ in "?" }.joined(separator: ","))))")
            params.append(feed)
            params.append(contentsOf: sortedIds)
        }
        guard !clauses.isEmpty else { return [:] }
        let rows = scheduleDb.query("""
            SELECT st.trip_id, st.feed, st.stop_sequence, st.stop_id, st.departure_time,
                   t.service_id, t.trip_headsign, r.route_short_name, r.route_type
            FROM stop_times st
            JOIN trips t ON st.trip_id = t.trip_id AND st.feed = t.feed
            JOIN base.routes r ON t.route_id = r.route_id AND t.feed = r.feed
            WHERE \(clauses.joined(separator: " OR "))
            ORDER BY st.feed, st.trip_id, st.stop_sequence
        """, params: params)

        var grouped = [String: (id: String, feed: String, service: String, headsign: String, route: String, type: Int, stopTimes: [OfflineStopTime])]()
        for row in rows {
            guard let tripId = row["trip_id"] as? String,
                  let feed = row["feed"] as? String,
                  let seq = row["stop_sequence"] as? Int,
                  let stopId = row["stop_id"] as? String,
                  let dep = row["departure_time"] as? Int,
                  let service = row["service_id"] as? String,
                  let headsign = row["trip_headsign"] as? String,
                  let route = row["route_short_name"] as? String,
                  let type = row["route_type"] as? Int else { continue }
            let key = "\(feed):\(tripId)"
            let st = OfflineStopTime(tripKey: key, stopId: stopId, sequence: seq, arrival: dep, departure: dep)
            if grouped[key] == nil {
                grouped[key] = (tripId, feed, service, headsign, route, type, [])
            }
            grouped[key]?.stopTimes.append(st)
        }

        return Dictionary(uniqueKeysWithValues: grouped.map { key, value in
            let sorted = value.stopTimes.sorted(by: tripStopTimeSort)
            return (key, OfflineTrip(key: key, id: value.id, feed: value.feed, routeShortName: value.route, routeType: value.type, headsign: value.headsign, serviceId: value.service, stopTimes: sorted))
        })
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

    private static func buildWalkLinks(stops: [OfflineStop], maxWalkDuration: Int) -> [String: [OfflineWalkLink]] {
        guard maxWalkDuration > 0 else { return [:] }
        let limit = maxWalkDuration * 60
        let maxMeters = Double(limit) * 1.33
        let cellSize = maxMeters / 111_000.0
        var buckets = [WalkGridKey: [IndexedStop]]()
        for (index, stop) in stops.enumerated() {
            buckets[gridKey(lat: stop.lat, lon: stop.lon, cellSize: cellSize), default: []].append(IndexedStop(index: index, stop: stop))
        }

        var links = [String: [OfflineWalkLink]]()
        for stop in stops {
            let latDelta = maxMeters / 111_000.0
            let lonDelta = maxMeters / max(1.0, 111_000.0 * cos(stop.lat * .pi / 180))
            let minLatCell = gridCoord(stop.lat - latDelta, cellSize: cellSize)
            let maxLatCell = gridCoord(stop.lat + latDelta, cellSize: cellSize)
            let minLonCell = gridCoord(stop.lon - lonDelta, cellSize: cellSize)
            let maxLonCell = gridCoord(stop.lon + lonDelta, cellSize: cellSize)
            var candidates = [IndexedStop]()
            for latCell in minLatCell...maxLatCell {
                for lonCell in minLonCell...maxLonCell {
                    candidates.append(contentsOf: buckets[WalkGridKey(lat: latCell, lon: lonCell)] ?? [])
                }
            }
            candidates.sort { $0.index < $1.index }
            for candidate in candidates {
                let other = candidate.stop
                guard other.id != stop.id,
                      abs(other.lat - stop.lat) < latDelta,
                      abs(other.lon - stop.lon) < lonDelta else { continue }
                let seconds = max(30, Int(haversineMeters(lat1: stop.lat, lon1: stop.lon, lat2: other.lat, lon2: other.lon) / 1.33))
                if seconds <= limit {
                    links[stop.id, default: []].append(OfflineWalkLink(fromStopId: stop.id, toStopId: other.id, seconds: seconds))
                }
            }
        }
        for stopId in links.keys {
            links[stopId]?.sort(by: walkLinkSort)
        }
        return links
    }

    private struct IndexedStop {
        let index: Int
        let stop: OfflineStop
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

    private static func dayOfWeekColumn(for date: Date) -> String {
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

    private static func stopSort(_ lhs: OfflineStop, _ rhs: OfflineStop) -> Bool {
        if lhs.id != rhs.id { return lhs.id < rhs.id }
        return lhs.feed < rhs.feed
    }

    private static func stopTimeSort(_ lhs: OfflineStopTime, _ rhs: OfflineStopTime) -> Bool {
        if lhs.departure != rhs.departure { return lhs.departure < rhs.departure }
        if lhs.tripKey != rhs.tripKey { return lhs.tripKey < rhs.tripKey }
        if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
        return lhs.stopId < rhs.stopId
    }

    private static func tripStopTimeSort(_ lhs: OfflineStopTime, _ rhs: OfflineStopTime) -> Bool {
        if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
        if lhs.departure != rhs.departure { return lhs.departure < rhs.departure }
        return lhs.stopId < rhs.stopId
    }

    private static func walkLinkSort(_ lhs: OfflineWalkLink, _ rhs: OfflineWalkLink) -> Bool {
        if lhs.seconds != rhs.seconds { return lhs.seconds < rhs.seconds }
        return lhs.toStopId < rhs.toStopId
    }

    private static func normalizeStopName(_ name: String) -> String {
        name.replacingOccurrences(of: "Bratislava, ", with: "")
            .replacingOccurrences(of: "Rovinka, ", with: "")
            .replacingOccurrences(of: "Dunajská Lužná, ", with: "")
            .replacingOccurrences(of: "Miloslavov, ", with: "")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "sk_SK"))
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
