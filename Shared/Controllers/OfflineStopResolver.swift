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

    /// The stops named like `name`, through the aliases, or containing it when none is.
    func resolveStops(named name: String) -> [OfflineStop] {
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

        return result
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
            lat: lat,
            lon: lon,
            platform: row["platform_code"] as? String,
            zone: row["zone_id"] as? String
        )
    }
}
