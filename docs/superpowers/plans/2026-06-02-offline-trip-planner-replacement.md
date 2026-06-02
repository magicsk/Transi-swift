# Offline Trip Planner Replacement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current offline BFS trip planner with an under-5-second timetable router that returns equal or better meaningful options than the combined R API and I API.

**Architecture:** Keep the public `TimetableDatabase.queryOfflineTrip(...) -> [Journey]` API stable. Split offline routing into focused files: context loading, stop resolving, walking links, timetable routing, grouping, and mapping back to `Journey`. Use deterministic CLI verification first, then production integration.

**Tech Stack:** Swift 5/6, Foundation, SQLite3 wrapper in `Shared/Util/SQLite.swift`, existing GTFS SQLite databases from `~/Developer/js/api/public/timetable`, Node for dev-only online comparison.

---

## File Structure

- Create `Scripts/offline-routing-check.swift`
  Deterministic CLI verification harness. Opens local `base.db` and `schedule.db`, calls `OfflineRoutingEngine`, asserts counts, timing, departure cutoff, line sequences, and arrival mode.
- Create `Scripts/compare-offline-online.mjs`
  Dev-only online comparison harness. Calls R API and I API, then prints route count/sequence/time comparisons against offline output.
- Create `Shared/Controllers/OfflineRoutingTypes.swift`
  Shared internal routing structs and helpers: stop metadata, stop time, trip pattern, walking link, route label, candidate journey, grouped journey.
- Create `Shared/Controllers/OfflineStopResolver.swift`
  Resolves app stop names to GTFS candidates with aliases, coordinate clusters, and nearby candidates.
- Create `Shared/Controllers/OfflineRoutingContext.swift`
  Loads active service IDs, stops, trips, stop times, stop indexes, route indexes, and walking links for a query date.
- Create `Shared/Controllers/OfflineTimetableRouter.swift`
  Performs departure and arrival routing with transfer rounds and Pareto pruning.
- Create `Shared/Controllers/OfflineJourneyGrouper.swift`
  Groups equivalent journeys and selects representative journeys.
- Modify `Shared/Controllers/OfflineRoutingEngine.swift`
  Replace the current BFS body with orchestration using the new components.
- Modify `Shared/Controllers/TimetableDatabase.swift`
  Pass `arrivalDeparture` to the engine.
- Modify `Transi.xcodeproj/project.pbxproj`
  Add new Swift files to the main app target sources.

## Task 1: Add Deterministic Offline Routing Harness

**Files:**
- Create: `Scripts/offline-routing-check.swift`

- [ ] **Step 1: Write failing harness**

Create `Scripts/offline-routing-check.swift`:

```swift
import Foundation

struct CheckCase {
    let label: String
    let from: String
    let to: String
    let iso: String
    let mode: ArrivalDeparture
    let minJourneys: Int
    let maxMs: Int
    let requiredLines: Set<String>
}

let cases: [CheckCase] = [
    CheckCase(label: "short_city", from: "Hronská", to: "Most SNP", iso: "2026-06-02T08:00:00+02:00", mode: .departure, minJourneys: 5, maxMs: 5000, requiredLines: ["70"]),
    CheckCase(label: "medium_city", from: "Zlaté piesky", to: "Hlavná stanica", iso: "2026-06-02T08:00:00+02:00", mode: .departure, minJourneys: 5, maxMs: 5000, requiredLines: ["61"]),
    CheckCase(label: "train_station_pair", from: "Hlavná stanica", to: "Stn. Petržalka", iso: "2026-06-02T08:00:00+02:00", mode: .departure, minJourneys: 5, maxMs: 5000, requiredLines: ["93"]),
    CheckCase(label: "regional_bus", from: "Autobusová stanica", to: "Rovinka, Obecný úrad", iso: "2026-06-02T08:00:00+02:00", mode: .departure, minJourneys: 5, maxMs: 5000, requiredLines: ["725", "727", "737"]),
    CheckCase(label: "regional_train", from: "Hlavná stanica", to: "Pezinok, Žel. stanica", iso: "2026-06-02T08:00:00+02:00", mode: .departure, minJourneys: 4, maxMs: 5000, requiredLines: ["R50", "S50"]),
    CheckCase(label: "long_suburban", from: "Most SNP", to: "Senec, Žel. stanica", iso: "2026-06-02T08:00:00+02:00", mode: .departure, minJourneys: 4, maxMs: 5000, requiredLines: ["S60", "620"]),
    CheckCase(label: "late_short", from: "Hronská", to: "Most SNP", iso: "2026-06-02T23:30:00+02:00", mode: .departure, minJourneys: 3, maxMs: 5000, requiredLines: ["N70"]),
    CheckCase(label: "arrival_city", from: "Hronská", to: "Most SNP", iso: "2026-06-02T08:40:00+02:00", mode: .arrival, minJourneys: 3, maxMs: 5000, requiredLines: ["70"]),
]

let basePath = ProcessInfo.processInfo.environment["TRANSI_BASE_DB"] ?? "/Users/magic_sk/Developer/js/api/public/timetable/base.db"
let schedulePath = ProcessInfo.processInfo.environment["TRANSI_SCHEDULE_DB"] ?? "/Users/magic_sk/Developer/js/api/public/timetable/schedule.db"

guard let baseDb = SQLiteDatabase(path: basePath), let scheduleDb = SQLiteDatabase(path: schedulePath) else {
    fatalError("Failed to open timetable databases")
}
scheduleDb.execute("ATTACH DATABASE '\(basePath)' AS base")

let parser = ISO8601DateFormatter()
parser.formatOptions = [.withInternetDateTime]
let selected = Set(CommandLine.arguments.dropFirst())
let checkCases = selected.isEmpty ? cases : cases.filter { selected.contains($0.label) }
var failures = [String]()

for check in checkCases {
    guard let date = parser.date(from: check.iso) else {
        failures.append("\(check.label): invalid date")
        continue
    }

    let engine = OfflineRoutingEngine(scheduleDb: scheduleDb, baseDb: baseDb)
    let start = Date()
    let journeys = engine.planTrip(
        fromName: check.from,
        toName: check.to,
        date: date,
        arrivalDeparture: check.mode,
        maxTransfers: 3,
        maxWalkDuration: 15
    )
    let elapsedMs = Int(Date().timeIntervalSince(start) * 1000)
    let allLines = Set(journeys.flatMap { ($0.parts ?? []).compactMap(\.routeShortName) })
    let firstDeparture = journeys.compactMap { $0.parts?.first?.startDeparture }.min()
    let lastArrival = journeys.compactMap { $0.parts?.last?.endArrival }.max()

    print("\(check.label): count=\(journeys.count) elapsedMs=\(elapsedMs) lines=\(Array(allLines).sorted())")

    if elapsedMs > check.maxMs {
        failures.append("\(check.label): elapsed \(elapsedMs)ms > \(check.maxMs)ms")
    }
    if journeys.count < check.minJourneys {
        failures.append("\(check.label): count \(journeys.count) < \(check.minJourneys)")
    }
    if check.requiredLines.isDisjoint(with: allLines) {
        failures.append("\(check.label): missing required lines \(Array(check.requiredLines).sorted())")
    }
    if check.mode == .departure, let firstDeparture, firstDeparture < date {
        failures.append("\(check.label): first departure \(firstDeparture) is before requested \(date)")
    }
    if check.mode == .arrival, let lastArrival, lastArrival > date {
        failures.append("\(check.label): last arrival \(lastArrival) is after requested \(date)")
    }
}

if !failures.isEmpty {
    for failure in failures {
        fputs("FAIL: \(failure)\n", stderr)
    }
    exit(1)
}
```

