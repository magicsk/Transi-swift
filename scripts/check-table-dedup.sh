#!/bin/bash
set -euo pipefail

transi_root="$(cd "$(dirname "$0")/.." && pwd)"
transi_test_cache="$(mktemp -d "${TMPDIR:-/tmp}/transi-table-dedup-check.XXXXXX")"
trap 'rm -r -- "$transi_test_cache"' EXIT

# Replay departures captured from both feeds through the production trip matcher.
{
    printf '%s\n' 'import Foundation'
    awk '/^struct Connection:/,/^}/
        /^func isSameDeparture/,/^}/
        /^func terminates/,/^}/' "$transi_root/Shared/Models/Table.swift"
    sed -n '/^\/\/ Swift regression checks/,/^SWIFT$/ { /^SWIFT$/!p; }' "$0"
} | xcrun swift -module-cache-path "$transi_test_cache" -
exit

: <<'SWIFT'
// Swift regression checks
func departure(_ line: String, platform: Int, cp: String) -> Connection {
    let parts = cp.split(separator: ":").map { Double($0)! }
    var connection = Connection.example
    connection.line = line
    connection.platform = platform
    connection.departureTimeCP = 1_791_000_000 + parts[0] * 3600 + parts[1] * 60
    return connection
}

// Socket rounds casCP to the minute; regional schedules are whole minutes.
let cases: [(String, Connection, Connection, Bool)] = [
    ("70: socket 18:37:30 rounds up, regional 18:37", departure("70", platform: 715, cp: "18:38"),
     departure("70", platform: 715, cp: "18:37"), true),
    ("Prievozská 42: feeds schedule 11:26 vs 11:23", departure("42", platform: 715, cp: "11:26"),
     departure("42", platform: 715, cp: "11:23"), true),
    ("regional platform unknown", departure("740", platform: 715, cp: "11:35"),
     departure("740", platform: -1, cp: "11:35"), true),
    ("other direction of the same line", departure("42", platform: 716, cp: "11:26"),
     departure("42", platform: 715, cp: "11:26"), false),
    ("next tram on a 4-minute headway", departure("9", platform: 955, cp: "11:24"),
     departure("9", platform: 955, cp: "11:20"), false),
    ("other line at the same time", departure("71", platform: 715, cp: "11:27"),
     departure("72", platform: 715, cp: "11:27"), false),
]

for (name, socket, regional, expected) in cases {
    assert(isSameDeparture(socket, regional) == expected, "\(name): expected \(expected)")
    assert(isSameDeparture(regional, socket) == expected, "\(name): must be symmetric")
}

// Tram 3 runs every 2 minutes: a timetable-only row must not take over the previous tram's live data.
let untrackedTram = departure("3", platform: 262, cp: "07:02")
assert(!isSameDeparture(untrackedTram, departure("3", platform: 262, cp: "07:00"), within: 0))
assert(isSameDeparture(untrackedTram, departure("3", platform: 262, cp: "07:02"), within: 0))
print("PASS: \(cases.count + 2) socket/regional trip matching cases")

// Regional trips arriving at their last stop are not departures from it.
let terminusCases: [(String, String?, Bool)] = [
    ("Patrónka", "Patrónka", true),
    ("Bratislava, Patrónka", "Patrónka", true),
    ("Bratislava, AS", "Autobusová stanica", true),
    ("Nem. Bory ► Podvornice", "Patrónka", false),
    ("Hlavná stanica", "Prievozská", false),
    ("Bratislava, AS", "Prievozská", false),
    ("", nil, false),
]

for (headsign, stopName, expected) in terminusCases {
    var connection = Connection.example
    connection.headsign = headsign
    assert(terminates(connection, at: stopName) == expected, "\(headsign) at \(stopName ?? "nil"): expected \(expected)")
}
print("PASS: \(terminusCases.count) regional terminus cases")
SWIFT
