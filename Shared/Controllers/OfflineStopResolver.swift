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