- [ ] **Step 2: Run harness to verify it fails on current implementation**

Run:

```bash
swiftc \
  Shared/Util/SQLite.swift \
  Shared/Extensions/Date.swift \
  Shared/Util/DateTime.swift \
  Shared/Models/Trip.swift \
  Shared/Controllers/OfflineRoutingEngine.swift \
  Scripts/offline-routing-check.swift \
  -o /tmp/transi-offline-routing-check
perl -e 'alarm 30; exec @ARGV' /tmp/transi-offline-routing-check
```

Expected: FAIL. Current failures should include regional/long timeouts or counts below minimum, and the compile should fail until `OfflineRoutingEngine.planTrip(...arrivalDeparture:)` exists.

- [ ] **Step 3: Commit harness**

```bash
git add Scripts/offline-routing-check.swift
git commit -m "test: add offline routing verification harness"
```

## Task 2: Add Internal Routing Types

**Files:**
- Create: `Shared/Controllers/OfflineRoutingTypes.swift`
- Modify: `Transi.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write compile check for missing types**

Temporarily add this at the top of `Scripts/offline-routing-check.swift` after imports:

```swift
let _routingTypeCompileCheck: OfflineRoutingMode = .departure
```

Run the harness compile command from Task 1.

Expected: FAIL with `cannot find type 'OfflineRoutingMode' in scope`.

- [ ] **Step 2: Create routing types**

Create `Shared/Controllers/OfflineRoutingTypes.swift`:

```swift
import Foundation

enum OfflineRoutingMode {
    case departure
    case arrival
}

struct OfflineStop: Hashable {
    let id: String
    let feed: String
    let name: String
    let normalizedName: String
    let lat: Double
    let lon: Double
    let platform: String?
    let zone: String?
}

struct OfflineStopTime {
    let tripKey: String
    let stopId: String
    let sequence: Int
    let arrival: Int
    let departure: Int
}

struct OfflineTrip {
    let key: String
    let id: String
    let feed: String
    let routeShortName: String
    let routeType: Int
    let headsign: String
    let serviceId: String
    let stopTimes: [OfflineStopTime]
}

struct OfflineWalkLink: Hashable {
    let fromStopId: String
    let toStopId: String
    let seconds: Int
}

struct OfflineRoutingLabel: Hashable {
    let stopId: String
    let time: Int
    let transfers: Int
    let walkSeconds: Int
    let previousIndex: Int?
    let tripKey: String?
    let boardStopId: String?
    let alightStopId: String?
    let boardTime: Int?
    let alightTime: Int?
    let walkLink: OfflineWalkLink?
}

struct OfflineJourneyCandidate {
    let labels: [OfflineRoutingLabel]
    let parts: [Part]
    let zones: Set<String>
    let arrivalSeconds: Int
    let departureSeconds: Int
    let transferCount: Int
    let walkSeconds: Int
}

struct OfflineGroupedJourney {
    let representative: OfflineJourneyCandidate
    let alternatives: [OfflineJourneyCandidate]
}
```

- [ ] **Step 3: Add new file to app target**

Add `OfflineRoutingTypes.swift` to the `Shared/Controllers` group and main `Transi` target sources in `Transi.xcodeproj/project.pbxproj`, following the existing `OfflineRoutingEngine.swift` file reference and source build-file pattern.

- [ ] **Step 4: Remove temporary compile check and verify compile**

Remove `_routingTypeCompileCheck` from the script.

Run:

```bash
xcodebuild -project Transi.xcodeproj -scheme Transi -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' build
```

Expected: PASS or fail only for unrelated pre-existing project issues. If destination is unavailable, use `xcodebuild -list -project Transi.xcodeproj` and choose an available iOS simulator.

- [ ] **Step 5: Commit types**

```bash
git add Shared/Controllers/OfflineRoutingTypes.swift Transi.xcodeproj/project.pbxproj
git commit -m "feat: add offline routing internal types"
```

## Task 3: Implement Stop Resolver And Walking Links

**Files:**
- Create: `Shared/Controllers/OfflineStopResolver.swift`
- Modify: `Transi.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing resolver harness section**

Add this assertion block to `Scripts/offline-routing-check.swift` before route cases:

```swift
let resolver = OfflineStopResolver(baseDb: baseDb)
let hlavna = resolver.resolveStops(named: "Hlavná stanica", maxWalkDuration: 15)
let petrzalka = resolver.resolveStops(named: "Stn. Petržalka", maxWalkDuration: 15)
let pezinok = resolver.resolveStops(named: "Pezinok, Žel. stanica", maxWalkDuration: 15)
let resolverChecks: [(String, [OfflineStop], String)] = [
    ("Hlavná stanica", hlavna, "Bratislava hl.st."),
    ("Stn. Petržalka", petrzalka, "Bratislava-Petržalka"),
    ("Pezinok, Žel. stanica", pezinok, "Pezinok"),
]
for (label, stops, expectedName) in resolverChecks where !stops.contains(where: { $0.name == expectedName }) {
    failures.append("\(label): missing alias candidate \(expectedName)")
}
```

Run the harness compile command.

Expected: FAIL with missing `OfflineStopResolver`.

- [ ] **Step 2: Implement resolver**

Create `Shared/Controllers/OfflineStopResolver.swift`:

