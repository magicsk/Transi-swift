#!/bin/bash
set -euo pipefail

transi_root="$(cd "$(dirname "$0")/.." && pwd)"
transi_test_cache="$(mktemp -d "${TMPDIR:-/tmp}/transi-live-activity-alerts-check.XXXXXX")"
trap 'rm -r -- "$transi_test_cache"' EXIT

# Replay a stuck vehicle through the production alert gate without loading ActivityKit.
{
    printf '%s\n' 'import Foundation'
    awk '/^struct Connection:/,/^}/
        /^func getDepartureTimeRemainingText/,/^}/
        /^func getLiveActivityProgressMinutes/,/^}/' "$transi_root/Shared/Models/Table.swift"
    sed -n '/^\/\/ Swift regression checks/,/^SWIFT$/ { /^SWIFT$/!p; }' "$0"
} | xcrun swift -module-cache-path "$transi_test_cache" -
exit

: <<'SWIFT'
// Swift regression checks
func connection(secondsLeft: Int, lastStop: String) -> Connection {
    var connection = Connection.example
    connection.departureTimeRaw = Date().timeIntervalSince1970 + Double(secondsLeft) + 0.5
    connection.departureTimeRemaining = getDepartureTimeRemainingText("", connection.departureTimeRaw, "online")
    connection.lastStopName = lastStop
    return connection
}

// Mirrors updateActivity with default settings: 200 s threshold, every notify toggle on.
// The 10 s ticker updates on text changes; the server pushes every 60 s.
var eta = 150, stop = "Trnavské mýto"
var old = connection(secondsLeft: eta, lastStop: stop)
var lastAlertMinutes: Int?
var alertsBefore = 0
var alerts = [String]()
for t in stride(from: 10, through: 780, by: 10) {
    let isPush = t % 60 == 0
    if isPush, t < 600 {
        eta = t + 150 // stuck: every update slides the ETA a minute later
    } else if t == 600 {
        eta = 750 // moving again: passed the next stop, steady ETA
        stop = "Račianske mýto"
    }
    let new = connection(secondsLeft: eta - t, lastStop: stop)
    guard isPush || new.departureTimeRemaining != old.departureTimeRemaining else { continue }
    let isNew = old.departureTimeRemaining != new.departureTimeRemaining || old.lastStopName != new.lastStopName
    if eta - t < 200, isNew {
        alertsBefore += 1
        if let minutes = getLiveActivityProgressMinutes(from: old, to: new, lastAlertMinutes: lastAlertMinutes) {
            lastAlertMinutes = minutes
            alerts.append("\(t)s \(new.departureTimeRemaining)")
        }
    }
    old = new
}

assert(alertsBefore >= 20, "Replay must reproduce the stuck-vehicle alert spam (\(alertsBefore))")
assert(alerts == ["40s 1 min", "600s 2 min", "640s 1 min", "700s <1 min", "750s now"],
       "Stuck vehicle alerts once, then only on a new stop or fewer minutes: \(alerts)")
print("PASS: stuck vehicle for 10 min alerts \(alerts.count)× instead of \(alertsBefore)×: \(alerts)")
SWIFT
