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
        let checkCases = selected.isEmpty ? cases : cases.filter { selected.contains($0.label) }
        var failures = [String]()

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
    }
}
