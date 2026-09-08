#!/bin/bash
set -euo pipefail

transi_root="$(cd "$(dirname "$0")/.." && pwd)"
transi_test_cache="$(mktemp -d "${TMPDIR:-/tmp}/transi-recents-check.XXXXXX")"
trap 'rm -r -- "$transi_test_cache"' EXIT

# Exercise the production Codable implementation without loading iOS services.
{
    printf '%s\n' 'import Foundation'
    awk '/^struct RecentTripSearch:/,/^class TripPlannerController:/ {
        if ($0 !~ /^class TripPlannerController:/) print
    }' "$transi_root/Shared/Controllers/TripPlannerController.swift"
    sed -n '/^\/\/ Swift regression checks/,/^SWIFT$/ { /^SWIFT$/!p; }' "$0"
} | xcrun swift -module-cache-path "$transi_test_cache" -
exit

: <<'SWIFT'
// Swift regression checks
struct Stop: Codable, Equatable { let id: Int }
struct Trip: Codable, Equatable { let journey: [String] }
enum ArrivalDeparture: String, Codable { case arrival, departure }

let firstDate = Date(timeIntervalSinceReferenceDate: 800_000_000.25)
let secondDate = firstDate.addingTimeInterval(3_600)
var searches = [
    RecentTripSearch(
        from: Stop(id: 1), to: Stop(id: 2),
        arrivalDeparture: .departure,
        arrivalDepartureDate: firstDate,
        arrivalDepartureCustomDate: false,
        trip: Trip(journey: ["first result", "paginated result"])
    ),
    RecentTripSearch(
        from: Stop(id: 2), to: Stop(id: 3),
        arrivalDeparture: .arrival,
        arrivalDepartureDate: secondDate,
        arrivalDepartureCustomDate: true,
        trip: Trip(journey: ["other search result"])
    )
]
searches[0].tripSavedAt = firstDate.addingTimeInterval(5)
searches[1].tripSavedAt = secondDate.addingTimeInterval(5)

let encoder = JSONEncoder()
let decoder = JSONDecoder()
let restored = try decoder.decode([RecentTripSearch].self, from: encoder.encode(searches))
assert(restored == searches, "Restart round-trip must preserve every result, search date and save date")

let legacyJSON = Data("""
[{"from":{"id":1},"to":{"id":2},"arrivalDeparture":"arrival",
  "arrivalDepartureDate":800000000.25,"arrivalDepartureCustomDate":true},
 {"from":{"id":2},"to":{"id":3}}]
""".utf8)
let legacy = try decoder.decode([RecentTripSearch].self, from: legacyJSON)
assert(legacy.count == 2 && legacy.allSatisfy { $0.trip == nil && $0.tripSavedAt == nil },
       "Legacy metadata without saved results must remain readable")
assert(legacy[0].arrivalDepartureDate == firstDate && legacy[0].arrivalDeparture == .arrival
       && legacy[0].arrivalDepartureCustomDate, "Legacy custom search criteria must survive")
assert(legacy[1].arrivalDeparture == .departure && !legacy[1].arrivalDepartureCustomDate,
       "Original stop-only recents must keep their defaults")
print("PASS: multiple saved trips, pagination results, exact dates and legacy recents")
SWIFT
