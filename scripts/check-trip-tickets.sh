#!/bin/bash
set -euo pipefail

transi_root="$(cd "$(dirname "$0")/.." && pwd)"
transi_test_cache="$(mktemp -d "${TMPDIR:-/tmp}/transi-trip-tickets-check.XXXXXX")"
trap 'rm -r -- "$transi_test_cache"' EXIT

# Compile the production ticket catalogue, pass coverage and journey mapping without the app's services,
# then replay a trimmed real B-API ticket catalogue and real R-API journeys (scripts/fixtures/ticket-types.json).
sed -n '/^\/\/ Swift regression checks/,/^SWIFT$/ { /^SWIFT$/!p; }' "$0" > "$transi_test_cache/main.swift"
{
    printf '%s\n' 'import Foundation' 'class TripPlannerController {}'
    awk '/^func isCityLine/,/^}/; /^func isTrain/,/^}/' "$transi_root/Shared/Util/Line.swift"
} > "$transi_test_cache/stubs.swift"
shared="$transi_root/Shared"
xcrun swiftc -module-cache-path "$transi_test_cache" -target "$(uname -m)-apple-macosx14.0" \
    -o "$transi_test_cache/check" \
    "$shared/Models/Trip.swift" "$shared/Models/StopGps.swift" "$shared/Models/ApiModels.swift" \
    "$shared/Models/AnyCodable.swift" "$shared/Models/Stops.swift" "$shared/Models/Table.swift" \
    "$shared/Models/TicketCatalogue.swift" \
    "$shared/Util/DateTime.swift" "$shared/Extensions/Date.swift" "$shared/Extensions/String.swift" \
    "$shared/Extensions/CLLocationCoordinate2D.swift" \
    "$shared/Controllers/TripPlannerController+Mapping.swift" \
    "$transi_test_cache/stubs.swift" "$transi_test_cache/main.swift"
"$transi_test_cache/check" "$transi_root/scripts/fixtures/ticket-types.json"
exit

: <<'SWIFT'
// Swift regression checks
import Foundation

struct Fixture: Decodable {
    let catalogue: TicketCatalogue
    let raptor: RApiTrip
}

// Same key strategy as the app's fetch decoder.
let apiDecoder = JSONDecoder()
apiDecoder.keyDecodingStrategy = .convertFromSnakeCase
let fixture = try apiDecoder.decode(
    Fixture.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
)
let catalogue = fixture.catalogue
let localFormatter = DateFormatter()
localFormatter.dateFormat = "yyyy-MM-dd HH:mm"
localFormatter.timeZone = TimeZone(identifier: "Europe/Bratislava")
func local(_ time: String) -> Date { localFormatter.date(from: time)! }

// Decoding and the on-disk cache.
assert(catalogue.zones?.count == 18 && catalogue.cacheKey == "2026-09-30T22:28:22.724Z", "Catalogue zones and key")
assert(catalogue.basicSingles.map(\.ticketId) == [804, 806, 808, 810, 812, 814, 816, 818, 820, 821],
       "Basic singles skip discounted, day and season tickets")
