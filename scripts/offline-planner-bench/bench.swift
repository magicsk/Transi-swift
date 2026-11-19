import Foundation

// Reads [{label,from,to,iso}] JSON from argv[1], prints one JSON line per query with offline journeys.
@main
enum Bench {
    static func main() {
        let env = ProcessInfo.processInfo.environment
        let baseDb = SQLiteDatabase(path: env["TRANSI_BASE_DB"]!)!
        let scheduleDb = SQLiteDatabase(path: env["TRANSI_SCHEDULE_DB"]!)!
        scheduleDb.execute("ATTACH DATABASE '\(env["TRANSI_BASE_DB"]!)' AS base")
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let imhdStops = try! decoder.decode([Stop].self, from: FileManager.default.contents(atPath: env["TRANSI_STOPS_JSON"]!)!)
        let queries = try! JSONSerialization.jsonObject(with: FileManager.default.contents(atPath: CommandLine.arguments[1])!) as! [[String: String]]
        let parser = ISO8601DateFormatter()
        let out = ISO8601DateFormatter()
        for q in queries {
            let engine = OfflineRoutingEngine(scheduleDb: scheduleDb, baseDb: baseDb)
            let start = Date()
            let journeys = engine.planTrip(fromName: q["from"]!, toName: q["to"]!, date: parser.date(from: q["iso"]!)!,
                                           arrivalDeparture: .departure, maxTransfers: 3, maxWalkDuration: 15, imhdStops: imhdStops)
            let ms = Int(Date().timeIntervalSince(start) * 1000)
            let js: [[String: Any]] = journeys.map { j in
                let parts = j.parts ?? []
                return ["dep": out.string(from: parts.first!.startDeparture), "arr": out.string(from: parts.last!.endArrival),
                        "lines": parts.filter { $0.routeType != 64 }.compactMap(\.routeShortName),
                        "walkSec": parts.filter { $0.routeType == 64 }.reduce(0) { $0 + $1.endArrival.timeIntervalSince($1.startDeparture) }]
            }
            let line: [String: Any] = ["label": q["label"]!, "ms": ms, "journeys": js]
            print(String(data: try! JSONSerialization.data(withJSONObject: line), encoding: .utf8)!)
            fflush(stdout)
        }
    }
}
