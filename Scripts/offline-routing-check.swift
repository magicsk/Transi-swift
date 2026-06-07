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
    let minUniqueLineSignatures: Int
    let requiredActiveFeed: String?

    init(
        label: String,
        from: String,
        to: String,
        iso: String,
        mode: ArrivalDeparture,
        minJourneys: Int,
        maxMs: Int,
        requiredLines: Set<String>,
        minUniqueLineSignatures: Int = 0,
        requiredActiveFeed: String? = nil
    ) {
        self.label = label
        self.from = from
        self.to = to
        self.iso = iso
        self.mode = mode
        self.minJourneys = minJourneys
        self.maxMs = maxMs
        self.requiredLines = requiredLines
        self.minUniqueLineSignatures = minUniqueLineSignatures
        self.requiredActiveFeed = requiredActiveFeed
    }
}

let cases: [CheckCase] = [
    CheckCase(label: "short_city", from: "Hronská", to: "Most SNP", iso: "2026-06-02T08:00:00+02:00", mode: .departure, minJourneys: 5, maxMs: 5000, requiredLines: ["70"], minUniqueLineSignatures: 2),
    CheckCase(label: "medium_city", from: "Zlaté piesky", to: "Hlavná stanica", iso: "2026-06-02T08:00:00+02:00", mode: .departure, minJourneys: 5, maxMs: 5000, requiredLines: ["61"]),
    CheckCase(label: "train_station_pair", from: "Hlavná stanica", to: "Stn. Petržalka", iso: "2026-06-02T08:00:00+02:00", mode: .departure, minJourneys: 5, maxMs: 5000, requiredLines: ["93"]),
    CheckCase(label: "regional_bus", from: "Autobusová stanica", to: "Rovinka, Obecný úrad", iso: "2026-06-02T08:00:00+02:00", mode: .departure, minJourneys: 5, maxMs: 5000, requiredLines: ["725", "727", "737"], requiredActiveFeed: "regional"),
    CheckCase(label: "regional_train", from: "Hlavná stanica", to: "Pezinok, Žel. stanica", iso: "2026-06-02T08:00:00+02:00", mode: .departure, minJourneys: 4, maxMs: 5000, requiredLines: ["R50", "S50"]),
    CheckCase(label: "long_suburban", from: "Most SNP", to: "Senec, Žel. stanica", iso: "2026-06-02T08:00:00+02:00", mode: .departure, minJourneys: 4, maxMs: 5000, requiredLines: ["S60", "620"]),
    CheckCase(label: "late_short", from: "Hronská", to: "Most SNP", iso: "2026-06-02T23:30:00+02:00", mode: .departure, minJourneys: 3, maxMs: 5000, requiredLines: ["N70"]),
    CheckCase(label: "arrival_city", from: "Hronská", to: "Most SNP", iso: "2026-06-02T08:40:00+02:00", mode: .arrival, minJourneys: 3, maxMs: 5000, requiredLines: ["70"]),
    CheckCase(label: "overnight_departure", from: "Hronská", to: "Most SNP", iso: "2026-06-03T00:30:00+02:00", mode: .departure, minJourneys: 1, maxMs: 5000, requiredLines: ["N70"]),
    CheckCase(label: "overnight_arrival", from: "Hronská", to: "Most SNP", iso: "2026-06-03T00:45:00+02:00", mode: .arrival, minJourneys: 1, maxMs: 5000, requiredLines: ["N70"]),
    CheckCase(label: "early_morning_departure", from: "Hronská", to: "Most SNP", iso: "2026-06-03T04:59:00+02:00", mode: .departure, minJourneys: 1, maxMs: 5000, requiredLines: ["72"]),
]

