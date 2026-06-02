# Offline Trip Planner Replacement Design

## Goal

Build an offline trip planner that can replace the combined R API and I API route search for users who download timetable data. Offline routing should return the same or more meaningful options than the online APIs, complete within 5 seconds on a normal phone, and support a future server-side version that can include realtime delays.

## Current Findings

The current `OfflineRoutingEngine` can return some city-only trips, but it is not yet a replacement for the online APIs.

- City routes return in roughly 0.6-2.4 seconds in measured cases, but with too few options and sometimes with departures before the requested departure time.
- Regional bus, regional train, and long suburban cases timed out under a 20-second harness.
- `arrivalDeparture` is accepted by `TimetableDatabase.queryOfflineTrip(...)` but is not passed into the engine, so offline arrival searches currently behave like departure searches.
- Stop matching is too narrow for train and regional GTFS naming. Examples include `Hlavná stanica` versus `Bratislava hl.st.`, `Stn. Petržalka` versus `Bratislava-Petržalka`, and `Pezinok, Žel. stanica` versus `Pezinok`.
- Walking transfers are limited to same normalized stop names, while good online results often depend on nearby physical transfers between city, regional, and train stops.

## Architecture

Replace the current per-start BFS core with a timetable routing engine based on rounds by transfer count.

The public app contract remains stable:

```swift
TimetableDatabase.queryOfflineTrip(
    fromName: String,
    toName: String,
    date: Date,
    arrivalDeparture: ArrivalDeparture,
    maxTransfers: Int,
    maxWalkDuration: Int,
    completion: @escaping ([Journey]) -> Void
)
```

Internally, `OfflineRoutingEngine` should build richer route labels and map them back to `[Journey]` for current UI compatibility. Future UI/API work can expose grouped transfer alternatives explicitly without changing the core router again.

## Routing Context

For each query date, build a compact routing context:

- Active service IDs per feed for the requested service date.
- Stop metadata from `base.stops`, including GTFS stop ID, feed, name, normalized name, coordinate, platform code, and zone.
- Route/trip metadata from `base.routes` and `schedule.trips`.
- Stop times indexed by trip and by stop.
- Boarding indexes that can find the next usable trip for a stop and route pattern without scanning every passing trip from every graph state.
- Nearby walking links for origin, transfer, and destination access.

The first implementation can compute context in-app from existing `base.db` and `schedule.db`. API build-time precomputation may be added later if profiling shows it is needed.

## Stop Matching And Walking

Input stop names come from the app stop list and remain the user-facing contract. The router should resolve them into GTFS stop candidates using:

- Exact GTFS name matches.
- Known alias mappings for train and regional naming differences.
- Same physical-place clusters using coordinates.
- Nearby stop links within the user `maxWalkDuration`.

Walking links are allowed:

- From the requested origin to nearby boardable stops.
- Between transfer stops.
- From alighting stops to the requested destination.

Walking must be capped by `maxWalkDuration`, counted in ranking, and exposed as normal `routeType == 64` journey parts when it is part of the selected representative journey.

## Search Behavior

Departure search:

- Do not return journeys whose first departure is before the requested departure time.
- Prefer earlier arrival, then lower transfer count, then lower walking time, then lower waiting time.
- Search across midnight when a valid journey continues into the next service day.

Arrival search:

- Implement real arrival-mode behavior instead of using departure-mode search.
- Prefer later departure that still arrives by the requested arrival time, then lower transfer count, then lower walking time, then lower waiting time.

The router should include city, regional bus, train, and mixed city+regional/city+train trips. It should return enough candidates before grouping to exceed the combined meaningful output of R API and I API.

## Equivalent Journey Grouping

After routing, group variants that are effectively the same passenger choice.

Two journeys are equivalent when they have:

- The same ordered transit line sequence.
- The same requested origin and destination.
- Arrival times within 2-3 minutes.
- Transfer differences only among adjacent or equivalent stops.

The result list should show one representative journey. The representative should keep metadata for alternatives such as "transfer also possible at X, Y, Z" so future UI/API can expose that choice. Until the current `Journey` model is expanded, grouped alternatives can be held in an internal result model and only the representative can be mapped to `[Journey]`.

## Performance Target

All measured replacement cases must complete under 5 seconds. Faster is preferred:

- City-only routes should usually complete under 1 second.
- Regional/train routes should usually complete under 2 seconds.
- The engine may return the first ranked results before doing deeper optional search, but the current UI contract only needs a final `[Journey]` callback.

The engine should avoid per-start full-graph BFS. It should keep labels per stop and transfer round, prune dominated labels, and avoid repeated expansion of equivalent states.

## Testing And Verification

Create deterministic offline tests against local timetable DBs for these cases:

- `Hronská -> Most SNP` at 08:00.
- `Zlaté piesky -> Hlavná stanica` at 08:00.
- `Hlavná stanica -> Stn. Petržalka` at 08:00.
- `Autobusová stanica -> Rovinka, Obecný úrad` at 08:00.
- `Hlavná stanica -> Pezinok, Žel. stanica` at 08:00.
- `Most SNP -> Senec, Žel. stanica` at 08:00.
- `Hronská -> Most SNP` at 23:30.
- At least one arrival-mode query.

Create a dev-only comparison harness that calls the live R API and I API, then prints:

- Online counts.
- Offline counts before and after grouping.
- First departure and arrival.
- Line sequences.
- Elapsed offline time.
- Cases where offline returns fewer meaningful options than combined online results.

The first replacement pass is successful when:

- Every measured query returns under 5 seconds.
- Offline returns at least the same meaningful option count as the combined online APIs after grouping.
- Departure-mode results do not start before the requested time.
- Regional bus and train cases do not time out.
- Arrival mode is tested and behaves differently from departure mode.