```swift
import Foundation

final class OfflineStopResolver {
    private let baseDb: SQLiteDatabase
    private let aliases: [String: [String]] = [
        "Autobusová stanica": ["Bratislava, AS", "Bratislava, Autobusová stanica"],
        "Hlavná stanica": ["Bratislava hl.st.", "Bratislava hlavná stanica", "Bratislava, Hlavná stanica"],
        "Stn. Petržalka": ["Bratislava-Petržalka", "Bratislava, Petržalka"],
        "Stn. Vajnory": ["Bratislava-Vajnory"],
        "Stn. Vinohrady": ["Bratislava-Vinohrady"],
        "Stn. Nové Mesto": ["Bratislava-Nové Mesto"],
        "Pezinok, Žel. stanica": ["Pezinok"],
        "Senec, Žel. stanica": ["Senec"],
        "Miloslavov, Žel. stanica": ["Miloslavov"],
        "Rovinka": ["Rovinka"],
    ]

    init(baseDb: SQLiteDatabase) {
        self.baseDb = baseDb
    }

    func resolveStops(named name: String, maxWalkDuration: Int) -> [OfflineStop] {
        let directNames = candidateNames(for: name)
        var seen = Set<String>()
        var result = [OfflineStop]()

        for candidate in directNames {
            for stop in queryStops(whereClause: "stop_name = ?", params: [candidate]) {
                if seen.insert(stop.id).inserted {
                    result.append(stop)
                }
            }
        }

        if result.isEmpty {
            for stop in queryStops(whereClause: "stop_name LIKE ?", params: ["%\(bareName(name))%"]) where stop.feed != "trains" {
                if seen.insert(stop.id).inserted {
                    result.append(stop)
                }
            }
        }

        if maxWalkDuration > 0 {
            let secondsLimit = maxWalkDuration * 60
            for seed in result {
                for nearby in nearbyStops(to: seed, secondsLimit: secondsLimit) {
                    if seen.insert(nearby.id).inserted {
                        result.append(nearby)
                    }
                }
            }
        }

        return result
    }

    func walkLinks(for stops: [OfflineStop], maxWalkDuration: Int) -> [OfflineWalkLink] {
        guard maxWalkDuration > 0 else { return [] }
        let secondsLimit = maxWalkDuration * 60
        var links = [OfflineWalkLink]()
        for stop in stops {
            for target in nearbyStops(to: stop, secondsLimit: secondsLimit) where target.id != stop.id {
                let seconds = walkSeconds(from: stop, to: target)
                if seconds <= secondsLimit {
                    links.append(OfflineWalkLink(fromStopId: stop.id, toStopId: target.id, seconds: seconds))
                }
            }
        }
        return links
    }

    private func candidateNames(for name: String) -> [String] {
        var names = [name]
        names.append("Bratislava, \(name)")
        names.append(contentsOf: aliases[name] ?? [])
        return Array(Set(names))
    }

    private func bareName(_ name: String) -> String {
        if let comma = name.firstIndex(of: ",") {
            return String(name[name.index(after: comma)...]).trimmingCharacters(in: .whitespaces)
        }
        return name
    }

    private func queryStops(whereClause: String, params: [Any]) -> [OfflineStop] {
        let rows = baseDb.query("""
            SELECT stop_id, feed, stop_name, stop_lat, stop_lon, platform_code, zone_id
            FROM stops
            WHERE \(whereClause)
        """, params: params)
        return rows.compactMap(mapStop)
    }

    private func nearbyStops(to stop: OfflineStop, secondsLimit: Int) -> [OfflineStop] {
        let maxMeters = Double(secondsLimit) * 1.33
        let latDelta = maxMeters / 111_000.0
        let lonDelta = maxMeters / max(1.0, 111_000.0 * cos(stop.lat * .pi / 180))
        let rows = baseDb.query("""
            SELECT stop_id, feed, stop_name, stop_lat, stop_lon, platform_code, zone_id
            FROM stops
            WHERE stop_lat BETWEEN ? AND ?
              AND stop_lon BETWEEN ? AND ?
        """, params: [stop.lat - latDelta, stop.lat + latDelta, stop.lon - lonDelta, stop.lon + lonDelta])
        return rows.compactMap(mapStop).filter { walkSeconds(from: stop, to: $0) <= secondsLimit }
    }

    private func mapStop(_ row: [String: Any]) -> OfflineStop? {
        guard let id = row["stop_id"] as? String,
              let feed = row["feed"] as? String,
              let name = row["stop_name"] as? String,
              let lat = row["stop_lat"] as? Double,
              let lon = row["stop_lon"] as? Double else {
            return nil
        }
        return OfflineStop(
            id: id,
            feed: feed,
            name: name,
            normalizedName: normalize(name),
            lat: lat,
            lon: lon,
            platform: row["platform_code"] as? String,
            zone: row["zone_id"] as? String
        )
    }

    private func normalize(_ name: String) -> String {
        name.replacingOccurrences(of: "Bratislava, ", with: "")
            .replacingOccurrences(of: "Rovinka, ", with: "")
            .replacingOccurrences(of: "Dunajská Lužná, ", with: "")
            .replacingOccurrences(of: "Miloslavov, ", with: "")
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "sk_SK"))
    }

    private func walkSeconds(from a: OfflineStop, to b: OfflineStop) -> Int {
        max(30, Int(haversineMeters(lat1: a.lat, lon1: a.lon, lat2: b.lat, lon2: b.lon) / 1.33))
    }

    private func haversineMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6371e3
        let phi1 = lat1 * .pi / 180
        let phi2 = lat2 * .pi / 180
        let dPhi = (lat2 - lat1) * .pi / 180
        let dLam = (lon2 - lon1) * .pi / 180
        let a = sin(dPhi / 2) * sin(dPhi / 2) + cos(phi1) * cos(phi2) * sin(dLam / 2) * sin(dLam / 2)
        return r * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
```

- [ ] **Step 3: Add file to app target**

Add `OfflineStopResolver.swift` to the `Shared/Controllers` group and main target sources in `Transi.xcodeproj/project.pbxproj`.

- [ ] **Step 4: Verify resolver checks pass**

Run the harness compile and execute command from Task 1.

Expected: resolver alias checks pass; route checks still fail because the router is not replaced yet.

- [ ] **Step 5: Commit resolver**

```bash
git add Shared/Controllers/OfflineStopResolver.swift Transi.xcodeproj/project.pbxproj Scripts/offline-routing-check.swift
git commit -m "feat: resolve offline GTFS stop aliases"
```

## Task 4: Build Routing Context Indexes

