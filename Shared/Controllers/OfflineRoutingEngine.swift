//
//  OfflineRoutingEngine.swift
//  Transi
//
//  Created by magic_sk on 06/03/2026.
//

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
    
    private func distanceBetween(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let r = 6371e3
        let phi1 = lat1 * Double.pi / 180
        let phi2 = lat2 * Double.pi / 180
        let deltaPhi = (lat2 - lat1) * Double.pi / 180
        let deltaLambda = (lon2 - lon1) * Double.pi / 180
        let a = sin(deltaPhi / 2) * sin(deltaPhi / 2) + cos(phi1) * cos(phi2) * sin(deltaLambda / 2) * sin(deltaLambda / 2)
        return r * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    private func normalizeStopName(_ name: String) -> String {
        return name.replacingOccurrences(of: "Bratislava, ", with: "")
                   .replacingOccurrences(of: "Rovinka, ", with: "")
                   .replacingOccurrences(of: "Dunajská Lužná, ", with: "")
                   .replacingOccurrences(of: "Miloslavov, ", with: "")
    }

    private func getStops(name: String) -> [StopInfo] {
        var searchName = name
        if name == "Autobusová stanica" { searchName = "Bratislava, AS" }
        
        var rows = baseDb.query("SELECT stop_id, stop_name, stop_lat, stop_lon, platform_code, feed FROM stops WHERE stop_name = ?", params: [searchName])
        
        if rows.isEmpty {
            let parts = name.split(separator: ",")
            if parts.count > 1 {
                let cleanName = parts[1].trimmingCharacters(in: .whitespaces)
                rows = baseDb.query("SELECT stop_id, stop_name, stop_lat, stop_lon, platform_code, feed FROM stops WHERE stop_name LIKE ?", params: ["%" + cleanName + "%"])
            } else {
                rows = baseDb.query("SELECT stop_id, stop_name, stop_lat, stop_lon, platform_code, feed FROM stops WHERE stop_name LIKE ?", params: ["%" + name + "%"])
            }
        }
        
        return rows.compactMap { row in
            guard let id = row["stop_id"] as? String,
                  let sname = row["stop_name"] as? String,
                  let lat = row["stop_lat"] as? Double,
                  let lon = row["stop_lon"] as? Double,
                  let feed = row["feed"] as? String else { return nil }
            return StopInfo(id: id, name: sname, normalizedName: normalizeStopName(sname), lat: lat, lon: lon, platform: row["platform_code"] as? String, feed: feed)
        }
    }

    struct GraphState {
        let stopId: String
        let time: Int
        let parts: [Part]
        let zones: [String]
        let transitLegs: Int
        let lastTripId: String?
    }

    func planTrip(fromName: String, toName: String, date: Date, maxTransfers: Int, maxWalkDuration: Int, activeServiceIds: [String]) -> [Journey] {
        let docDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let logFile = docDir.appendingPathComponent("routing_log.txt")
        var logStr = """--- PLAN TRIP START ---
From: \(fromName), To: \(toName)
Max Transfers: \(maxTransfers), Max Walk: \(maxWalkDuration)
"""
        
        let fromStops = getStops(name: fromName)
        let toStops = getStops(name: toName)
        
        if fromStops.isEmpty || toStops.isEmpty { 
            logStr += "Missing stops! fromStops: \(fromStops.count), toStops: \(toStops.count)\n"
            try? logStr.write(to: logFile, atomically: true, encoding: .utf8)
            return [] 
        }
        
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let initialTimeInSeconds = Int(date.timeIntervalSince(startOfDay))
        let initialTime = initialTimeInSeconds / 60
        
        var journeys = [Journey]()
        let toStopIds = Set(toStops.map { $0.id })
        
        // 1. Pre-fetch trips in a 4 hour window
        let maxSearchWindow = 240 // 4 hours
        let placeholders = activeServiceIds.map { _ in "?" }.joined(separator: ",")
        var params: [Any] = [initialTime * 60, (initialTime + maxSearchWindow) * 60]
        params.append(contentsOf: activeServiceIds)
        
        let q = """
            SELECT st.trip_id, st.stop_id, st.departure_time, st.departure_time as arrival_time, st.stop_sequence, 
                   r.route_short_name, r.route_type, t.trip_headsign, st.feed
            FROM stop_times st
            JOIN trips t ON st.trip_id = t.trip_id AND st.feed = t.feed
            JOIN base.routes r ON t.route_id = r.route_id AND t.feed = r.feed
            WHERE st.departure_time >= ? AND st.departure_time <= ?
            AND t.service_id IN (\(placeholders))
            ORDER BY st.trip_id, st.stop_sequence ASC
        """
        
        let rows = scheduleDb.query(q, params: params)
        var tripsDict = [String: MemTrip]()
        for row in rows {
            guard let tripId = row["trip_id"] as? String,
                  let stopId = row["stop_id"] as? String,
                  let dep = row["departure_time"] as? Int,
                  let arr = row["arrival_time"] as? Int,
                  let seq = row["stop_sequence"] as? Int,
                  let rShort = row["route_short_name"] as? String,
                  let rType = row["route_type"] as? Int,
                  let headsign = row["trip_headsign"] as? String,
                  let feed = row["feed"] as? String else { continue }
            let st = MemStopTime(stopId: stopId, arrival: arr, departure: dep, seq: seq)
            if tripsDict[tripId] != nil { tripsDict[tripId]!.stopTimes.append(st) }
            else { tripsDict[tripId] = MemTrip(id: tripId, feed: feed, routeShortName: rShort, routeType: rType, headsign: headsign, stopTimes: [st]) }
        }
        
        // 2. Pre-fetch stops and group by name for FAST platform transfers
        let allStopsRows = baseDb.query("SELECT stop_id, stop_name, stop_lat, stop_lon, platform_code, feed, zone_id FROM stops")
        var allStops = [String: StopInfo]()
        var stopsByName = [String: [StopInfo]]()
        var zonesByStop = [String: String]()
        for row in allStopsRows {
            guard let id = row["stop_id"] as? String, let sname = row["stop_name"] as? String, let lat = row["stop_lat"] as? Double, let lon = row["stop_lon"] as? Double, let feed = row["feed"] as? String else { continue }
            let info = StopInfo(id: id, name: sname, normalizedName: normalizeStopName(sname), lat: lat, lon: lon, platform: row["platform_code"] as? String, feed: feed)
            allStops[id] = info
            stopsByName[info.normalizedName, default: []].append(info)
            if let z = row["zone_id"] as? String, !z.isEmpty { zonesByStop[id] = z }
        }
        
        logStr += "Loaded \(tripsDict.count) trips, \(allStops.count) stops.\n"
        
        var tripsByStop = [String: [(tripId: String, seq: Int, dep: Int)]]()
        for (tId, trip) in tripsDict {
            for st in trip.stopTimes {
                tripsByStop[st.stopId, default: []].append((tripId: tId, seq: st.seq, dep: st.departure))
            }
        }
        
        var bestArr = [String: Int]()
        var activeStates = [GraphState]()
        for fs in fromStops {
            activeStates.append(GraphState(stopId: fs.id, time: initialTime, parts: [], zones: [], transitLegs: 0, lastTripId: nil))
            bestArr[fs.id] = initialTime
        }
        
        let maxLegs = min(maxTransfers + 1, 5)
        for leg in 1...maxLegs {
            if activeStates.isEmpty { break }
            var nextStates = [GraphState]()
            
            for state in activeStates {
                guard let currStopData = allStops[state.stopId] else { continue }
                
                // Optimized Walking: only platforms and nearby
                var walkableOrigins = [(id: String, time: Int, part: Part?)]()
                walkableOrigins.append((id: state.stopId, time: state.time, part: nil))
                
                // Platform transfers (same normalized name)
                for target in stopsByName[currStopData.normalizedName] ?? [] {
                    if target.id == state.stopId { continue }
                    let walkPart = Part(startStopName: currStopData.name, endStopName: target.name, startStopCode: currStopData.platform, endStopCode: target.platform, startDeparture: startOfDay.addingTimeInterval(TimeInterval(state.time * 60)), endArrival: startOfDay.addingTimeInterval(TimeInterval((state.time + 1) * 60)), routeType: 64, tripHeadsign: "Walk to platform", routeShortName: nil)
                    walkableOrigins.append((id: target.id, time: state.time + 1, part: walkPart))
                }
                
                // Transit from each walkable origin
                for origin in walkableOrigins {
                    let passingTrips = tripsByStop[origin.id] ?? []
                    for pt in passingTrips {
                        if pt.tripId == state.lastTripId { continue }
                        if pt.dep < origin.time * 60 || pt.dep > (origin.time + 120) * 60 { continue }
                        
                        guard let trip = tripsDict[pt.tripId] else { continue }
                        for st in trip.stopTimes where st.seq > pt.seq {
                            let arrTimeMins = st.arrival / 60
                            if arrTimeMins < (bestArr[st.stopId] ?? 1000000) {
                                bestArr[st.stopId] = arrTimeMins
                                
                                var newParts = state.parts
                                if let wp = origin.part { newParts.append(wp) }
                                
                                let p = Part(startStopName: origin.id, endStopName: st.stopId, startStopCode: allStops[origin.id]?.platform, endStopCode: allStops[st.stopId]?.platform, startDeparture: startOfDay.addingTimeInterval(TimeInterval(pt.dep)), endArrival: startOfDay.addingTimeInterval(TimeInterval(st.arrival)), routeType: trip.routeType, tripHeadsign: trip.headsign, routeShortName: trip.routeShortName)
                                newParts.append(p)
                                
                                var newZones = Set(state.zones)
                                for tst in trip.stopTimes where tst.seq >= pt.seq && tst.seq <= st.seq {
                                    if let z = zonesByStop[tst.stopId] { newZones.insert(z) }
                                }
                                
                                if toStopIds.contains(st.stopId) {
                                    journeys.append(Journey(id: UUID().uuidString, parts: newParts, zones: Array(newZones).sorted()))
                                } else {
                                    nextStates.append(GraphState(stopId: st.stopId, time: arrTimeMins, parts: newParts, zones: Array(newZones).sorted(), transitLegs: leg, lastTripId: pt.tripId))
                                }
                            }
                        }
                    }
                }
            }
            activeStates = nextStates
            logStr += "Leg \(leg) done, found \(journeys.count) journeys so far.\n"
        }
        
        var unique = Array(Set(journeys))
        unique.sort { ($0.parts?.first?.startDeparture ?? Date()) < ($1.parts?.first?.startDeparture ?? Date()) }
        logStr += "Found \(unique.count) final journeys.\n"
        try? logStr.write(to: logFile, atomically: true, encoding: .utf8)
        return Array(unique.prefix(15))
    }
}
