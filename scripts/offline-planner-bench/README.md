# Offline planner bench

Runs offline `planTrip` on `queries.json` (30 seeded Bratislava pairs, Mon 2026-11-23) and scores it against the online planners. Run from this folder; use copies of the timetable DBs (they open read-write).

1. `node online.mjs ../../Release.xcconfig > online.jsonl` fetches the online journeys (URLs and keys are read from that file).
2. `swiftc -O ../../Shared/Util/SQLite.swift ../../Shared/Extensions/{Date,String,CLLocationCoordinate2D}.swift ../../Shared/Util/DateTime.swift ../../Shared/Models/{Trip,StopGps,Stops}.swift ../../Shared/Controllers/Offline{RoutingTypes,RoutingContext,StopResolver,TimetableRouter,JourneyGrouper,RoutingEngine}.swift bench.swift -o /tmp/offline-bench`
3. `TRANSI_BASE_DB=… TRANSI_SCHEDULE_DB=… TRANSI_STOPS_JSON=…/stops.json /tmp/offline-bench queries.json > offline.jsonl`, then `node score.mjs offline.jsonl [baseline.jsonl]`.