**Files:**
- Create: `Shared/Controllers/OfflineRoutingContext.swift`
- Modify: `Transi.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing context compile check**

Add to `Scripts/offline-routing-check.swift` after DB setup:

```swift
let contextDate = parser.date(from: "2026-06-02T08:00:00+02:00")!
let context = OfflineRoutingContext.build(scheduleDb: scheduleDb, baseDb: baseDb, date: contextDate, maxWalkDuration: 15)
if context.tripsByKey.isEmpty {
    failures.append("context: expected active trips")
}
```

Run the harness compile command.

Expected: FAIL with missing `OfflineRoutingContext`.

- [ ] **Step 2: Implement context loader**

Create `Shared/Controllers/OfflineRoutingContext.swift` with this API:

```swift
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
        let dayStart = Calendar.current.startOfDay(for: date)
        let dateString = dayStart.toString()
        let dayColumn = dayOfWeekColumn(for: dayStart)
        let stops = loadStops(baseDb: baseDb)
        let active = activeServiceIdsByFeed(scheduleDb: scheduleDb, date: dateString, dayColumn: dayColumn)
        let trips = loadTrips(scheduleDb: scheduleDb, activeServiceIdsByFeed: active)
        let walkLinks = buildWalkLinks(stops: Array(stops.values), maxWalkDuration: maxWalkDuration)
        var stopTimesByStop = [String: [OfflineStopTime]]()
        for trip in trips.values {
            for stopTime in trip.stopTimes {
                stopTimesByStop[stopTime.stopId, default: []].append(stopTime)
            }
        }
        for stopId in stopTimesByStop.keys {
            stopTimesByStop[stopId]?.sort { $0.departure < $1.departure }
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
                normalizedName: name,
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
        for (feed, ids) in activeServiceIdsByFeed where !ids.isEmpty {
            clauses.append("(t.feed = ? AND t.service_id IN (\(ids.map { _ in "?" }.joined(separator: ","))))")
            params.append(feed)
            params.append(contentsOf: Array(ids))
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
            let sorted = value.stopTimes.sorted { $0.sequence < $1.sequence }
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
        var links = [String: [OfflineWalkLink]]()
        for stop in stops {
            let maxMeters = Double(limit) * 1.33
            let candidates = stops.filter { other in
                other.id != stop.id &&
                abs(other.lat - stop.lat) < maxMeters / 111_000.0 &&
                abs(other.lon - stop.lon) < maxMeters / max(1.0, 111_000.0 * cos(stop.lat * .pi / 180))
            }
            for other in candidates {
                let seconds = max(30, Int(haversineMeters(lat1: stop.lat, lon1: stop.lon, lat2: other.lat, lon2: other.lon) / 1.33))
                if seconds <= limit {
                    links[stop.id, default: []].append(OfflineWalkLink(fromStopId: stop.id, toStopId: other.id, seconds: seconds))
                }
            }
        }
        return links
    }

    private static func dayOfWeekColumn(for date: Date) -> String {
        switch Calendar(identifier: .gregorian).component(.weekday, from: date) {
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
```

- [ ] **Step 3: Add file to app target**

Add `OfflineRoutingContext.swift` to `Transi.xcodeproj/project.pbxproj`.

- [ ] **Step 4: Verify context check passes**

Run the harness.

Expected: context check passes; route quality checks still fail.

- [ ] **Step 5: Commit context**

```bash
git add Shared/Controllers/OfflineRoutingContext.swift Transi.xcodeproj/project.pbxproj Scripts/offline-routing-check.swift
git commit -m "feat: build offline routing context indexes"
```

## Task 5: Implement Departure Router

**Files:**
- Create: `Shared/Controllers/OfflineTimetableRouter.swift`
- Modify: `Transi.xcodeproj/project.pbxproj`

- [ ] **Step 1: Keep harness as failing test**

Run:

```bash
perl -e 'alarm 30; exec @ARGV' /tmp/transi-offline-routing-check short_city train_station_pair regional_bus regional_train long_suburban
```

Expected: FAIL under current engine.

- [ ] **Step 2: Implement departure router API**

Create `Shared/Controllers/OfflineTimetableRouter.swift`:

```swift
import Foundation

final class OfflineTimetableRouter {
    private let context: OfflineRoutingContext

    init(context: OfflineRoutingContext) {
        self.context = context
    }

    func routeDeparture(
        originStopIds: Set<String>,
        destinationStopIds: Set<String>,
        departureSeconds: Int,
        maxTransfers: Int
    ) -> [OfflineJourneyCandidate] {
        var labels = [OfflineRoutingLabel]()
        var bestByRound = Array(repeating: [String: OfflineRoutingLabel](), count: maxTransfers + 2)
        var frontier = [OfflineRoutingLabel]()

        for stopId in originStopIds {
            let label = OfflineRoutingLabel(stopId: stopId, time: departureSeconds, transfers: 0, walkSeconds: 0, previousIndex: nil, tripKey: nil, boardStopId: nil, alightStopId: nil, boardTime: nil, alightTime: nil, walkLink: nil)
            labels.append(label)
            bestByRound[0][stopId] = label
            frontier.append(label)
        }

        var candidates = [OfflineJourneyCandidate]()
        for round in 0...maxTransfers {
            let expanded = expandDeparture(frontier: frontier, round: round, labels: &labels, bestByRound: &bestByRound, destinationStopIds: destinationStopIds, candidates: &candidates)
            frontier = expanded
            if frontier.isEmpty { break }
        }

        return candidates.sorted(by: departureSort).prefix(40).map { $0 }
    }

    private func expandDeparture(
        frontier: [OfflineRoutingLabel],
        round: Int,
        labels: inout [OfflineRoutingLabel],
        bestByRound: inout [[String: OfflineRoutingLabel]],
        destinationStopIds: Set<String>,
        candidates: inout [OfflineJourneyCandidate]
    ) -> [OfflineRoutingLabel] {
        var next = [OfflineRoutingLabel]()
        for label in frontier {
            let origins = walkingOrigins(from: label)
            for origin in origins {
                for stopTime in context.stopTimesByStopId[origin.stopId] ?? [] where stopTime.departure >= origin.time {
                    guard let trip = context.tripsByKey[stopTime.tripKey],
                          let boardIndex = trip.stopTimes.firstIndex(where: { $0.stopId == stopTime.stopId && $0.sequence == stopTime.sequence }) else {
                        continue
                    }
                    for alight in trip.stopTimes[(boardIndex + 1)...] {
                        let newLabel = OfflineRoutingLabel(
                            stopId: alight.stopId,
                            time: alight.arrival,
                            transfers: round,
                            walkSeconds: origin.walkSeconds,
                            previousIndex: labels.firstIndex(of: label),
                            tripKey: trip.key,
                            boardStopId: stopTime.stopId,
                            alightStopId: alight.stopId,
                            boardTime: stopTime.departure,
                            alightTime: alight.arrival,
                            walkLink: origin.walkLink
                        )
                        if isDominated(newLabel, by: bestByRound[min(round + 1, bestByRound.count - 1)][alight.stopId]) {
                            continue
                        }
                        labels.append(newLabel)
                        bestByRound[min(round + 1, bestByRound.count - 1)][alight.stopId] = newLabel
                        if destinationStopIds.contains(alight.stopId) {
                            if let candidate = buildCandidate(terminal: newLabel, allLabels: labels) {
                                candidates.append(candidate)
                            }
                        } else {
                            next.append(newLabel)
                        }
                    }
                }
            }
        }
        return next
    }

    private struct WalkOrigin {
        let stopId: String
        let time: Int
        let walkSeconds: Int
        let walkLink: OfflineWalkLink?
    }

    private func walkingOrigins(from label: OfflineRoutingLabel) -> [WalkOrigin] {
        var result = [WalkOrigin(stopId: label.stopId, time: label.time, walkSeconds: label.walkSeconds, walkLink: nil)]
        for link in context.walkLinksByStopId[label.stopId] ?? [] {
            result.append(WalkOrigin(stopId: link.toStopId, time: label.time + link.seconds, walkSeconds: label.walkSeconds + link.seconds, walkLink: link))
        }
        return result
    }

    private func isDominated(_ label: OfflineRoutingLabel, by existing: OfflineRoutingLabel?) -> Bool {
        guard let existing else { return false }
        return existing.time <= label.time &&
            existing.transfers <= label.transfers &&
            existing.walkSeconds <= label.walkSeconds
    }

    private func buildCandidate(terminal: OfflineRoutingLabel, allLabels: [OfflineRoutingLabel]) -> OfflineJourneyCandidate? {
        var chain = [OfflineRoutingLabel]()
        var current: OfflineRoutingLabel? = terminal
        while let label = current {
            chain.append(label)
            if let previous = label.previousIndex {
                current = allLabels[previous]
            } else {
                current = nil
            }
        }
        chain.reverse()
        let parts = mapParts(labels: chain)
        guard let first = parts.first, let last = parts.last else { return nil }
        let zones = Set(parts.flatMap { part -> [String] in
            [part.startStopName, part.endStopName].compactMap { _ in nil }
        })
        return OfflineJourneyCandidate(
            labels: chain,
            parts: parts,
            zones: zones,
            arrivalSeconds: Int(last.endArrival.timeIntervalSince(context.dayStart)),
            departureSeconds: Int(first.startDeparture.timeIntervalSince(context.dayStart)),
            transferCount: parts.filter { $0.routeType != 64 }.count - 1,
            walkSeconds: chain.last?.walkSeconds ?? 0
        )
    }

    private func mapParts(labels: [OfflineRoutingLabel]) -> [Part] {
        var parts = [Part]()
        for label in labels {
            if let link = label.walkLink,
               let from = context.stopsById[link.fromStopId],
               let to = context.stopsById[link.toStopId] {
                let dep = context.dayStart.addingTimeInterval(TimeInterval(label.time - link.seconds))
                let arr = context.dayStart.addingTimeInterval(TimeInterval(label.time))
                parts.append(Part(startStopName: from.name, endStopName: to.name, startStopCode: from.platform, endStopCode: to.platform, startDeparture: dep, endArrival: arr, routeType: 64, tripHeadsign: "Walk", routeShortName: nil))
            }
            guard let tripKey = label.tripKey,
                  let trip = context.tripsByKey[tripKey],
                  let board = label.boardStopId.flatMap({ context.stopsById[$0] }),
                  let alight = label.alightStopId.flatMap({ context.stopsById[$0] }),
                  let boardTime = label.boardTime,
                  let alightTime = label.alightTime else {
                continue
            }
            parts.append(Part(
                startStopName: board.name,
                endStopName: alight.name,
                startStopCode: board.platform,
                endStopCode: alight.platform,
                startDeparture: context.dayStart.addingTimeInterval(TimeInterval(boardTime)),
                endArrival: context.dayStart.addingTimeInterval(TimeInterval(alightTime)),
                routeType: trip.routeType,
                tripHeadsign: trip.headsign,
                routeShortName: trip.routeShortName
            ))
        }
        return parts
    }

    private func departureSort(_ lhs: OfflineJourneyCandidate, _ rhs: OfflineJourneyCandidate) -> Bool {
        if lhs.arrivalSeconds != rhs.arrivalSeconds { return lhs.arrivalSeconds < rhs.arrivalSeconds }
        if lhs.transferCount != rhs.transferCount { return lhs.transferCount < rhs.transferCount }
        if lhs.walkSeconds != rhs.walkSeconds { return lhs.walkSeconds < rhs.walkSeconds }
        return lhs.departureSeconds < rhs.departureSeconds
    }
}
```

After this implementation is in place, the Task 9 pruning constants must be applied before final verification. The required behavior is governed by the harness, not by preserving this exact implementation.

- [ ] **Step 3: Add file to app target**

Add `OfflineTimetableRouter.swift` to `Transi.xcodeproj/project.pbxproj`.

- [ ] **Step 4: Commit router shell**

```bash
git add Shared/Controllers/OfflineTimetableRouter.swift Transi.xcodeproj/project.pbxproj
git commit -m "feat: add offline timetable departure router"
```

## Task 6: Integrate New Router Into Engine

**Files:**
- Modify: `Shared/Controllers/OfflineRoutingEngine.swift`
- Modify: `Shared/Controllers/TimetableDatabase.swift`

- [ ] **Step 1: Verify current harness failure**

Run:

```bash
swiftc Shared/Util/SQLite.swift Shared/Extensions/Date.swift Shared/Util/DateTime.swift Shared/Models/Trip.swift Shared/Controllers/OfflineRoutingTypes.swift Shared/Controllers/OfflineStopResolver.swift Shared/Controllers/OfflineRoutingContext.swift Shared/Controllers/OfflineTimetableRouter.swift Shared/Controllers/OfflineRoutingEngine.swift Scripts/offline-routing-check.swift -o /tmp/transi-offline-routing-check
perl -e 'alarm 30; exec @ARGV' /tmp/transi-offline-routing-check
```

Expected: FAIL until `planTrip(...arrivalDeparture:)` is added and old BFS is bypassed.

- [ ] **Step 2: Replace engine public method**

Modify `Shared/Controllers/OfflineRoutingEngine.swift` so its public entry point is:

```swift
func planTrip(
    fromName: String,
    toName: String,
    date: Date,
    arrivalDeparture: ArrivalDeparture,
    maxTransfers: Int,
    maxWalkDuration: Int
) -> [Journey] {
    let resolver = OfflineStopResolver(baseDb: baseDb)
    let fromStops = resolver.resolveStops(named: fromName, maxWalkDuration: maxWalkDuration)
    let toStops = resolver.resolveStops(named: toName, maxWalkDuration: maxWalkDuration)
    guard !fromStops.isEmpty, !toStops.isEmpty else { return [] }

    let context = OfflineRoutingContext.build(
        scheduleDb: scheduleDb,
        baseDb: baseDb,
        date: date,
        maxWalkDuration: maxWalkDuration
    )
    let seconds = max(0, Int(date.timeIntervalSince(context.dayStart)))
    let router = OfflineTimetableRouter(context: context)
    let candidates: [OfflineJourneyCandidate]

    switch arrivalDeparture {
    case .departure:
        candidates = router.routeDeparture(
            originStopIds: Set(fromStops.map(\.id)),
            destinationStopIds: Set(toStops.map(\.id)),
            departureSeconds: seconds,
            maxTransfers: maxTransfers
        )
    case .arrival:
        candidates = router.routeArrival(
            originStopIds: Set(fromStops.map(\.id)),
            destinationStopIds: Set(toStops.map(\.id)),
            arrivalSeconds: seconds,
            maxTransfers: maxTransfers
        )
    }

    return OfflineJourneyGrouper()
        .group(candidates)
        .map { Journey(id: UUID().uuidString, parts: $0.representative.parts, zones: Array($0.representative.zones).sorted()) }
}
```

Temporarily add this fallback until Task 7:

```swift
extension OfflineTimetableRouter {
    func routeArrival(originStopIds: Set<String>, destinationStopIds: Set<String>, arrivalSeconds: Int, maxTransfers: Int) -> [OfflineJourneyCandidate] {
        return []
    }
}
```

Temporarily add this fallback until Task 8:

```swift
final class OfflineJourneyGrouper {
    func group(_ candidates: [OfflineJourneyCandidate]) -> [OfflineGroupedJourney] {
        candidates.map { OfflineGroupedJourney(representative: $0, alternatives: []) }
    }
}
```

- [ ] **Step 3: Pass arrival mode through database**

Modify `Shared/Controllers/TimetableDatabase.swift`:

```swift
let journeys = engine.planTrip(
    fromName: fromName,
    toName: toName,
    date: date,
    arrivalDeparture: arrivalDeparture,
    maxTransfers: maxTransfers,
    maxWalkDuration: maxWalkDuration
)
```

- [ ] **Step 4: Verify departure cases improve**

Run:

```bash
perl -e 'alarm 30; exec @ARGV' /tmp/transi-offline-routing-check short_city train_station_pair regional_bus regional_train
```

Expected: PASS for at least `train_station_pair`, `regional_bus`, and no pre-request departures. If `short_city` or `regional_train` fails count thresholds, continue to Task 7 and tune there.

- [ ] **Step 5: Commit integration**

```bash
git add Shared/Controllers/OfflineRoutingEngine.swift Shared/Controllers/TimetableDatabase.swift
git commit -m "feat: route offline trips through timetable router"
```

## Task 7: Implement Arrival Mode And Cross-Midnight Search

**Files:**
- Modify: `Shared/Controllers/OfflineTimetableRouter.swift`
- Modify: `Shared/Controllers/OfflineRoutingContext.swift`
- Modify: `Shared/Controllers/OfflineRoutingEngine.swift`

- [ ] **Step 1: Verify arrival test fails**

Run:

```bash
perl -e 'alarm 30; exec @ARGV' /tmp/transi-offline-routing-check arrival_city late_short
```

Expected: FAIL because arrival mode returns no candidates or late-night options are insufficient.

- [ ] **Step 2: Add reverse indexes**

Extend `OfflineRoutingContext` with:

```swift
let reverseStopTimesByStopId: [String: [OfflineStopTime]]
```

Populate it from `stopTimesByStop` sorted by descending arrival:

```swift
var reverseStopTimesByStop = stopTimesByStop
for stopId in reverseStopTimesByStop.keys {
    reverseStopTimesByStop[stopId]?.sort { $0.arrival > $1.arrival }
}
```

- [ ] **Step 3: Implement routeArrival**

Replace the temporary `routeArrival` fallback with reverse-time routing. Add this method to `OfflineTimetableRouter`:

```swift
func routeArrival(
    originStopIds: Set<String>,
    destinationStopIds: Set<String>,
    arrivalSeconds: Int,
    maxTransfers: Int
) -> [OfflineJourneyCandidate] {
    var labels = [OfflineRoutingLabel]()
    var bestByRound = Array(repeating: [String: OfflineRoutingLabel](), count: maxTransfers + 2)
    var frontier = [OfflineRoutingLabel]()

    for stopId in destinationStopIds {
        let label = OfflineRoutingLabel(stopId: stopId, time: arrivalSeconds, transfers: 0, walkSeconds: 0, previousIndex: nil, tripKey: nil, boardStopId: nil, alightStopId: nil, boardTime: nil, alightTime: nil, walkLink: nil)
        labels.append(label)
        bestByRound[0][stopId] = label
        frontier.append(label)
    }

    var candidates = [OfflineJourneyCandidate]()
    for round in 0...maxTransfers {
        var next = [OfflineRoutingLabel]()
        for label in frontier {
            let destinations = reverseWalkingDestinations(from: label)
            for destination in destinations {
                for stopTime in context.reverseStopTimesByStopId[destination.stopId] ?? [] where stopTime.arrival <= destination.time {
                    guard let trip = context.tripsByKey[stopTime.tripKey],
                          let alightIndex = trip.stopTimes.firstIndex(where: { $0.stopId == stopTime.stopId && $0.sequence == stopTime.sequence }) else {
                        continue
                    }
                    for board in trip.stopTimes[..<alightIndex].reversed() {
                        let newLabel = OfflineRoutingLabel(
                            stopId: board.stopId,
                            time: board.departure,
                            transfers: round,
                            walkSeconds: destination.walkSeconds,
                            previousIndex: labels.firstIndex(of: label),
                            tripKey: trip.key,
                            boardStopId: board.stopId,
                            alightStopId: stopTime.stopId,
                            boardTime: board.departure,
                            alightTime: stopTime.arrival,
                            walkLink: destination.walkLink
                        )
                        if isReverseDominated(newLabel, by: bestByRound[min(round + 1, bestByRound.count - 1)][board.stopId]) {
                            continue
                        }
                        labels.append(newLabel)
                        bestByRound[min(round + 1, bestByRound.count - 1)][board.stopId] = newLabel
                        if originStopIds.contains(board.stopId) {
                            if let candidate = buildCandidate(terminal: newLabel, allLabels: labels) {
                                candidates.append(candidate)
                            }
                        } else {
                            next.append(newLabel)
                        }
                    }
                }
            }
        }
        frontier = next
        if frontier.isEmpty { break }
    }

    return candidates.sorted {
        if $0.departureSeconds != $1.departureSeconds { return $0.departureSeconds > $1.departureSeconds }
        if $0.transferCount != $1.transferCount { return $0.transferCount < $1.transferCount }
        return $0.walkSeconds < $1.walkSeconds
    }
    .prefix(40)
    .map { $0 }
}
```

Add these helpers to the same file:

```swift
private func reverseWalkingDestinations(from label: OfflineRoutingLabel) -> [WalkOrigin] {
    var result = [WalkOrigin(stopId: label.stopId, time: label.time, walkSeconds: label.walkSeconds, walkLink: nil)]
    for links in context.walkLinksByStopId.values {
        for link in links where link.toStopId == label.stopId {
            result.append(WalkOrigin(stopId: link.fromStopId, time: label.time - link.seconds, walkSeconds: label.walkSeconds + link.seconds, walkLink: link))
        }
    }
    return result
}

private func isReverseDominated(_ label: OfflineRoutingLabel, by existing: OfflineRoutingLabel?) -> Bool {
    guard let existing else { return false }
    return existing.time >= label.time &&
        existing.transfers <= label.transfers &&
        existing.walkSeconds <= label.walkSeconds
}
```

- [ ] **Step 4: Add next-day context for late trips**

In `OfflineRoutingEngine.planTrip`, call context/router for the requested date and the next day when fewer than 5 grouped candidates are found:

```swift
var allCandidates = candidates
if allCandidates.count < 8 {
    let nextDate = Calendar.current.date(byAdding: .day, value: 1, to: date)!
    let nextContext = OfflineRoutingContext.build(scheduleDb: scheduleDb, baseDb: baseDb, date: nextDate, maxWalkDuration: maxWalkDuration)
    let nextRouter = OfflineTimetableRouter(context: nextContext)
    allCandidates.append(contentsOf: nextRouter.routeDeparture(
        originStopIds: Set(fromStops.map(\.id)),
        destinationStopIds: Set(toStops.map(\.id)),
        departureSeconds: 0,
        maxTransfers: maxTransfers
    ))
}
```

Keep filtering so departure-mode candidates do not start before the original requested `date`.

- [ ] **Step 5: Verify arrival and late-night**

Run:

```bash
perl -e 'alarm 30; exec @ARGV' /tmp/transi-offline-routing-check arrival_city late_short
```

Expected: PASS.

- [ ] **Step 6: Commit arrival/cross-midnight**

```bash
git add Shared/Controllers/OfflineTimetableRouter.swift Shared/Controllers/OfflineRoutingContext.swift Shared/Controllers/OfflineRoutingEngine.swift
git commit -m "feat: support offline arrival and overnight routing"
```

## Task 8: Implement Equivalent Journey Grouping

**Files:**
- Create: `Shared/Controllers/OfflineJourneyGrouper.swift`
- Modify: `Shared/Controllers/OfflineRoutingEngine.swift`
- Modify: `Transi.xcodeproj/project.pbxproj`

- [ ] **Step 1: Add grouping assertions to harness**

Add after route result checks:

```swift
let signatures = journeys.map { journey in
    (journey.parts ?? [])
        .filter { $0.routeType != 64 }
        .compactMap(\.routeShortName)
        .joined(separator: ">")
}
let uniqueSignatures = Set(signatures)
if uniqueSignatures.count < min(signatures.count, 2) {
    failures.append("\(check.label): grouped output collapsed all line signatures")
}
```

Run `short_city medium_city long_suburban`.

Expected: FAIL or expose duplicate/over-collapsed behavior until grouper exists.

- [ ] **Step 2: Implement grouper**

Create `Shared/Controllers/OfflineJourneyGrouper.swift`:

```swift
import Foundation

final class OfflineJourneyGrouper {
    func group(_ candidates: [OfflineJourneyCandidate]) -> [OfflineGroupedJourney] {
        var groups = [String: [OfflineJourneyCandidate]]()
        for candidate in candidates {
            groups[groupKey(candidate), default: []].append(candidate)
        }
        return groups.values.map { group in
            let sorted = group.sorted(by: rank)
            return OfflineGroupedJourney(representative: sorted[0], alternatives: Array(sorted.dropFirst()))
        }
        .sorted { rank($0.representative, $1.representative) }
    }

    private func groupKey(_ candidate: OfflineJourneyCandidate) -> String {
        let transitParts = candidate.parts.filter { $0.routeType != 64 }
        let lines = transitParts.compactMap(\.routeShortName).joined(separator: ">")
        let bucketedArrival = candidate.arrivalSeconds / 180
        let first = candidate.parts.first?.startStopName ?? ""
        let last = candidate.parts.last?.endStopName ?? ""
        return "\(first)|\(last)|\(lines)|\(bucketedArrival)"
    }

    private func rank(_ lhs: OfflineJourneyCandidate, _ rhs: OfflineJourneyCandidate) -> Bool {
        if lhs.arrivalSeconds != rhs.arrivalSeconds { return lhs.arrivalSeconds < rhs.arrivalSeconds }
        if lhs.transferCount != rhs.transferCount { return lhs.transferCount < rhs.transferCount }
        if lhs.walkSeconds != rhs.walkSeconds { return lhs.walkSeconds < rhs.walkSeconds }
        return lhs.departureSeconds < rhs.departureSeconds
    }
}
```

- [ ] **Step 3: Remove temporary grouper from engine**

Delete the temporary `OfflineJourneyGrouper` fallback from `OfflineRoutingEngine.swift`.

- [ ] **Step 4: Add file to app target**

Add `OfflineJourneyGrouper.swift` to `Transi.xcodeproj/project.pbxproj`.

- [ ] **Step 5: Verify grouping does not reduce meaningful counts below thresholds**

Run:

```bash
perl -e 'alarm 30; exec @ARGV' /tmp/transi-offline-routing-check
```

Expected: all deterministic checks pass or only count thresholds fail due to router breadth, which Task 9 tunes.

- [ ] **Step 6: Commit grouper**

```bash
git add Shared/Controllers/OfflineJourneyGrouper.swift Shared/Controllers/OfflineRoutingEngine.swift Transi.xcodeproj/project.pbxproj Scripts/offline-routing-check.swift
git commit -m "feat: group equivalent offline journeys"
```

## Task 9: Tune Breadth, Ranking, And Performance

**Files:**
- Modify: `Shared/Controllers/OfflineTimetableRouter.swift`
- Modify: `Shared/Controllers/OfflineRoutingContext.swift`
- Modify: `Scripts/offline-routing-check.swift`

- [ ] **Step 1: Run full failing/pass matrix**

Run:

```bash
perl -e 'alarm 45; exec @ARGV' /tmp/transi-offline-routing-check
```

Expected: PASS. If any case fails, use the printed count, elapsed time, and missing line data to tune one variable at a time.

- [ ] **Step 2: Add pruning constants**

In `OfflineTimetableRouter`, add:

```swift
private let maxCandidatesPerStopPerRound = 4
private let maxReturnedCandidates = 60
private let maxBoardingsPerStopExpansion = 80
```

Use these limits when appending `next` labels and candidates. Keep lower-arrival, lower-transfer, lower-walk labels first.

- [ ] **Step 3: Add route breadth before grouping**

When expanding from a stop, keep multiple trips per line sequence instead of one earliest-only trip:

```swift
var boardingsByLine = [String: Int]()
for stopTime in context.stopTimesByStopId[origin.stopId] ?? [] where stopTime.departure >= origin.time {
    guard let trip = context.tripsByKey[stopTime.tripKey] else { continue }
    let count = boardingsByLine[trip.routeShortName, default: 0]
    if count >= 3 { continue }
    boardingsByLine[trip.routeShortName] = count + 1
    // existing expansion
}
```

- [ ] **Step 4: Verify under-5s target**

Run each case independently:

```bash
for label in short_city medium_city train_station_pair regional_bus regional_train long_suburban late_short arrival_city; do
  perl -e 'alarm 10; exec @ARGV' /tmp/transi-offline-routing-check "$label" || exit 1
done
```

Expected: every case passes and prints elapsed under 5000ms.

- [ ] **Step 5: Commit tuning**

```bash
git add Shared/Controllers/OfflineTimetableRouter.swift Shared/Controllers/OfflineRoutingContext.swift Scripts/offline-routing-check.swift
git commit -m "perf: tune offline routing breadth and pruning"
```

## Task 10: Add Online Comparison Harness

**Files:**
- Create: `Scripts/compare-offline-online.mjs`

- [ ] **Step 1: Write harness**

Create `Scripts/compare-offline-online.mjs`:

```javascript
import fs from 'node:fs'
import { spawnSync } from 'node:child_process'

const stops = JSON.parse(fs.readFileSync('/Users/magic_sk/Developer/js/api/data/stops.json', 'utf8'))
const xcconfig = fs.readFileSync('Release.xcconfig', 'utf8')
const config = {}
for (const line of xcconfig.split(/\r?\n/)) {
  const match = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*?)\s*$/)
  if (match) config[match[1]] = match[2].replaceAll('/$()/', '//')
}

const S_USER_AGENT = 'ProdProd/204 CFNetwork/3826.600.41 Darwin/24.6.0'
const G_USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36'

const cases = [
  { label: 'short_city', from: 'Hronská', to: 'Most SNP', iso: '2026-06-02T08:00:00+02:00' },
  { label: 'medium_city', from: 'Zlaté piesky', to: 'Hlavná stanica', iso: '2026-06-02T08:00:00+02:00' },
  { label: 'train_station_pair', from: 'Hlavná stanica', to: 'Stn. Petržalka', iso: '2026-06-02T08:00:00+02:00' },
  { label: 'regional_bus', from: 'Autobusová stanica', to: 'Rovinka, Obecný úrad', iso: '2026-06-02T08:00:00+02:00' },
  { label: 'regional_train', from: 'Hlavná stanica', to: 'Pezinok, Žel. stanica', iso: '2026-06-02T08:00:00+02:00' },
  { label: 'long_suburban', from: 'Most SNP', to: 'Senec, Žel. stanica', iso: '2026-06-02T08:00:00+02:00' },
  { label: 'late_short', from: 'Hronská', to: 'Most SNP', iso: '2026-06-02T23:30:00+02:00' },
]

function stopByName(name) {
  const stop = stops.find((s) => s.name === name)
  if (!stop) throw new Error(`Missing stop: ${name}`)
  return stop
}

function fmt(dateLike) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Bratislava',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).formatToParts(new Date(dateLike))
  const byType = Object.fromEntries(parts.map((p) => [p.type, p.value]))
  return `${byType.year}-${byType.month}-${byType.day} ${byType.hour}:${byType.minute}`
}

