import CoreLocation
import Foundation

class OfflineRoutingEngine {
    let scheduleDb: SQLiteDatabase
    let baseDb: SQLiteDatabase

    init(scheduleDb: SQLiteDatabase, baseDb: SQLiteDatabase) {
        self.scheduleDb = scheduleDb
        self.baseDb = baseDb
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

    struct GraphState {
        let stopId: String
        let time: Int
        let parts: [Part]
        let zones: Set<String>
        let transitLegs: Int
        let lastTripId: String?
    }

    private func normalizeStopName(_ name: String) -> String {
        return name.replacingOccurrences(of: "Bratislava, ", with: "")
                   .replacingOccurrences(of: "Rovinka, ", with: "")
                   .replacingOccurrences(of: "Dunajská Lužná, ", with: "")
                   .replacingOccurrences(of: "Miloslavov, ", with: "")
    }

    private func getStops(name: String) -> [StopInfo] {
        // City GTFS uses bare names (e.g. "Hronská"); regional/trains GTFS prefixes with
        // city ("Bratislava, Hronská", "Bratislava, AS"). iOS Magic-API Stop.name matches
        // the bare form. Match both feeds explicitly so we can later transfer onto
        // regional/train trips departing from the same physical location.
        let candidates: [String]
        if name == "Autobusová stanica" {
            candidates = [name, "Bratislava, AS", "Bratislava, Autobusová stanica"]
        } else {
            candidates = [name, "Bratislava, " + name]
        }

        var seen = Set<String>()
        var collected = [[String: Any]]()
        for candidate in candidates {
            let rows = baseDb.query(
                "SELECT stop_id, stop_name, stop_lat, stop_lon, platform_code, feed FROM stops WHERE stop_name = ?",
                params: [candidate]
            )
            for row in rows {
                if let id = row["stop_id"] as? String, seen.insert(id).inserted {
                    collected.append(row)
                }
            }
        }

        // Last-resort fuzzy match, restricted to city to avoid cross-region collisions.
        if collected.isEmpty {
            let rows = baseDb.query(
                "SELECT stop_id, stop_name, stop_lat, stop_lon, platform_code, feed FROM stops WHERE stop_name LIKE ? AND feed = 'city'",
                params: ["%" + name + "%"]
            )
            for row in rows {
                if let id = row["stop_id"] as? String, seen.insert(id).inserted {
                    collected.append(row)
                }
            }
        }

        return collected.compactMap { row in
            guard let id = row["stop_id"] as? String,
                  let sname = row["stop_name"] as? String,
                  let lat = row["stop_lat"] as? Double,
                  let lon = row["stop_lon"] as? Double,
                  let feed = row["feed"] as? String else { return nil }
            return StopInfo(
                id: id,
                name: sname,
                normalizedName: normalizeStopName(sname),
                lat: lat,
                lon: lon,
                platform: row["platform_code"] as? String,
                feed: feed
            )
        }
    }

    /// Walking speed used to convert distance → walk time. ~1.33 m/s = 80 m/min, slow pace.
    private static let walkSpeedMetersPerSecond: Double = 1.33
    /// Minimum platform-transfer time in seconds; covers boarding lag even when stops are adjacent.
    private static let minWalkSeconds: Int = 30

    private func haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6371e3
        let phi1 = lat1 * .pi / 180
        let phi2 = lat2 * .pi / 180
        let dPhi = (lat2 - lat1) * .pi / 180
        let dLam = (lon2 - lon1) * .pi / 180
        let a = sin(dPhi / 2) * sin(dPhi / 2) + cos(phi1) * cos(phi2) * sin(dLam / 2) * sin(dLam / 2)
        return r * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    /// Returns walk time in seconds for the given distance, or nil if it exceeds the user's cap.
    private func walkSeconds(meters: Double, maxWalkMinutes: Int) -> Int? {
        let seconds = max(Self.minWalkSeconds, Int(meters / Self.walkSpeedMetersPerSecond))
        if seconds > maxWalkMinutes * 60 { return nil }
        return seconds
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

    private func activeServiceIds(feed: String, date: String, dayOfWeek: String) -> Set<String> {
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
                  let exType = row["exception_type"] as? Int else { continue }
            if exType == 1 { serviceIds.insert(sid) }
            if exType == 2 { serviceIds.remove(sid) }
        }
        return serviceIds
    }

    func planTrip(fromName: String, toName: String, date: Date, maxTransfers: Int, maxWalkDuration: Int) -> [Journey] {
        let fromStops = getStops(name: fromName)
        let toStops = getStops(name: toName)
        if fromStops.isEmpty || toStops.isEmpty { return [] }

        let calendar = Calendar.current
        let startOfSearchDay = calendar.startOfDay(for: date)
        // Small back-shift to surface trips the user "just missed" (clock skew, walking-to-stop).
        // In-progress trips that the user can still board at downstream stops are handled
        // naturally by the BFS: each stop_time has its own departure_time, so the boarding
        // check (`pt.dep >= origin.time`) admits them on its own.
        let departureSlackSeconds = 5 * 60
        let initialTimeInSeconds = max(0, Int(date.timeIntervalSince(startOfSearchDay)) - departureSlackSeconds)

        var journeys = [Journey]()
        let toStopIds = Set(toStops.map { $0.id })

        let allStopsRows = baseDb.query(
            "SELECT stop_id, stop_name, stop_lat, stop_lon, platform_code, feed, zone_id FROM stops"
        )
        var allStops = [String: StopInfo]()
        var stopsByName = [String: [StopInfo]]()
        var zonesByStop = [String: String]()
        for row in allStopsRows {
            guard let id = row["stop_id"] as? String,
                  let sname = row["stop_name"] as? String,
                  let lat = row["stop_lat"] as? Double,
                  let lon = row["stop_lon"] as? Double,
                  let feed = row["feed"] as? String else { continue }
            let info = StopInfo(
                id: id,
                name: sname,
                normalizedName: normalizeStopName(sname),
                lat: lat,
                lon: lon,
                platform: row["platform_code"] as? String,
                feed: feed
            )
            allStops[id] = info
            stopsByName[info.normalizedName, default: []].append(info)
            if let z = row["zone_id"] as? String, !z.isEmpty { zonesByStop[id] = z }
        }

        let maxLegs = min(maxTransfers + 1, 6)
        // Per-day search window: bound stop_times prefetch so we don't load the entire
        // day's million+ rows. 8h covers the longest realistic Bratislava city journey
        // including waits, while pruning the bulk of the table from memory.
        let searchWindowSeconds = 8 * 3600
        var currentDayOffset = 0
        while journeys.count < 5 && currentDayOffset < 2 {
            let evalDay = startOfSearchDay.addingTimeInterval(TimeInterval(currentDayOffset * 86400))
            let dateStr = evalDay.toString()
            let dayOfWeek = dayOfWeekColumn(for: evalDay)

            // Collect (feed, serviceIds) pairs separately so we can filter trips per feed.
            let feeds = ["city", "regional", "trains"]
            var serviceIdsByFeed = [String: Set<String>]()
            var totalActive = 0
            for feed in feeds {
                let sids = activeServiceIds(feed: feed, date: dateStr, dayOfWeek: dayOfWeek)
                if !sids.isEmpty {
                    serviceIdsByFeed[feed] = sids
                    totalActive += sids.count
                }
            }
            if totalActive == 0 { currentDayOffset += 1; continue }

            // Day-relative time window (seconds since start of evalDay).
            // For day 0, anchor at the user's chosen time minus the 3h back-shift.
            // For day N>0, anchor at the start of that day.
            let dayWindowStart = (currentDayOffset == 0) ? initialTimeInSeconds : 0
            let dayWindowEnd = dayWindowStart + searchWindowSeconds

            // Build OR'd WHERE clause: (t.feed=? AND t.service_id IN (...)) OR ...
            var whereClauses = [String]()
            var params: [Any] = []
            for (feed, sids) in serviceIdsByFeed {
                let placeholders = sids.map { _ in "?" }.joined(separator: ",")
                whereClauses.append("(t.feed = ? AND t.service_id IN (\(placeholders)))")
                params.append(feed)
                params.append(contentsOf: Array(sids))
            }
            let whereClause = whereClauses.joined(separator: " OR ")

            // Load every stop_time of every trip that has at least one stop_time in the window.
            // The EXISTS subquery uses idx_st_trip; the outer WHERE narrows by service_id.
            // Bind time bounds twice — once for EXISTS, once for the outer (no-op) clause kept
            // so SQLite picks the right index.
            var queryParams: [Any] = [dayWindowStart, dayWindowEnd]
            queryParams.append(contentsOf: params)
            let q = """
                SELECT st.trip_id, st.stop_id, st.departure_time,
                       st.departure_time AS arrival_time, st.stop_sequence,
                       r.route_short_name, r.route_type, t.trip_headsign, st.feed
                FROM stop_times st
                JOIN trips t ON st.trip_id = t.trip_id AND st.feed = t.feed
                JOIN base.routes r ON t.route_id = r.route_id AND t.feed = r.feed
                WHERE EXISTS (
                    SELECT 1 FROM stop_times st2
                    WHERE st2.trip_id = st.trip_id AND st2.feed = st.feed
                      AND st2.departure_time BETWEEN ? AND ?
                )
                AND (\(whereClause))
            """
            let rows = scheduleDb.query(q, params: queryParams)

            var tripsDict = [String: MemTrip]()
            for row in rows {
                guard let tId = row["trip_id"] as? String,
                      let sId = row["stop_id"] as? String,
                      let dep = row["departure_time"] as? Int,
                      let arr = row["arrival_time"] as? Int,
                      let seq = row["stop_sequence"] as? Int,
                      let rS = row["route_short_name"] as? String,
                      let rT = row["route_type"] as? Int,
                      let h = row["trip_headsign"] as? String,
                      let f = row["feed"] as? String else { continue }
                let adjustedDep = dep + (currentDayOffset * 86400)
                let adjustedArr = arr + (currentDayOffset * 86400)
                let st = MemStopTime(stopId: sId, arrival: adjustedArr, departure: adjustedDep, seq: seq)
                if tripsDict[tId] != nil {
                    tripsDict[tId]!.stopTimes.append(st)
                } else {
                    tripsDict[tId] = MemTrip(
                        id: tId, feed: f, routeShortName: rS, routeType: rT, headsign: h, stopTimes: [st]
                    )
                }
            }

            var tripsByStop = [String: [(tripId: String, seq: Int, dep: Int, stopId: String)]]()
            for (tId, trip) in tripsDict {
                for st in trip.stopTimes {
                    tripsByStop[st.stopId, default: []].append(
                        (tripId: tId, seq: st.seq, dep: st.departure, stopId: st.stopId)
                    )
                }
            }

            let dayStartTime = (currentDayOffset == 0) ? initialTimeInSeconds : (currentDayOffset * 86400)
            // Bound start candidates by departure-time window (absolute seconds with day offset
            // already baked in by adjustedDep above) plus a soft cap so a quiet stop on a busy
            // day doesn't degenerate into thousands of starts.
            let absWindowStart = dayStartTime + (currentDayOffset * 86400)
            let absWindowEnd = absWindowStart + searchWindowSeconds
            var startTripsAtOrigin = [(tripId: String, seq: Int, dep: Int, stopId: String)]()
            for fs in fromStops {
                startTripsAtOrigin.append(contentsOf: tripsByStop[fs.id] ?? [])
            }
            startTripsAtOrigin = startTripsAtOrigin
                .filter { $0.dep >= absWindowStart && $0.dep <= absWindowEnd }
                .sorted { $0.dep < $1.dep }
            let startTripCandidates = startTripsAtOrigin.prefix(60)

            for startCandidate in startTripCandidates {
                // Pareto frontier per stop: list of non-dominated (arrival, legs) pairs.
                // A new state at (T, L) is admissible only if no existing entry dominates it
                // (arrival ≤ T AND legs ≤ L). On admit, drop any existing entries this state
                // dominates. This preserves equal-arrival alternatives that use fewer transfers
                // — the greedy "strictly less arrival" rule used to discard them.
                var paretoByStop = [String: [(arrival: Int, legs: Int)]]()
                func tryAdmit(stopId: String, arrival: Int, legs: Int) -> Bool {
                    let entries = paretoByStop[stopId] ?? []
                    for e in entries where e.arrival <= arrival && e.legs <= legs {
                        return false
                    }
                    var pruned = entries.filter { e in
                        !(arrival <= e.arrival && legs <= e.legs && (arrival < e.arrival || legs < e.legs))
                    }
                    pruned.append((arrival, legs))
                    paretoByStop[stopId] = pruned
                    return true
                }
                var journeysForThisStart = [Journey]()
                var activeStates = [GraphState(
                    stopId: startCandidate.stopId,
                    time: startCandidate.dep,
                    parts: [],
                    zones: [],
                    transitLegs: 0,
                    lastTripId: nil
                )]

                for leg in 1...maxLegs {
                    if activeStates.isEmpty { break }
                    var nextStates = [GraphState]()
                    for state in activeStates {
                        guard let currStopData = allStops[state.stopId] else { continue }
                        var origins = [(id: String, time: Int, part: Part?)]()
                        origins.append((id: state.stopId, time: state.time, part: nil))

                        // Platform transfers (same normalized name) — only after at least one
                        // transit leg, with walk time computed from actual distance and capped
                        // by the user's maxWalkDuration setting.
                        if !state.parts.isEmpty && maxWalkDuration > 0 {
                            for target in stopsByName[currStopData.normalizedName] ?? [] {
                                if target.id == state.stopId { continue }
                                let dist = haversineMeters(
                                    lat1: currStopData.lat, lon1: currStopData.lon,
                                    lat2: target.lat, lon2: target.lon
                                )
                                guard let walkSec = walkSeconds(meters: dist, maxWalkMinutes: maxWalkDuration) else {
                                    continue
                                }
                                let walkPart = Part(
                                    startStopName: currStopData.name,
                                    endStopName: target.name,
                                    startStopCode: currStopData.platform,
                                    endStopCode: target.platform,
                                    startDeparture: startOfSearchDay.addingTimeInterval(TimeInterval(state.time)),
                                    endArrival: startOfSearchDay.addingTimeInterval(TimeInterval(state.time + walkSec)),
                                    routeType: 64,
                                    tripHeadsign: "Walk to platform",
                                    routeShortName: nil
                                )
                                origins.append((id: target.id, time: state.time + walkSec, part: walkPart))
                            }
                        }

                        for origin in origins {
                            let passingTrips = tripsByStop[origin.id] ?? []
                            for pt in passingTrips {
                                if pt.tripId == state.lastTripId { continue }
                                if pt.dep < origin.time || pt.dep > origin.time + 43200 { continue } // 12h wait
                                guard let trip = tripsDict[pt.tripId] else { continue }
                                for st in trip.stopTimes where st.seq > pt.seq {
                                    if tryAdmit(stopId: st.stopId, arrival: st.arrival, legs: leg) {
                                        var nParts = state.parts
                                        if let wp = origin.part { nParts.append(wp) }
                                        let p = Part(
                                            startStopName: allStops[origin.id]?.name ?? origin.id,
                                            endStopName: allStops[st.stopId]?.name ?? st.stopId,
                                            startStopCode: allStops[origin.id]?.platform,
                                            endStopCode: allStops[st.stopId]?.platform,
                                            startDeparture: startOfSearchDay.addingTimeInterval(TimeInterval(pt.dep)),
                                            endArrival: startOfSearchDay.addingTimeInterval(TimeInterval(st.arrival)),
                                            routeType: trip.routeType,
                                            tripHeadsign: trip.headsign,
                                            routeShortName: trip.routeShortName
                                        )
                                        nParts.append(p)
                                        var nZones = state.zones
                                        for tst in trip.stopTimes where tst.seq >= pt.seq && tst.seq <= st.seq {
                                            if let z = zonesByStop[tst.stopId] { nZones.insert(z) }
                                        }
                                        if toStopIds.contains(st.stopId) {
                                            journeysForThisStart.append(Journey(
                                                id: UUID().uuidString,
                                                parts: nParts,
                                                zones: Array(nZones).sorted()
                                            ))
                                        } else if leg < maxLegs {
                                            nextStates.append(GraphState(
                                                stopId: st.stopId,
                                                time: st.arrival,
                                                parts: nParts,
                                                zones: nZones,
                                                transitLegs: leg,
                                                lastTripId: pt.tripId
                                            ))
                                        }
                                    }
                                }
                            }
                        }
                    }
                    activeStates = nextStates
                    if !journeysForThisStart.isEmpty { break }
                }

                if let best = journeysForThisStart.sorted(by: {
                    ($0.parts?.last?.endArrival ?? Date()) < ($1.parts?.last?.endArrival ?? Date())
                }).first {
                    journeys.append(best)
                }
                if journeys.count >= 5 { break }
            }
            currentDayOffset += 1
        }

        journeys.sort {
            ($0.parts?.first?.startDeparture ?? Date()) < ($1.parts?.first?.startDeparture ?? Date())
        }
        return Array(unique(journeys).prefix(10))
    }

    private func unique(_ journeys: [Journey]) -> [Journey] {
        var result = [Journey]()
        for j in journeys where !result.contains(where: { $0 == j }) {
            result.append(j)
        }
        return result
    }
}
