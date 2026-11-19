#!/bin/bash
set -euo pipefail

# Decodes a hand-written sample of each api.magicsk.eu /timetable response (trip planner and route timetables)
# into the app's models with the app's decoder settings, and checks the timetable endpoint URLs.
transi_root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/transi-server-decoding.XXXXXX")"
trap 'rm -r -- "$work"' EXIT

sed -n '/^\/\/ Swift regression checks/,/^SWIFT$/ { /^SWIFT$/!p; }' "$0" > "$work/main.swift"
xcrun swiftc -module-cache-path "$work/cache" \
    "$transi_root/Shared/Models/Trip.swift" "$transi_root/Shared/Models/StopGps.swift" \
    "$transi_root/Shared/Models/Timetables.swift" "$transi_root/Shared/Util/DateTime.swift" \
    "$work/main.swift" -o "$work/check"
"$work/check"
exit

: <<'SWIFT'
// Swift regression checks
import Foundation

// Same settings as the shared decoder in Shared/Util/Fetch.swift.
let decoder = JSONDecoder()
decoder.keyDecodingStrategy = .convertFromSnakeCase
func decode<T: Decodable>(_ type: T.Type, _ json: String) -> T {
    do { return try decoder.decode(type, from: Data(json.utf8)) } catch { fatalError("\(T.self): \(error)") }
}

// 2026-11-19T07:30:00Z is unix 1795073400, so Swift reference seconds 816766200.
let departure = Date(timeIntervalSince1970: 1_795_073_400)
let trip = decode(ServerTrip.self, """
{"journeys":[{"id":"s-0","zones":["100"],"parts":[
  {"start_stop_name":"Hronská","end_stop_name":"Hronská","start_stop_code":"A","end_stop_code":"B",
   "start_departure":816766200,"end_arrival":816766260,"route_type":64,
   "start_stop_gps":{"lon":17.2,"lat":48.1},"end_stop_gps":{"lon":17.21,"lat":48.11}},
  {"start_stop_name":"Hronská","end_stop_name":"Pažítková","start_stop_code":"B","end_stop_code":"A",
   "start_departure":816766320,"end_arrival":816766980.5,"route_type":3,"trip_headsign":"Hlavná stanica",
   "route_short_name":"X99","start_stop_gps":{"lon":17.21,"lat":48.11},"end_stop_gps":{"lon":17.13,"lat":48.15},
   "stops":[{"name":"Hronská","platform":"B","time":816766320,"gps":{"lon":17.21,"lat":48.11},"zone":"100",
             "is_request_stop":false,"stop_id":123},
            {"name":"Pažítková","platform":null,"time":816766980.5,"zone":"100","is_request_stop":true}]}
]}]}
""")
let journey = trip.journeys[0]
assert(trip.journeys.count == 1 && journey.id == "s-0" && journey.zones == ["100"])
let ride = journey.parts![1]
assert(journey.parts![0].startDeparture == departure && journey.parts![0].routeType == 64)
assert(ride.endArrival == Date(timeIntervalSinceReferenceDate: 816_766_980.5) && ride.routeShortName == "X99")
assert(ride.startStopGps == StopGps(lon: 17.21, lat: 48.11) && ride.tripHeadsign == "Hlavná stanica")
assert(ride.stops?.count == 2 && ride.stops?[0].stopId == 123 && ride.stops?[1].isRequestStop == true)
assert(decode(ServerTrip.self, #"{"journeys":[]}"#).journeys.isEmpty)
// An error reply (e.g. the 404 for a stop name the server can't resolve) must fail, so the planner falls back.
assert((try? decoder.decode(ServerTrip.self, from: Data(#"{"error":"Unknown stop: Hronská"}"#.utf8))) == nil)

let routes = decode(Timetables.self, """
{"routes":[{"route_id":42,"short_name":"9","long_name":"Karlova Ves - Ružinov","description":null,
            "route_type":0,"color":"E31E24","text_color":"FFFFFF"},
           {"route_id":7,"short_name":"N33","long_name":"","route_type":3}]}
""").routes
assert(routes.map(\.id) == [42, 7] && routes[0].color == "E31E24" && routes[1].textColor == nil)
assert(routes.allSatisfy { $0.source == .bApi }, "Decoded routes default to the B API; the list's fetcher tags them")

let directions = decode(Directions.self, #"{"directions":[{"direction_id":0,"direction":"Karlova Ves"},{"direction_id":-1,"direction":"Ružinov"}]}"#).all
assert(directions.map(\.id) == [0, -1] && directions[1].name == "Ružinov")

let departures = decode(Departures.self, """
{"departures":[{"trip_id":0,"trip_flags":0,"trip_headsign":"Karlova Ves","departure":275,"route_type":0,
  "external_id":"trip-1","direction_departures":[
    {"station_id":0,"station_name":"Ružinov","departure":275,"stop_code":"000000012300"},
    {"station_id":1,"station_name":"Karlova Ves","departure":301}]}]}
""").all
assert(departures[0].headsign == "Karlova Ves" && departures[0].externalId == "trip-1")
assert(departures[0].directionDepartures[0].stopCode == "000000012300" && departures[0].directionDepartures[1].stopCode == nil)

let details = decode(TimetableDetails.self, #"{"departures":[{"t":275,"trip_id":0},{"t":1445,"trip_id":0}]}"#).all
assert(details.map(\.t) == [275, 1445])

// Endpoints: date in the device's zone, direction names and "+" encoded.
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = .current
let date = calendar.date(from: DateComponents(year: 2026, month: 11, day: 19, hour: 0, minute: 30))!
let route = Route(routeId: 42, shortName: "9", longName: "", routeType: 0, source: .server)
let departuresURL = route.serverEndpoint("departures", direction: Direction(directionId: -1, direction: "A + B & C"), date: date)
assert(departuresURL == "/timetable/routes/42/departures?direction_id=-1&direction=A%20%2B%20B%20%26%20C&date=2026-11-19", departuresURL)
let stopURL = route.serverEndpoint("stop-departures", direction: directions[0], date: date, stopId: "000000012300")
assert(stopURL == "/timetable/routes/42/stop-departures?direction_id=0&direction=Karlova%20Ves&date=2026-11-19&stop_id=000000012300", stopURL)

print("server timetable decoding checks passed")
SWIFT