function localDateParts(iso) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Bratislava',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).formatToParts(new Date(iso))
  const byType = Object.fromEntries(parts.map((p) => [p.type, p.value]))
  return { ymdDash: `${byType.year}-${byType.month}-${byType.day}`, time: `${byType.hour}:${byType.minute}` }
}

function summarizeRJourney(journey) {
  const parts = journey.parts ?? []
  return {
    departure: parts[0]?.start_departure ? fmt(parts[0].start_departure) : null,
    arrival: parts.at(-1)?.end_arrival ? fmt(parts.at(-1).end_arrival) : null,
    lines: parts.filter((p) => p.route_type !== 64).map((p) => p.route_short_name).filter(Boolean),
  }
}

function iLineNames(journey) {
  if (!journey.lines || !journey.linesMapping) return []
  return journey.linesMapping.map((lineIndex) => {
    const line = journey.lines[lineIndex]
    const name = line?.find((item) => typeof item === 'string' && item.trim())
    return typeof name === 'string' ? name : null
  })
}

function summarizeIJourney(journey) {
  return {
    departure: fmt(journey.departure.date),
    arrival: fmt(journey.arrival.date),
    lines: iLineNames(journey).filter(Boolean),
  }
}

async function fetchJson(url, options) {
  const response = await fetch(url, options)
  const text = await response.text()
  return { status: response.status, json: text ? JSON.parse(text) : null }
}

