//
//  TransiWatchWidget.swift
//  Transi Watch Widget
//
//  Created by magic_sk on 19/11/2026.
//

import AppIntents
import SwiftUI
import WidgetKit

@main
struct TransiWatchWidgetBundle: WidgetBundle {
    var body: some Widget {
        DeparturesWidget()
    }
}

struct DeparturesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetStore.departuresKind, intent: SelectStopIntent.self, provider: DeparturesProvider()
        ) { entry in
            DeparturesWidgetView(entry: entry)
        }
        .configurationDisplayName("Departures")
        .description("The next departures from the nearest or a favorite stop.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

// MARK: - Configuration

struct StopEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Stop"
    static let defaultQuery = StopEntityQuery()

    let id: Int
    let name: String

    init(_ stop: Stop) {
        id = stop.id
        name = stop.name ?? "\(stop.id)"
    }

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

/// The stops the watch app left in the App Group.
private func knownStops() -> [Stop] {
    WidgetStore.favoriteStops + [WidgetStore.nearestStop].compactMap { $0 }
}

struct StopEntityQuery: EntityQuery {
    func entities(for identifiers: [Int]) async throws -> [StopEntity] {
        let stops = knownStops()
        return identifiers.compactMap { id in stops.first { $0.id == id }.map(StopEntity.init) }
    }

    func suggestedEntities() async throws -> [StopEntity] {
        WidgetStore.favoriteStops.map(StopEntity.init)
    }
}

struct SelectStopIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Departures"
    static let description = IntentDescription("The next departures from a stop.")

    /// nil follows the stop nearest the watch.
    @Parameter(title: "Stop")
    var stop: StopEntity?

    init() {}

    init(stop: StopEntity?) {
        self.stop = stop
    }
}

// MARK: - Timeline

extension DeparturesEntry: TimelineEntry {}

struct DeparturesProvider: AppIntentTimelineProvider {
    func placeholder(in _: Context) -> DeparturesEntry { .example }

    func snapshot(for configuration: SelectStopIntent, in context: Context) async -> DeparturesEntry {
        if context.isPreview { return .example }
        return await timeline(for: configuration, in: context).entries.first ?? .example
    }

    func timeline(for configuration: SelectStopIntent, in _: Context) async -> Timeline<DeparturesEntry> {
        let now = Date()
        // A chosen stop the app no longer knows falls back to the nearest one.
        let chosen = configuration.stop.flatMap { entity in knownStops().first { $0.id == entity.id } }
        guard let stop = chosen ?? WidgetStore.nearestStop else {
            // The app reloads this timeline once it knows a stop.
            return Timeline(entries: [DeparturesEntry(date: now, state: .noStop)], policy: .never)
        }
        let stopName = stop.name ?? ""
        let stopId = chosen?.id ?? -1
        do {
            let departures = try await fetchDepartures(at: stop, now: now)
            // An hour of entries: the reload below is throttled past 15 min when the budget runs low, and the last
            // entry's minutes would otherwise stay on screen after those vehicles left.
            let entries = departureEntries(departures, stopName: stopName, stopId: stopId, from: now, minutes: 60)
            return Timeline(entries: entries, policy: .after(now + 15 * 60))
        } catch {
            let entry = DeparturesEntry(date: now, stopName: stopName, stopId: stopId, state: .failed)
            return Timeline(entries: [entry], policy: .after(now + 5 * 60))
        }
    }

    /// On watchOS these are the configurations people pick from.
    func recommendations() -> [AppIntentRecommendation<SelectStopIntent>] {
        [AppIntentRecommendation(intent: SelectStopIntent(), description: "Nearest stop")]
            + WidgetStore.favoriteStops.map { stop in
                AppIntentRecommendation(
                    intent: SelectStopIntent(stop: StopEntity(stop)), description: Text(verbatim: stop.name ?? "")
                )
            }
    }
}

// MARK: Timeline entries

struct WidgetDeparture: Hashable {
    let line: String
    let headsign: String
    /// The platform letter, empty when unknown.
    let platform: String
    let time: Date
    /// Live position data, not just the timetable.
    let isLive: Bool
    /// Time left at the entry's date as the app's board shows it, like "3 min"; `shortRemaining` is like "3m".
    var remaining = ""
    var shortRemaining = ""
}

struct DeparturesEntry {
    enum State: Hashable {
        case departures([WidgetDeparture])
        case noStop
        case failed
    }

    let date: Date
    var stopName = ""
    /// -1 for the nearest-stop configuration.
    var stopId = -1
    let state: State

    var isNearest: Bool { stopId == -1 }
}