@main
enum OfflineRoutingCheck {
    static func main() {
        let selected = Set(CommandLine.arguments.dropFirst())
        let knownLabels = Set(cases.map(\.label))
        let unknownLabels = selected.subtracting(knownLabels)

        if !unknownLabels.isEmpty {
            for label in unknownLabels.sorted() {
                fputs("FAIL: unknown case label \(label)\n", stderr)
            }
            exit(1)
        }

        let basePath = ProcessInfo.processInfo.environment["TRANSI_BASE_DB"] ?? "/Users/magic_sk/Developer/js/api/public/timetable/base.db"
        let schedulePath = ProcessInfo.processInfo.environment["TRANSI_SCHEDULE_DB"] ?? "/Users/magic_sk/Developer/js/api/public/timetable/schedule.db"

        guard let baseDb = SQLiteDatabase(path: basePath), let scheduleDb = SQLiteDatabase(path: schedulePath) else {
            fatalError("Failed to open timetable databases")
        }
        let escapedBasePath = basePath.replacingOccurrences(of: "'", with: "''")
        scheduleDb.execute("ATTACH DATABASE '\(escapedBasePath)' AS base")

        let parser = ISO8601DateFormatter()
        parser.formatOptions = [.withInternetDateTime]
        var failures = [String]()

        let contextDate = parser.date(from: "2026-06-02T08:00:00+02:00")!
        let context = OfflineRoutingContext.build(scheduleDb: scheduleDb, baseDb: baseDb, date: contextDate, maxWalkDuration: 15)
        if context.tripsByKey.isEmpty {
            failures.append("context: expected active trips")
        }
        if context.stopsById.isEmpty {
            failures.append("context: expected stops")
        }
        if context.stopTimesByStopId.isEmpty {
            failures.append("context: expected stop time index")
        }
        if context.walkLinksByStopId.isEmpty {
            failures.append("context: expected walk link index")
        }

        let checkCases = selected.isEmpty ? cases : cases.filter { selected.contains($0.label) }

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

        for check in checkCases {
            guard let date = parser.date(from: check.iso) else {
                failures.append("\(check.label): invalid date")
                continue
            }

            let engine = OfflineRoutingEngine(scheduleDb: scheduleDb, baseDb: baseDb)
            let start = Date()
            let journeys: [Journey] = engine.planTrip(
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
            let unavailableFeed = check.requiredActiveFeed.flatMap { feed in
                activeServiceIds(feed: feed, on: date, scheduleDb: scheduleDb).isEmpty ? feed : nil
            }

            print("\(check.label): count=\(journeys.count) elapsedMs=\(elapsedMs) lines=\(Array(allLines).sorted())")
            if ProcessInfo.processInfo.environment["TRANSI_ROUTING_DEBUG"] == "1" {
                printJourneys(journeys)
            }

            if elapsedMs > check.maxMs {
                failures.append("\(check.label): elapsed \(elapsedMs)ms > \(check.maxMs)ms")
            }
            if let unavailableFeed {
                print("\(check.label): skipped unavailable feed=\(unavailableFeed) date=\(gtfsDateString(for: date))")
                continue
            }
            if journeys.count < check.minJourneys {
                failures.append("\(check.label): count \(journeys.count) < \(check.minJourneys)")
            }
            if check.requiredLines.isDisjoint(with: allLines) {
                failures.append("\(check.label): missing required lines \(Array(check.requiredLines).sorted())")
            }
            let signatures = journeys.map { journey in
                (journey.parts ?? [])
                    .filter { $0.routeType != 64 }
                    .compactMap(\.routeShortName)
                    .joined(separator: ">")
            }
            let uniqueSignatures = Set(signatures)
            if check.minUniqueLineSignatures > 0 && uniqueSignatures.count < check.minUniqueLineSignatures {
                failures.append("\(check.label): unique line signatures \(uniqueSignatures.count) < \(check.minUniqueLineSignatures)")
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
    }

    private static func activeServiceIds(feed: String, on date: Date, scheduleDb: SQLiteDatabase) -> Set<String> {
        let dateString = gtfsDateString(for: date)
        let dayColumn = dayOfWeekColumn(for: date)
        let calendarRows = scheduleDb.query("""
            SELECT service_id FROM calendar
            WHERE feed = ? AND start_date <= ? AND end_date >= ? AND \(dayColumn) = 1
        """, params: [feed, dateString, dateString])
        var ids = Set(calendarRows.compactMap { $0["service_id"] as? String })
        let exceptionRows = scheduleDb.query(
            "SELECT service_id, exception_type FROM calendar_dates WHERE feed = ? AND date = ?",
            params: [feed, dateString]
        )
        for row in exceptionRows {
            guard let serviceId = row["service_id"] as? String,
                  let type = row["exception_type"] as? Int else { continue }
            if type == 1 { ids.insert(serviceId) }
            if type == 2 { ids.remove(serviceId) }
        }
        return ids
    }

    private static func dayOfWeekColumn(for date: Date) -> String {
        switch bratislavaCalendar.component(.weekday, from: date) {
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

    private static func gtfsDateString(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = bratislavaCalendar
        formatter.timeZone = bratislavaTimeZone
        formatter.dateFormat = "yyyyMMdd"
        return formatter.string(from: date)
    }

    private static var bratislavaCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = bratislavaTimeZone
        return calendar
    }

    private static var bratislavaTimeZone: TimeZone {
        TimeZone(identifier: "Europe/Bratislava")!
    }

    private static func printJourneys(_ journeys: [Journey]) {
        for (index, journey) in journeys.enumerated() {
            let parts = journey.parts ?? []
            let signature = parts.map { part -> String in
                let line = part.routeShortName ?? "walk"
                let start = part.startStopName ?? "?"
                let end = part.endStopName ?? "?"
                return "\(line):\(start)->\(end)"
            }.joined(separator: " | ")
            print("  [\(index + 1)] \(signature)")
        }
    }
}