async function getSession() {
  const body = JSON.stringify({ installation: 'codex-offline-compare', language: 'en', platform: 2 })
  const result = await fetchJson(`${config.B_API_URL}/mobile/v1/startup`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-api-key': config.B_API_KEY, 'User-Agent': S_USER_AGENT },
    body,
  })
  if (result.status !== 200 || !result.json?.session) throw new Error(`startup failed: ${result.status}`)
  return result.json.session
}

async function fetchR(c, session) {
  const from = stopByName(c.from)
  const to = stopByName(c.to)
  const body = JSON.stringify({
    org_id: 120,
    max_walk_duration: 15,
    max_transfers: 3,
    search_to_hours: 2,
    search_from: c.iso,
    from_station_id: [from.station_id],
    to_station_id: [to.station_id],
  })
  const result = await fetchJson(`${config.R_API_URL}/mobile/v1/raptor/`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-api-key': config.R_API_KEY, 'x-session': session, 'User-Agent': S_USER_AGENT },
    body,
  })
  return { status: result.status, count: result.json?.journey?.length ?? 0, journeys: (result.json?.journey ?? []).slice(0, 5).map(summarizeRJourney) }
}

async function fetchI(c) {
  const from = stopByName(c.from)
  const to = stopByName(c.to)
  const p = localDateParts(c.iso)
  const params = new URLSearchParams({
    v: '7',
    a: `g${from.id}`,
    b: `g${to.id}`,
    pd: p.ymdDash,
    pt: p.time,
    pa: '0',
    pl: '1.0-4.0',
    pp: '0',
    pc: '0',
    format: '0',
    op: 'Planner',
  })
  const result = await fetchJson(`${config.I_API_URL}/ba/api/cepo?${params}`, { headers: { 'User-Agent': G_USER_AGENT } })
  return { status: result.status, count: result.json?.journeys?.length ?? 0, journeys: (result.json?.journeys ?? []).slice(0, 5).map(summarizeIJourney) }
}

