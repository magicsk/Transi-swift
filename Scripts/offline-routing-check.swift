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
    let forbidsFinalWalk: Bool
    let maxDepartureSpanSeconds: Int?

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
        requiredActiveFeed: String? = nil,
        forbidsFinalWalk: Bool = false,
        maxDepartureSpanSeconds: Int? = nil
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
        self.forbidsFinalWalk = forbidsFinalWalk
        self.maxDepartureSpanSeconds = maxDepartureSpanSeconds
    }
}

let cases: [CheckCase] = [
    CheckCase(label: "short_city", from: "Hronská", to: "Most SNP", iso: "2026-06-12T08:00:00+02:00", mode: .departure, minJourneys: 5, maxMs: 5000, requiredLines: ["70"], minUniqueLineSignatures: 2),
    CheckCase(label: "medium_city", from: "Zlaté piesky", to: "Hlavná stanica", iso: "2026-06-12T08:00:00+02:00", mode: .departure, minJourneys: 4, maxMs: 5000, requiredLines: ["61"]),
    CheckCase(label: "train_station_pair", from: "Hlavná stanica", to: "Stn. Petržalka", iso: "2026-06-12T08:00:00+02:00", mode: .departure, minJourneys: 5, maxMs: 5000, requiredLines: ["93"]),
    CheckCase(label: "regional_bus", from: "Autobusová stanica", to: "Rovinka, Obecný úrad", iso: "2026-06-12T08:00:00+02:00", mode: .departure, minJourneys: 5, maxMs: 5000, requiredLines: ["725", "727", "737"], requiredActiveFeed: "regional"),
    CheckCase(label: "regional_train", from: "Hlavná stanica", to: "Pezinok, Žel. stanica", iso: "2026-06-12T08:00:00+02:00", mode: .departure, minJourneys: 4, maxMs: 5000, requiredLines: ["R50", "S50"]),
    CheckCase(label: "long_suburban", from: "Most SNP", to: "Senec, Žel. stanica", iso: "2026-06-12T08:00:00+02:00", mode: .departure, minJourneys: 4, maxMs: 5000, requiredLines: ["S60", "620"]),
    CheckCase(label: "late_short", from: "Hronská", to: "Most SNP", iso: "2026-06-12T23:30:00+02:00", mode: .departure, minJourneys: 2, maxMs: 5000, requiredLines: ["N70"]),
    CheckCase(label: "arrival_city", from: "Hronská", to: "Most SNP", iso: "2026-06-12T08:40:00+02:00", mode: .arrival, minJourneys: 3, maxMs: 5000, requiredLines: ["70"]),
    CheckCase(label: "overnight_departure", from: "Hronská", to: "Most SNP", iso: "2026-06-13T00:30:00+02:00", mode: .departure, minJourneys: 1, maxMs: 5000, requiredLines: ["N33", "N70", "N72"]),
    CheckCase(label: "overnight_arrival", from: "Hronská", to: "Most SNP", iso: "2026-06-13T00:45:00+02:00", mode: .arrival, minJourneys: 1, maxMs: 5000, requiredLines: ["N70"]),
    CheckCase(label: "early_morning_departure", from: "Hronská", to: "Most SNP", iso: "2026-06-13T04:59:00+02:00", mode: .departure, minJourneys: 1, maxMs: 5000, requiredLines: ["72"]),
    CheckCase(label: "hill_destination_direct", from: "Hodžovo nám.", to: "Hrad", iso: "2026-06-12T08:00:00+02:00", mode: .departure, minJourneys: 2, maxMs: 5000, requiredLines: ["47"], forbidsFinalWalk: true),
    CheckCase(label: "hill_destination_hub", from: "Hlavná stanica", to: "Hrad", iso: "2026-06-12T08:00:00+02:00", mode: .departure, minJourneys: 3, maxMs: 5000, requiredLines: ["44"], forbidsFinalWalk: true),
    CheckCase(label: "brodna_krce_afternoon", from: "Brodná", to: "Krče", iso: "2026-07-13T15:00:00+02:00", mode: .departure, minJourneys: 6, maxMs: 5000, requiredLines: ["21", "92"], maxDepartureSpanSeconds: 2 * 60 * 60),
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
        let environment = ProcessInfo.processInfo.environment
        let overrideIso = environment["TRANSI_CHECK_ISO"]
        let maxTransfers = Int(environment["TRANSI_MAX_TRANSFERS"] ?? "") ?? 3
        let maxWalkDuration = Int(environment["TRANSI_MAX_WALK_DURATION"] ?? "") ?? 15
        let skipFixedExpectations = environment["TRANSI_SKIP_EXPECTATIONS"] == "1"

        guard let contextDate = parser.date(from: overrideIso ?? "2026-06-12T08:00:00+02:00") else {
            fputs("FAIL: invalid TRANSI_CHECK_ISO \(overrideIso ?? "")\n", stderr)
            exit(1)
        }
        let context = OfflineRoutingContext.build(scheduleDb: scheduleDb, baseDb: baseDb, date: contextDate, maxWalkDuration: maxWalkDuration)
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
        let hlavna = resolver.resolveStops(named: "Hlavná stanica", maxWalkDuration: maxWalkDuration)
        let petrzalka = resolver.resolveStops(named: "Stn. Petržalka", maxWalkDuration: maxWalkDuration)
        let pezinok = resolver.resolveStops(named: "Pezinok, Žel. stanica", maxWalkDuration: maxWalkDuration)
        let resolverChecks: [(String, [OfflineStop], String)] = [
            ("Hlavná stanica", hlavna, "Bratislava hl.st."),
            ("Stn. Petržalka", petrzalka, "Bratislava-Petržalka"),
            ("Pezinok, Žel. stanica", pezinok, "Pezinok"),
        ]
        for (label, stops, expectedName) in resolverChecks where !stops.contains(where: { $0.name == expectedName }) {
            failures.append("\(label): missing alias candidate \(expectedName)")
        }

        for check in checkCases {
            guard let date = parser.date(from: overrideIso ?? check.iso) else {
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
                maxTransfers: maxTransfers,
                maxWalkDuration: maxWalkDuration
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
                fputs("WARN: \(check.label): elapsed \(elapsedMs)ms > \(check.maxMs)ms budget\n", stderr)
            }
            if let unavailableFeed, !skipFixedExpectations {
                print("\(check.label): skipped unavailable feed=\(unavailableFeed) date=\(gtfsDateString(for: date))")
                continue
            }
            if !skipFixedExpectations, journeys.count < check.minJourneys {
                failures.append("\(check.label): count \(journeys.count) < \(check.minJourneys)")
            }
            if !skipFixedExpectations, check.requiredLines.isDisjoint(with: allLines) {
                failures.append("\(check.label): missing required lines \(Array(check.requiredLines).sorted())")
            }
            let signatures = journeys.map { journey in
                (journey.parts ?? [])
                    .filter { $0.routeType != 64 }
                    .compactMap(\.routeShortName)
                    .joined(separator: ">")
            }
            let uniqueSignatures = Set(signatures)
            if !skipFixedExpectations, check.minUniqueLineSignatures > 0 && uniqueSignatures.count < check.minUniqueLineSignatures {
                failures.append("\(check.label): unique line signatures \(uniqueSignatures.count) < \(check.minUniqueLineSignatures)")
            }
            if let repeatedLineSignature = repeatedTransitLineSignature(in: journeys) {
                failures.append("\(check.label): repeated transit line \(repeatedLineSignature)")
            }
            if let dominatedSignature = dominatedJourneySignature(in: journeys, mode: check.mode) {
                failures.append("\(check.label): dominated journey \(dominatedSignature)")
            }
            if let extremeDurationSignature = extremeDurationJourneySignature(in: journeys) {
                failures.append("\(check.label): extreme duration detour \(extremeDurationSignature)")
            }
            if check.mode == .departure, let outOfOrderSignature = outOfOrderDepartureSignature(in: journeys) {
                failures.append("\(check.label): departures not sorted by start time \(outOfOrderSignature)")
            }
            if let maxDepartureSpanSeconds = check.maxDepartureSpanSeconds,
               let departureSpan = departureSpanSeconds(in: journeys),
               departureSpan > maxDepartureSpanSeconds {
                failures.append("\(check.label): departure span \(departureSpan)s > \(maxDepartureSpanSeconds)s")
            }
            if check.forbidsFinalWalk, let finalWalkSignature = finalWalkSignature(in: journeys) {
                failures.append("\(check.label): final walk journey \(finalWalkSignature)")
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
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = bratislavaTimeZone
        for (index, journey) in journeys.enumerated() {
            let parts = journey.parts ?? []
            let signature = parts.map { part -> String in
                let line = part.routeShortName ?? "walk"
                let start = part.startStopName ?? "?"
                let end = part.endStopName ?? "?"
                return "\(line):\(start)->\(end)"
            }.joined(separator: " | ")
            let start = parts.first.map { formatter.string(from: $0.startDeparture) } ?? "?"
            let end = parts.last.map { formatter.string(from: $0.endArrival) } ?? "?"
            print("  [\(index + 1)] \(start)-\(end) \(signature)")
        }
    }

    private static func repeatedTransitLineSignature(in journeys: [Journey]) -> String? {
        for journey in journeys {
            let lines = transitLines(journey)
            var seen = Set<String>()
            for line in lines {
                if seen.contains(line) {
                    return lines.joined(separator: ">")
                }
                seen.insert(line)
            }
        }
        return nil
    }

    private static func dominatedJourneySignature(in journeys: [Journey], mode: ArrivalDeparture) -> String? {
        let metrics = journeys.compactMap(JourneyMetrics.init)
        for candidate in metrics {
            if metrics.contains(where: { other in
                other.id != candidate.id && dominates(other, candidate, mode: mode)
            }) {
                return candidate.signature
            }
        }
        return nil
    }

    private static func finalWalkSignature(in journeys: [Journey]) -> String? {
        for journey in journeys {
            let parts = journey.parts ?? []
            if parts.last?.routeType == 64 {
                return parts.map { part -> String in
                    let line = part.routeShortName ?? "walk"
                    let start = part.startStopName ?? "?"
                    let end = part.endStopName ?? "?"
                    return "\(line):\(start)->\(end)"
                }.joined(separator: " | ")
            }
        }
        return nil
    }

    private static func extremeDurationJourneySignature(in journeys: [Journey]) -> String? {
        let metrics = journeys.compactMap(JourneyMetrics.init)
        let durations = metrics.map(\.durationSeconds).filter { $0 > 0 }
        guard let bestDuration = durations.min() else { return nil }
        let limit = max(bestDuration + 30 * 60, bestDuration * 2)
        return metrics.first { $0.durationSeconds > limit }?.signature
    }

    private static func outOfOrderDepartureSignature(in journeys: [Journey]) -> String? {
        var previous: Date?
        for journey in journeys {
            guard let departure = journey.parts?.first?.startDeparture else { continue }
            if let previous, departure < previous {
                return JourneyMetrics(journey)?.signature ?? "unknown"
            }
            previous = departure
        }
        return nil
    }

    private static func departureSpanSeconds(in journeys: [Journey]) -> Int? {
        let departures = journeys.compactMap { $0.parts?.first?.startDeparture }
        guard let first = departures.min(), let last = departures.max() else { return nil }
        return Int(last.timeIntervalSince(first))
    }

    private static func dominates(_ lhs: JourneyMetrics, _ rhs: JourneyMetrics, mode: ArrivalDeparture) -> Bool {
        guard lhs.startName == rhs.startName, lhs.endName == rhs.endName else { return false }
        guard isPrefix(lhs.lines, of: rhs.lines) else { return false }
        let noWorseCore: Bool
        switch mode {
        case .departure:
            noWorseCore = lhs.departure >= rhs.departure && lhs.arrival <= rhs.arrival
        case .arrival:
            noWorseCore = lhs.departure >= rhs.departure && lhs.arrival <= rhs.arrival
        }
        guard noWorseCore,
              lhs.transferCount <= rhs.transferCount,
              lhs.walkSeconds <= rhs.walkSeconds else {
            return false
        }
        return lhs.departure > rhs.departure ||
            lhs.arrival < rhs.arrival ||
            lhs.transferCount < rhs.transferCount ||
            lhs.walkSeconds < rhs.walkSeconds
    }

    private static func isPrefix(_ prefix: [String], of lines: [String]) -> Bool {
        guard !prefix.isEmpty, prefix.count < lines.count else { return false }
        return Array(lines.prefix(prefix.count)) == prefix
    }

    private static func transitLines(_ journey: Journey) -> [String] {
        (journey.parts ?? [])
            .filter { $0.routeType != 64 }
            .compactMap(\.routeShortName)
    }

    private struct JourneyMetrics {
        let id: String
        let startName: String
        let endName: String
        let departure: Date
        let arrival: Date
        let transferCount: Int
        let walkSeconds: Int
        let durationSeconds: Int
        let lines: [String]
        let signature: String

        init?(_ journey: Journey) {
            guard let parts = journey.parts,
                  let first = parts.first,
                  let last = parts.last else {
                return nil
            }
            id = journey.id
            startName = first.startStopName ?? ""
            endName = last.endStopName ?? ""
            departure = first.startDeparture
            arrival = last.endArrival
            durationSeconds = max(0, Int(arrival.timeIntervalSince(departure)))
            let transitParts = parts.filter { $0.routeType != 64 }
            transferCount = max(0, transitParts.count - 1)
            lines = transitParts.compactMap(\.routeShortName)
            walkSeconds = parts
                .filter { $0.routeType == 64 }
                .reduce(0) { total, part in
                    total + max(0, Int(part.endArrival.timeIntervalSince(part.startDeparture)))
                }
            signature = lines.joined(separator: ">")
        }
    }
}
