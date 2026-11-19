#!/bin/bash
set -euo pipefail

transi_root="$(cd "$(dirname "$0")/.." && pwd)"
transi_test_cache="$(mktemp -d "${TMPDIR:-/tmp}/transi-train-departures-check.XXXXXX")"
trap 'rm -r -- "$transi_test_cache"' EXIT

# Run the production train departure decoding and board merge on handmade boards.
{
    printf '%s\n' 'import Foundation'
    awk '/^struct Connection:/,/^}/
        /^func getDelayText/,/^}/
        /^func getDepartureTimeRemainingText/,/^}/
        /^func getShortDepartureTimeRemainingText/,/^}/
        /^func isSameDeparture/,/^}/
        /^struct LiveActivityConnectionReference/,/^}/
        /^    func matchesLiveActivityReference/ { print "extension Connection {"; matcher = 1 }
        matcher { print; if ($0 ~ /^    }$/) { print "}"; matcher = 0 } }
        /^\/\/ MARK: - Train departures/,0' "$transi_root/Shared/Models/Table.swift"
    sed -n '/^\/\/ Swift regression checks/,/^SWIFT$/ { /^SWIFT$/!p; }' "$0"
} | xcrun swift -module-cache-path "$transi_test_cache" -
exit

: <<'SWIFT'
// Swift regression checks
let now: TimeInterval = 1_795_086_000
let stopId = 82

func minutes(_ offset: Int) -> TimeInterval { now + TimeInterval(offset * 60) }

func boardRow(_ line: String, _ offset: Int, id: String, type: String = "cp") -> Connection {
    var connection = Connection.empty
    connection.id = id
    connection.line = line
    connection.platform = 7915
    connection.stopId = stopId
    connection.departureTimeCP = minutes(offset)
    connection.departureTimeRaw = minutes(offset)
    connection.type = type
    return connection
}

func train(_ line: String, _ offset: Int, delay: Int?, number: String = "2014") -> TrainDeparture {
    TrainDeparture(train: number, line: line, headsign: "Kúty", departure: minutes(offset), delay: delay,
                   lastStation: delay == nil ? nil : "Bratislava-Lamač")
}

// The API's snake_case JSON decodes as the app's fetches do.
let decoder = JSONDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase
let json = """
{"departures":[{"train":"604","line":"Ex 604","headsign":"Bratislava hl.st.","departure":\(Int(minutes(10))),"delay":48,"last_station":"Šenkvice"},
{"train":"2016","line":"S20","headsign":"Kúty","departure":\(Int(minutes(30))),"delay":null,"last_station":null}]}
"""
let decoded = try! decoder.decode(TrainDeparturesResponse.self, from: json.data(using: .utf8)!).departures
let live = decoded[0].connection(at: stopId)
assert(live.id == "train:604:\(Int(minutes(10)))", "train row id: \(live.id)")
assert(live.line == "Ex 604" && live.platform == -1 && live.stopId == stopId && live.busID == "0:0")
assert(live.type == "online" && live.delay == 48 && live.delayText == "48 min delay")
assert(live.departureTimeCP == minutes(10) && live.departureTimeRaw == minutes(58), "live departs after its delay")
assert(live.lastStopName == "Šenkvice")
let scheduled = decoded[1].connection(at: stopId)
assert(scheduled.type == "cp" && scheduled.delay == 0 && scheduled.delayText == "offline")
assert(scheduled.departureTimeRaw == minutes(30) && scheduled.lastStopName == "none")
print("PASS: train departures decode into board rows")

func merge(_ trains: [TrainDeparture], _ board: [Connection]) -> [Connection] {
    mergeTrainDepartures(trains, at: stopId, into: board, now: now)
}

// The train departures take the place of every train row (socket's S20, ÖBB's "REX6") up to their last
// train, and leave buses, trams, later train rows and a live IDS BK row no live train covers alone.
let board = [
    boardRow("S20", 12, id: "1:7915"), boardRow("71", 12, id: "2:207"), boardRow("REX6", 47, id: "3:7918"),
    boardRow("S60", 9, id: "4717:1237:x", type: "online"), boardRow("S70", 130, id: "5:7915"),
]
var merged = merge([train("S20", 12, delay: 3), train("Ex 604", 10, delay: nil, number: "604"),
                    train("REX 7740", 47, delay: 1, number: "7740")], board)
assert(merged.map(\.id) == ["2:207", "4717:1237:x", "5:7915", "train:2014:\(Int(minutes(12)))",
                            "train:604:\(Int(minutes(10)))", "train:7740:\(Int(minutes(47)))"], "\(merged.map(\.id))")
assert(merged[3].type == "online" && merged[3].departureTimeRaw == minutes(15) && merged[3].lastStopName == "Bratislava-Lamač")

// Without train departures, failed or none listed, the board keeps its trains.
merged = merge([], board)
assert(merged.map(\.id) == board.map(\.id))

// A train stays until a minute after it leaves, a late one until then too.
merged = merge([train("Ex 604", -3, delay: 1, number: "604"), train("Ex 606", -2, delay: 2, number: "606"),
                train("Ex 608", -40, delay: 45, number: "608")], [])
assert(merged.map(\.line) == ["Ex 606", "Ex 608"], "\(merged.map(\.line))")

// The board may time the list's last train up to 3 minutes later; a train row past that is a later train.
merged = merge([train("S20", 100, delay: nil)], [boardRow("S20", 102, id: "6:7915"), boardRow("S20", 104, id: "7:7915")])
assert(merged.map(\.id) == ["7:7915", "train:2014:\(Int(minutes(100)))"], "\(merged.map(\.id))")

// A row live from IDS BK keeps its delay while ŽSR has none for that train, and stands in for it; once ŽSR
// has one, the train's row takes over.
let idsBkLive = boardRow("S60", 20, id: "4719:1237:x", type: "online")
merged = merge([train("S60", 20, delay: nil, number: "4719"), train("S20", 32, delay: nil)], [idsBkLive])
assert(merged.map(\.id) == ["4719:1237:x", "train:2014:\(Int(minutes(32)))"], "\(merged.map(\.id))")
// The train's Live Activity follows the row standing in for it; a bus row never stands in for a train.
assert(merged.first { $0.standsIn(for: train("S60", 21, delay: nil, number: "4719").connection(at: stopId)) }?.id == "4719:1237:x")
assert(!boardRow("71", 20, id: "8:207", type: "online").standsIn(for: train("71", 20, delay: nil).connection(at: stopId)))
merged = merge([train("S60", 20, delay: 2, number: "4719")], [idsBkLive])
assert(merged.map(\.id) == ["train:4719:\(Int(minutes(20)))"], "\(merged.map(\.id))")
print("PASS: 6 train merge cases")

// A train's Live Activity follows only its own row; one on a board row also finds the train row taking its place.
let trainRow = train("S20", 12, delay: 3).connection(at: stopId)
let boardS20 = boardRow("S20", 12, id: "1:7915")
assert(!boardS20.matchesLiveActivityReference(LiveActivityConnectionReference(connection: trainRow)))
assert(trainRow.matchesLiveActivityReference(LiveActivityConnectionReference(connection: trainRow)))
assert(trainRow.matchesLiveActivityReference(LiveActivityConnectionReference(connection: boardS20)))
print("PASS: 3 train Live Activity matching cases")
SWIFT