const session = await getSession()
for (const c of cases) {
  const offline = spawnSync('/tmp/transi-offline-routing-check', [c.label], { encoding: 'utf8' })
  if (offline.status !== 0) {
    console.error(`offline ${c.label} failed`)
    console.error(offline.stderr)
    process.exit(offline.status ?? 1)
  }
  const [r, i] = await Promise.all([fetchR(c, session), fetchI(c)])
  console.log(JSON.stringify({ label: c.label, offline: offline.stdout.trim(), r, i }))
}
```

- [ ] **Step 2: Run harness**

Run:

```bash
node Scripts/compare-offline-online.mjs
```

Expected: every line is JSON with `offline`, `r`, and `i` fields. The offline harness status must be zero for every case, and R/I statuses should be `200`.

- [ ] **Step 3: Commit comparison harness**

```bash
git add Scripts/compare-offline-online.mjs
git commit -m "test: add offline online route comparison harness"
```

## Task 11: Final Verification

**Files:**
- No new files expected.

- [ ] **Step 1: Run deterministic offline checks**

```bash
swiftc \
  Shared/Util/SQLite.swift \
  Shared/Extensions/Date.swift \
  Shared/Util/DateTime.swift \
  Shared/Models/Trip.swift \
  Shared/Controllers/OfflineRoutingTypes.swift \
  Shared/Controllers/OfflineStopResolver.swift \
  Shared/Controllers/OfflineRoutingContext.swift \
  Shared/Controllers/OfflineTimetableRouter.swift \
  Shared/Controllers/OfflineJourneyGrouper.swift \
  Shared/Controllers/OfflineRoutingEngine.swift \
  Scripts/offline-routing-check.swift \
  -o /tmp/transi-offline-routing-check
perl -e 'alarm 45; exec @ARGV' /tmp/transi-offline-routing-check
```

Expected: PASS, every printed elapsed time under 5000ms.

- [ ] **Step 2: Run app build**

```bash
xcodebuild -project Transi.xcodeproj -scheme Transi -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' build
```

Expected: PASS.

- [ ] **Step 3: Run online comparison**

```bash
node Scripts/compare-offline-online.mjs
```

Expected: offline meaningful grouped counts are at least online combined counts for the measured cases, or any exception is explained by grouped equivalent transfer variants.

- [ ] **Step 4: Inspect git status**

```bash
git status --short
```

Expected: only intentional files are modified.

- [ ] **Step 5: Final commit if needed**

If verification required small final fixes:

```bash
git add Shared/Controllers Scripts Transi.xcodeproj/project.pbxproj
git commit -m "feat: replace offline trip planner router"
```

## Notes For Execution

- Do not revert existing dirty changes unless the user explicitly asks.
- Do not preserve the current BFS if it blocks the under-5-second target.
- If the first router implementation still times out, optimize indexes before broadening search.
- Keep the app-facing `[Journey]` mapping stable until UI work for grouped transfer alternatives is requested.
- Use exact harness failures as the source of truth; do not tune by anecdotal route quality.