let unchanged = try apiDecoder.decode(TicketCatalogue.self, from: Data(#"{"cache_key":"2026-09-30T22:28:22.724Z"}"#.utf8))
assert(unchanged.tickets == nil && unchanged.zones == nil && unchanged.cacheKey == catalogue.cacheKey,
       "A current cache key comes back alone")
let cached = try JSONDecoder().decode(TicketCatalogue.self, from: JSONEncoder().encode(catalogue))
assert(cached == catalogue, "Cache round-trip")
// Only the cached key coming back alone confirms the cache; error bodies and other keys leave it unconfirmed.
let errorBody = try apiDecoder.decode(TicketCatalogue.self, from: Data(#"{"message":"Internal server error"}"#.utf8))
var keyless = catalogue
keyless.cacheKey = nil
let confirmCases: [(String, TicketCatalogue, TicketCatalogue, Bool)] = [
    ("same key alone", catalogue, unchanged, true),
    ("other key alone", catalogue, TicketCatalogue(cacheKey: "2026-10-01T00:00:00.000Z"), false),
    ("error body", catalogue, errorBody, false),
    ("cache without a key", keyless, errorBody, false),
    ("full catalogue", catalogue, catalogue, false),
]
for (name, cache, response, confirmed) in confirmCases {
    assert(cache.isConfirmed(by: response) == confirmed, "Confirm cache: \(name)")
}
print("PASS: catalogue decoding, basic singles, cache round-trip and \(confirmCases.count) cache confirmations")

// Zone ids (R-API) and names (I-API, offline).
func journey(_ id: String, zones: [String]?, legs: [(String?, String, String)], ticketId: Int? = nil) -> Journey {
    Journey(id: id, parts: legs.map { line, from, to in
        Part(startDeparture: local(from), endArrival: local(to), routeType: line == nil ? 64 : 3, routeShortName: line)
    }, zones: zones, ticketId: ticketId)
}
let cityLegs: [(String?, String, String)] = [("72", "2026-10-05 08:00", "2026-10-05 08:21"),
                                            (nil, "2026-10-05 08:21", "2026-10-05 08:31"),
                                            ("31", "2026-10-05 08:31", "2026-10-05 08:33")]
let zoneCases: [(String, [String]?, Set<String>?)] = [
    ("r-1", ["1955", "1953"], ["101", "100"]),
    ("r-2", ["64", "1955"], ["111", "101"]),
    ("i-1", ["100", "101"], ["100", "101"]),
    ("offline", ["101", "621"], ["101", "621"]),
    ("r-3", ["1953", "9999"], nil),
    ("i-2", ["1953"], nil),
    ("offline", ["100", "-"], nil),
    ("i-3", ["190"], nil),
    ("i-4", [], nil),
    ("i-5", nil, nil),
]
for (id, zones, expected) in zoneCases {
    assert(catalogue.zoneNames(of: journey(id, zones: zones, legs: cityLegs)) == expected, "\(id) \(zones ?? [])")
}
var noZones = catalogue
noZones.zones = nil
assert(noZones.zoneNames(of: journey("i-1", zones: ["100"], legs: cityLegs)) == nil, "No catalogue zones")
print("PASS: \(zoneCases.count + 1) zone id and name mappings")

// Single ticket selection; 100 and 101 count as two zones.
let ticketCases: [(Int, Int, Int)] = [
    (1, 10, 804), (2, 30, 804), (2, 31, 806), (2, 60, 806), (2, 61, 808), (3, 40, 808), (4, 60, 810),
    (9, 270, 820), (10, 30, 821), (2, 300, 821), (2, 301, 821),
]
for (zones, minutes, expected) in ticketCases {
    assert(catalogue.singleTicket(zoneCount: zones, minutes: minutes)?.ticketId == expected, "\(zones) zones, \(minutes) min")
}
let basic30 = catalogue.singleTicket(zoneCount: 2, minutes: 30)!
assert(basic30.price == 1.09 && basic30.timeDuration == 30 && basic30.zonesCount == 2 && basic30.currency == "EUR"
       && basic30.name == "Základný", "30 min, 2 zones, basic fare")
print("PASS: \(ticketCases.count) single ticket selections")

func ticket(_ id: Int) -> TicketCatalogue.Ticket { catalogue.tickets!.first { $0.ticketId == id }! }
func ticketId(_ coverage: TicketCoverage) -> Int? {
    switch coverage {
    case .notCovered(let ticket, _), .expired(_, _, let ticket), .partlyCovered(_, _, let ticket): return ticket.ticketId
    default: return nil
    }
}
// The R-API's ticket_id matches the derivation from zones and the time between boarding and alighting,
// trailing walks excluded; derived journeys reuse it.
let planner = TripPlannerController()
let rJourneys = planner.mapRApiToJourneys(fixture.raptor.journey ?? [])
for (index, rJourney) in rJourneys.enumerated() {
    let expected = fixture.raptor.journey![index].ticketId
    assert(ticketId(TicketCoverage(journey: rJourney, pass: nil, catalogue: catalogue)) == expected, "R-API ticket \(index)")
    var derived = rJourney
    derived.id = "i-\(index)"
    derived.zones = catalogue.zoneNames(of: rJourney).map { Array($0) }
    derived.ticketId = nil
    assert(ticketId(TicketCoverage(journey: derived, pass: nil, catalogue: catalogue)) == expected, "Derived ticket \(index)")
}
// The R-API ticket wins even where the derivation would differ.
assert(ticketId(TicketCoverage(journey: journey("r-1", zones: ["1953"], legs: cityLegs, ticketId: 808), pass: nil,
                               catalogue: catalogue)) == 808, "R-API ticket id")
print("PASS: \(rJourneys.count) real R-API ticket ids, as given and derived")

// Pass coverage: a 30-day 100+101 pass from 1 October is valid through 30 October.
let cityPass = SeasonPass(days: 30, validFrom: local("2026-10-01 15:42"), zones: ["100", "101"])
let october30 = local("2026-10-30 00:00")
assert(cityPass.start == local("2026-10-01 00:00") && cityPass.end == local("2026-10-31 00:00")
       && cityPass.lastDay == october30, "Pass days")
let city = journey("r-1", zones: ["1955", "1953"], legs: cityLegs)
func shifted(_ journey: Journey, to day: String) -> Journey {
    var journey = journey
    let offset = local("\(day) 08:00").timeIntervalSince(journey.parts![0].startDeparture)
    journey.parts = journey.parts!.map { part in
        var part = part
        part.startDeparture += offset
        part.endArrival += offset
        return part
    }
    return journey
}
// `journey` with stops in `zones` (nil: a stop without one), one list per transit leg.
func stopping(_ journey: Journey, in zones: [[String?]]) -> Journey {
    var journey = journey
    let transit = (journey.parts ?? []).indices.filter { journey.parts?[$0].routeType != 64 }
    for (index, legZones) in zip(transit, zones) {
        let time = journey.parts?[index].startDeparture ?? Date()
        journey.parts?[index].stops = legZones.map { PartStop(name: $0 ?? "-", time: time, zone: $0) }
    }
    return journey
}
let regional = stopping(journey("i-1", zones: ["101", "111"], legs: [("520", "2026-10-05 08:00", "2026-10-05 08:40")]),
                        in: [["101", "111"]])
let lateNight = journey("i-2", zones: ["100"], legs: [("N72", "2026-10-30 23:50", "2026-10-31 00:20")])
// A pass combines with a single ticket for the zones it lacks, on city lines and trains only, when the trip's stops
// in those zones are one run at its start or end; the R-API ticket is for the whole trip.
let cityAndTrainLegs: [(String?, String, String)] = [("72", "2026-10-05 08:00", "2026-10-05 08:10"),
                                                     (nil, "2026-10-05 08:10", "2026-10-05 08:13"),
                                                     ("S20", "2026-10-05 08:13", "2026-10-05 08:30")]
let cityAndTrainNoStops = journey("i-3", zones: ["100", "101", "111"], legs: cityAndTrainLegs, ticketId: 806)
let cityAndTrain = stopping(cityAndTrainNoStops, in: [["100", "100", "101"], ["101", "111"]])
let trainAndCity = stopping(journey("i-3", zones: ["111", "101", "100"],
                                    legs: [("S20", "2026-10-05 08:00", "2026-10-05 08:17"),
                                           (nil, "2026-10-05 08:17", "2026-10-05 08:20"),
                                           ("72", "2026-10-05 08:20", "2026-10-05 08:30")]),
                            in: [["111", "101"], ["101", "100"]])
// 111 -> 101 -> 100 -> 101 -> 221: the other zones lie on both sides of the pass zones.
let acrossTheCity = stopping(journey("i-3", zones: ["111", "101", "100", "221"],
                                     legs: [("S20", "2026-10-05 08:00", "2026-10-05 08:15"),
                                            ("72", "2026-10-05 08:20", "2026-10-05 08:40"),
                                            ("R 805", "2026-10-05 08:45", "2026-10-05 09:10")]),
                             in: [["111", "101"], ["101", "100", "100", "101"], ["101", "221"]])
func train(_ line: String, zones: [String?]) -> Journey {
    stopping(journey("i-1", zones: ["101", "111"], legs: [(line, "2026-10-05 08:00", "2026-10-05 08:40")]), in: [zones])
}
var bankCardCity = cityPass
bankCardCity.bankCard = true
let coverageCases: [(String, Journey, SeasonPass?, TicketCoverage)] = [
    ("city trip", city, cityPass, .covered(lastDay: october30)),
    ("first day", shifted(city, to: "2026-10-01"), cityPass, .covered(lastDay: october30)),
    ("last day", shifted(city, to: "2026-10-30"), cityPass, .covered(lastDay: october30)),
    ("after the pass", shifted(city, to: "2026-11-01"), cityPass,
     .expired(lastDay: october30, ended: false, ticket: ticket(806))),
    ("past midnight of the last day", lateNight, cityPass, .expired(lastDay: october30, ended: false, ticket: ticket(804))),
    ("before the pass", shifted(city, to: "2026-09-30"), cityPass, .notCovered(ticket: ticket(806))),
    ("city line, then train beyond the pass zones", cityAndTrain, cityPass,
     .partlyCovered(passZones: ["100", "101"], zones: ["111"], ticket: ticket(804))),
    ("train into the pass zones, then city line", trainAndCity, cityPass,
     .partlyCovered(passZones: ["100", "101"], zones: ["111"], ticket: ticket(804))),
    ("R-API zone ids, stop zone names", stopping(journey("r-1", zones: ["1953", "1955", "64"], legs: cityAndTrainLegs,
                                                         ticketId: 806), in: [["100", "101"], ["101", "111"]]), cityPass,
     .partlyCovered(passZones: ["100", "101"], zones: ["111"], ticket: ticket(804))),
    ("train two zones beyond", stopping(journey("i-1", zones: ["101", "111", "221"],
                                                legs: [("R 805", "2026-10-05 08:00", "2026-10-05 08:50")]),
                                        in: [["101", "111", "221"]]), cityPass,
     .partlyCovered(passZones: ["101"], zones: ["111", "221"], ticket: ticket(806))),
    // Passes in force that don't cover the trip say why: the zones they lack, or the bank-card limits.
    ("other zones on both sides", acrossTheCity, cityPass, .notCovered(ticket: ticket(810), reason: .zones(["111", "221"]))),
    ("other zone on both sides", train("S20", zones: ["111", "101", "111"]), cityPass, .notCovered(ticket: ticket(806), reason: .zones(["111"]))),
    ("other zone in the middle", train("S20", zones: ["101", "111", "101"]), cityPass, .notCovered(ticket: ticket(806), reason: .zones(["111"]))),
    ("stops in a zone the trip doesn't list", stopping(cityAndTrainNoStops, in: [["100", "101"], ["101", "111", "221"]]),
     cityPass, .notCovered(ticket: ticket(806), reason: .zones(["111"]))),
    ("no stops", cityAndTrainNoStops, cityPass, .notCovered(ticket: ticket(806), reason: .zones(["111"]))),
    ("one leg without stops", stopping(cityAndTrainNoStops, in: [["100", "101"]]), cityPass, .notCovered(ticket: ticket(806), reason: .zones(["111"]))),
    ("a stop without a zone", stopping(cityAndTrainNoStops, in: [["100", "101"], ["101", nil, "111"]]), cityPass, .notCovered(ticket: ticket(806), reason: .zones(["111"]))),
    ("unmapped line", train("Err", zones: ["101", "111"]), cityPass, .notCovered(ticket: ticket(806), reason: .zones(["111"]))),
    ("unknown line", train("?", zones: ["101", "111"]), cityPass, .notCovered(ticket: ticket(806), reason: .zones(["111"]))),
    // Regional buses take no ticket for the other zones alongside a pass, so the trip needs one of its own.
    ("regional bus beyond the pass zones", regional, cityPass, .notCovered(ticket: ticket(806), reason: .regionalBus(["111"]))),
    ("train and regional bus", stopping(journey("i-1", zones: ["101", "111"],
                                                legs: [("S20", "2026-10-05 08:00", "2026-10-05 08:20"),
                                                       ("520", "2026-10-05 08:25", "2026-10-05 08:40")]),
                                        in: [["101"], ["101", "111"]]),
     cityPass, .notCovered(ticket: ticket(806), reason: .regionalBus(["111"]))),
    ("regional bus 901, zones on both sides", stopping(journey("i-1", zones: ["111", "101", "221"],
                                                               legs: [("901", "2026-10-05 08:00", "2026-10-05 08:40")]),
                                                       in: [["111", "101", "221"]]),
     cityPass, .notCovered(ticket: ticket(808), reason: .regionalBus(["111", "221"]))),
    ("regional bus outside the pass zones", journey("i-1", zones: ["111", "221"],
                                                    legs: [("520", "2026-10-05 08:00", "2026-10-05 08:20")]), cityPass,
     .notCovered(ticket: ticket(804), reason: .zones(["111", "221"]))),
    ("bank-card pass and train", cityAndTrain, bankCardCity, .notCovered(ticket: ticket(806), reason: .bankCard)),
    ("bank-card pass and city line beyond its zones", stopping(journey("i-1", zones: ["101", "111"],
                                                                     legs: [("37", "2026-10-05 08:00", "2026-10-05 08:30")]),
                                                             in: [["101", "111"]]), bankCardCity,
     .notCovered(ticket: ticket(804), reason: .bankCard)),
    ("train before the pass", shifted(cityAndTrain, to: "2026-09-30"), cityPass, .notCovered(ticket: ticket(806))),
    ("train outside the pass zones", journey("i-1", zones: ["111", "221"],
                                             legs: [("S20", "2026-10-05 08:00", "2026-10-05 08:20")]), cityPass,
     .notCovered(ticket: ticket(804), reason: .zones(["111", "221"]))),
    ("network-wide", regional, SeasonPass(days: 7, validFrom: local("2026-10-05 00:00"), zones: [], networkWide: true),
     .covered(lastDay: local("2026-10-11 00:00"))),
    ("regional zones", regional, SeasonPass(days: 365, validFrom: local("2026-01-01 00:00"), zones: ["101", "111"]),
     .covered(lastDay: local("2026-12-31 00:00"))),
    ("no pass", city, nil, .notCovered(ticket: ticket(806))),
    ("no catalogue", city, cityPass, .unknown),
    ("walk only", journey("i-1", zones: nil, legs: [(nil, "2026-10-05 08:00", "2026-10-05 08:10")]), cityPass, .noTransit),
]
let today = local("2026-10-04 12:00")
for (name, journey, pass, expected) in coverageCases {
    let coverage = TicketCoverage(journey: journey, pass: pass, catalogue: name == "no catalogue" ? nil : catalogue,
                                  now: today)
    assert(coverage == expected, "\(name): \(coverage)")
}
// "Expired" only once the last day is over; until midnight the pass merely ends before this trip.
let expiryCases: [(String, Bool)] = [
    ("2026-10-30 00:00", false), ("2026-10-30 18:00", false), ("2026-10-30 23:59", false),
    ("2026-10-31 00:00", true), ("2026-10-31 00:10", true),
]
for (now, ended) in expiryCases {
    assert(TicketCoverage(journey: lateNight, pass: cityPass, catalogue: catalogue, now: local(now))
           == .expired(lastDay: october30, ended: ended, ticket: ticket(804)), "Pass ended at \(now)")
}
print("PASS: \(coverageCases.count) covered, partly covered, expired and not covered cases; \(expiryCases.count) expiry times")

// Bank-card passes: DPB city lines in zones 100 and 101 only.
var bankCard = cityPass
bankCard.bankCard = true
bankCard.zones = ["100", "101", "111"]
let bankCardCases: [(String, [(String?, String, String)], [String], Bool)] = [
    ("city lines", cityLegs, ["100", "101"], true),
    ("night and replacement lines", [("N72", "2026-10-05 08:00", "2026-10-05 08:10"),
                                     ("X13", "2026-10-05 08:12", "2026-10-05 08:20")], ["100"], true),
    ("regional bus in the city", [("727", "2026-10-05 08:00", "2026-10-05 08:10")], ["101"], false),
    ("train", [("S20", "2026-10-05 08:00", "2026-10-05 08:10")], ["100"], false),
    ("named train", [("R 805", "2026-10-05 08:00", "2026-10-05 08:10")], ["100"], false),
    ("line 200", [("200", "2026-10-05 08:00", "2026-10-05 08:10")], ["101"], false),
    ("901 to Hainburg", [("901", "2026-10-05 08:00", "2026-10-05 08:10")], ["100"], false),
    ("city line into zone 111", [("37", "2026-10-05 08:00", "2026-10-05 08:30")], ["101", "111"], false),
]
for (name, legs, zones, covered) in bankCardCases {
    let coverage = TicketCoverage(journey: journey("i-1", zones: zones, legs: legs), pass: bankCard, catalogue: catalogue)
    if case .notCovered(_, let reason) = coverage {
        assert(!covered && reason == .bankCard, "Bank card, \(name): \(coverage)")
    } else {
        assert(covered && coverage == .covered(lastDay: october30), "Bank card, \(name): \(coverage)")
    }
}
var cardOff = bankCard
cardOff.bankCard = false
assert(TicketCoverage(journey: journey("i-1", zones: ["101"], legs: [("727", "2026-10-05 08:00", "2026-10-05 08:10")]),
                      pass: cardOff, catalogue: catalogue) == .covered(lastDay: october30), "IDS BK passes cover regional lines")
print("PASS: \(bankCardCases.count + 1) bank-card pass cases")

// Stored settings: zone 100 never without 101.
let toggleCases: [(String, String, String)] = [
    ("100", "", "100,101"), ("100", "111", "100,101,111"), ("101", "", "101"), ("111", "101", "101,111"),
    ("100", "100,101,111", "111"), ("101", "100,101,111", "111"), ("111", "100,101,111", "100,101"),
]
for (zone, stored, expected) in toggleCases {
    assert(SeasonPass.toggling(zone, in: stored) == expected, "Toggle \(zone) in \(stored)")
}
assert(SeasonPass(days: 0, validFrom: 0, zones: "100,101", networkWide: false, bankCard: false) == nil, "No pass")
assert(SeasonPass(days: 90, validFrom: 0, zones: "100,101,111", networkWide: true, bankCard: true)
       == SeasonPass(days: 90, validFrom: Date(timeIntervalSinceReferenceDate: 0), zones: ["100", "101", "111"],
                     networkWide: true, bankCard: true), "Stored pass")
print("PASS: \(toggleCases.count) zone toggles and stored pass settings")

// IDS BK opens in the app first, then its App Store page.
let links = IdsBkLinks.openOrder.compactMap(URL.init(string:))
assert(links.map(\.scheme) == ["com.casperise.urbi.online.bid", "itms-apps", "https"]
       && links.dropFirst().allSatisfy { $0.path == "/app/id1360894243" || $0.path == "/sk/app/id1360894243" },
       "IDS BK app, then App Store")
print("PASS: IDS BK link order")
SWIFT
