#!/bin/bash
set -euo pipefail

transi_root="$(cd "$(dirname "$0")/.." && pwd)"
transi_test_cache="$(mktemp -d "${TMPDIR:-/tmp}/transi-watch-widget-check.XXXXXX")"
trap 'rm -r -- "$transi_test_cache"' EXIT

# Run the watch widget's timeline entry construction against fixed departures.
{
    printf '%s\n' 'import Foundation'
    awk '/^func getDepartureTimeRemainingText/,/^}/
        /^func getShortDepartureTimeRemainingText/,/^}/' "$transi_root/Shared/Models/Table.swift"
    awk '/^func timeStringFromDate/,/^}/' "$transi_root/Shared/Util/DateTime.swift"
    sed -n '/^\/\/ MARK: Timeline entries/,/^\/\/ MARK: End timeline entries/p' \
        "$transi_root/Transi Watch Widget/TransiWatchWidget.swift"
    sed -n '/^\/\/ Swift regression checks/,/^SWIFT$/ { /^SWIFT$/!p; }' "$0"
} | xcrun swift -module-cache-path "$transi_test_cache" -
exit

: <<'SWIFT'
// Swift regression checks
let now = Date(timeIntervalSince1970: 1_791_000_000 + 40) // 40 s past a minute
func departure(_ line: String, inSeconds seconds: Double) -> WidgetDeparture {
    WidgetDeparture(line: line, headsign: "Stn. Vrakuňa", platform: "A", time: now + seconds, isLive: true)
}
func shown(_ entry: DeparturesEntry) -> [WidgetDeparture] {
    guard case let .departures(departures) = entry.state else { fatalError("expected departures") }
    return departures
}

// Departures on whole minutes like the timetable, 4:20, 9:20 and 30:20 from now; something is left all timeline.
let departures = [departure("72", inSeconds: 260), departure("71", inSeconds: 560), departure("78", inSeconds: 1820)]
let entries = departureEntries(departures, stopName: "Hronská", stopId: 94, from: now, minutes: 15)

assert(entries.count == 15, "one entry a minute for 15 minutes, got \(entries.count)")
assert(entries[0].date == now, "the first entry is now")
for (index, entry) in entries.enumerated().dropFirst() {
    assert(entry.date.timeIntervalSince1970 == 1_791_000_000 + Double(index) * 60, "entry \(index) starts its minute")
}
assert(entries.allSatisfy { $0.stopName == "Hronská" && $0.stopId == 94 && !$0.isNearest })

// Time left comes from each entry's own date, as the app's board words it, and only departures after it are shown.
assert(shown(entries[0]).map(\.line) == ["72", "71", "78"])
assert(shown(entries[0]).map(\.remaining) == ["4 min", "9 min", "30 min"])
assert(shown(entries[1]).map(\.remaining) == ["4 min", "9 min", "30 min"], "\(shown(entries[1]).map(\.remaining))")
assert(shown(entries[4]).map(\.remaining) == ["1 min", "6 min", "27 min"], "\(shown(entries[4]).map(\.remaining))")
assert(shown(entries[4]).map(\.shortRemaining) == ["1m", "6m", "27m"])
assert(shown(entries[5]).map(\.line) == ["71", "78"], "72 leaves at entry 5's date")
assert(shown(entries[14]).map(\.remaining) == ["17 min"], "\(shown(entries[14]).map(\.remaining))")
let soon = departureEntries([departure("72", inSeconds: 30)], stopName: "", stopId: -1, from: now, minutes: 15)
assert(shown(soon[0]).map(\.remaining) == ["<1 min"], "under a minute reads like the board")
let timetabled = WidgetDeparture(line: "78", headsign: "", platform: "", time: now + 260, isLive: false)
let scheduled = departureEntries([timetabled], stopName: "", stopId: -1, from: now, minutes: 15)
assert(shown(scheduled[0]).map(\.remaining) == ["~4 min"], "timetable-only departures are marked")
print("PASS: \(entries.count) entries advance per minute with minutes from their own dates")

// At most three departures per entry.
let busy = (1 ... 6).map { departure("\($0)", inSeconds: Double($0) * 60) }
assert(shown(departureEntries(busy, stopName: "", stopId: -1, from: now, minutes: 15)[0]).count == 3)

// No departures: a single empty entry; the timeline ends at the first empty entry.
let empty = departureEntries([], stopName: "Hronská", stopId: -1, from: now, minutes: 15)
assert(empty.count == 1 && empty[0].state == .departures([]) && empty[0].isNearest)
let runsOut = departureEntries([departure("72", inSeconds: 130)], stopName: "", stopId: -1, from: now, minutes: 15)
assert(runsOut.count == 4 && runsOut.last?.state == .departures([]), "\(runsOut.count) entries")
print("PASS: 3 departure limit and empty timeline cases")
SWIFT