/// `minutes` (at least 1) entries: one now, then one at the start of each following minute. Each holds the next three
/// of `departures` (sorted) still to leave at its date and the time left from that date.
func departureEntries(
    _ departures: [WidgetDeparture], stopName: String, stopId: Int, from now: Date, minutes: Int
) -> [DeparturesEntry] {
    let minuteStart = (now.timeIntervalSince1970 / 60).rounded(.down) * 60
    let dates = [now] + (1 ..< minutes).map { Date(timeIntervalSince1970: minuteStart + Double($0) * 60) }
    let entries = dates.map { date in
        let next = departures.filter { $0.time > date }.prefix(3).map { departure in
            var departure = departure
            let clock = timeStringFromDate(departure.time)
            let raw = departure.time.timeIntervalSince1970
            let type = departure.isLive ? "online" : "cp"
            departure.remaining = getDepartureTimeRemainingText(clock, raw, type, now: date)
            departure.shortRemaining = getShortDepartureTimeRemainingText(clock, raw, type, now: date)
            return departure
        }
        return DeparturesEntry(date: date, stopName: stopName, stopId: stopId, state: .departures(Array(next)))
    }
    // Once nothing is left to show, later entries would only repeat that.
    let firstEmpty = entries.firstIndex { $0.state == .departures([]) } ?? entries.count - 1
    return Array(entries[...firstEmpty])
}

// MARK: End timeline entries

extension DeparturesEntry {
    static let example = DeparturesEntry(
        date: .now, stopName: "Hronská", stopId: -1,
        state: .departures([
            WidgetDeparture(line: "72", headsign: "Stn. Vrakuňa", platform: "A", time: .now, isLive: true, remaining: "3 min"),
            WidgetDeparture(line: "78", headsign: "Hlavná stanica", platform: "B", time: .now, isLive: false, remaining: "~7 min"),
            WidgetDeparture(line: "71", headsign: "Most SNP", platform: "A", time: .now, isLive: true, remaining: "12 min"),
        ])
    )
}

// MARK: - B-API

private let bApiUrl = Bundle.main.infoDictionary?["B_API_URL"] as? String ?? ""
private let bApiKey = Bundle.main.infoDictionary?["B_API_KEY"] as? String ?? ""

private func fetchBApi<T: Decodable>(
    _ endpoint: String, _: T.Type, session: String? = nil, jsonBody: Data? = nil
) async throws -> T {
    guard let url = URL(string: bApiUrl + endpoint) else { throw URLError(.badURL) }
    var request = URLRequest(url: url, timeoutInterval: 15)
    request.setValue(S_USER_AGENT, forHTTPHeaderField: "User-Agent")
    request.setValue(bApiKey, forHTTPHeaderField: "x-api-key")
    request.setValue(session, forHTTPHeaderField: "x-session")
    if let jsonBody {
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonBody
    }
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let status = (response as? HTTPURLResponse)?.statusCode, 200 ..< 300 ~= status else {
        throw URLError(.badServerResponse)
    }
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return try decoder.decode(T.self, from: data)
}

/// The stop's departures from `now` on, live and timetabled, soonest first. The station timetable also carries city
/// lines with their live delay, so this works without the phone or the app's socket.
private func fetchDepartures(at stop: Stop, now: Date) async throws -> [WidgetDeparture] {
    guard let stationId = stop.stationId else { throw URLError(.badURL) }
    // ponytail: a new session per timeline (about every 15 min); keep it in the App Group if startup gets throttled.
    let session = try await fetchBApi(
        "/mobile/v1/startup", Session.self, jsonBody: JSONEncoder().encode(SessionReq())
    ).session
    let calendar = Calendar.current
    let minutes = calendar.component(.hour, from: now) * 60 + calendar.component(.minute, from: now)
    let response = try await fetchBApi(
        "/mobile/v1/station/\(stationId)/timetable/\(actualDateString())/\(minutes)/1",
        RegionalConnectionsResponse.self, session: session
    )
    return response.current
        .map { Connection(from: $0, for: stop) }
        .filter { $0.departureTimeRaw > now.timeIntervalSince1970 && !terminates($0, at: stop.name) }
        .sorted { $0.departureTimeRaw < $1.departureTimeRaw }
        .map { connection in
            WidgetDeparture(
                line: connection.line,
                headsign: connection.headsign.replacingOccurrences(of: "Bratislava, ", with: ""),
                platform: shownPlatformLabel(stop.platformLabels, connection.platform),
                time: Date(timeIntervalSince1970: connection.departureTimeRaw),
                isLive: connection.type == "online"
            )
        }
}
