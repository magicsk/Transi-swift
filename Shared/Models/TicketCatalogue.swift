//
//  TicketCatalogue.swift
//  Transi
//
//  Created by magic_sk on 04/10/2026.
//

import Foundation

/// The official IDS BK app. It publishes no ticket or purchase deep links; its URL scheme opens the home screen.
enum IdsBkLinks {
    static let app = "com.casperise.urbi.online.bid://"
    static let appStore = "itms-apps://apps.apple.com/app/id1360894243"
    static let appStoreWeb = "https://apps.apple.com/sk/app/id1360894243"
    /// Tried in order until one opens: the app, else its App Store page.
    static let openOrder = [app, appStore, appStoreWeb]
}

/// B-API `/mobile/v1/ticket/types/{cache_key}`. While `cache_key` is current only `cacheKey` comes back.
struct TicketCatalogue: Codable, Equatable, Sendable {
    var tickets: [Ticket]?
    var zones: [Zone]?
    var cacheKey: String?

    struct Ticket: Codable, Equatable, Sendable {
        var ticketId: Int
        var categoryId: Int
        var ticketType: Int
        /// Nil for network-wide tickets.
        var zonesCount: Int?
        var name: String
        var price: Double
        var currency: String
        /// Minutes.
        var timeDuration: Int
        var discounted: Bool
    }

    struct Zone: Codable, Equatable, Sendable {
        var zoneId: Int
        /// Like "100".
        var zoneName: String
        var zoneDescription: String?
    }

    /// Full-fare single-journey tickets ("Základné lístky"), network-wide included.
    var basicSingles: [Ticket] {
        (tickets ?? []).filter { $0.categoryId == 300 && $0.ticketType == 2 && !$0.discounted }
    }

    /// The cheapest basic single ticket for `zoneCount` zones lasting `minutes`; the network-wide one when none lasts long enough.
    func singleTicket(zoneCount: Int, minutes: Int) -> Ticket? {
        let singles = basicSingles
        return singles.filter { ($0.zonesCount ?? .max) >= zoneCount && $0.timeDuration >= minutes }
            .min { $0.price < $1.price }
            ?? singles.first { $0.zonesCount == nil }
    }

    /// Whether `response`, fetched with this catalogue's cache key, says it is still current: the same key comes back alone.
    func isConfirmed(by response: TicketCatalogue) -> Bool {
        cacheKey != nil && response.cacheKey == cacheKey && response.tickets == nil
    }

    /// The journey's fare zone names; R-API journeys carry catalogue zone ids. Nil when a zone is not in the catalogue.
    func zoneNames(of journey: Journey) -> Set<String>? {
        guard let zones, let journeyZones = journey.zones, !journeyZones.isEmpty else { return nil }
        let byId = journey.id.hasPrefix("r-")
        var names = Set<String>()
        for journeyZone in journeyZones {
            guard let zone = zones.first(where: { byId ? String($0.zoneId) == journeyZone : $0.zoneName == journeyZone })
            else { return nil }
            names.insert(zone.zoneName)
        }
        return names
    }
}

/// A season pass (PCL) from the "My pass" settings.
struct SeasonPass: Equatable {
    /// Zone 100 is sold only together with 101; passes bought with a bank card are valid only in these.
    static let cityZones: Set<String> = ["100", "101"]
    static let durations = [7, 30, 90, 365]
    /// Bratislava days in the medium date style, as DatePicker shows them. `Date.FormatStyle`'s `.abbreviated` takes its
    /// pattern from the language alone, so it ignores the region format ("Nov 2, 2026" for English in Slovakia).
    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeZone = Calendar.bratislava.timeZone
        return formatter
    }()

    var days: Int
    var validFrom: Date
    var zones: Set<String>
    var networkWide = false
    /// Bought with a bank card through DPB: valid only on DPB city lines in zones 100 and 101.
    var bankCard = false

    var start: Date { Calendar.bratislava.startOfDay(for: validFrom) }
    /// Midnight after the last valid day.
    var end: Date { Calendar.bratislava.date(byAdding: .day, value: days, to: start) ?? start }
    var lastDay: Date { Calendar.bratislava.date(byAdding: .day, value: -1, to: end) ?? start }

    /// Why a pass doesn't cover a trip.
    enum Mismatch: Equatable {
        /// Bank-card passes are valid only on city lines in zones 100 and 101.
        case bankCard
        /// Zones the trip passes through that the pass lacks.
        case zones([String])
    }

    /// Why the pass isn't valid in every one of `zones` on every `transit` leg; nil when it is.
    func mismatch(in zones: Set<String>, on transit: [Part]) -> Mismatch? {
        if bankCard, !zones.isSubset(of: Self.cityZones) || !transit.allSatisfy({ isCityLine($0.routeShortName ?? "") }) {
            return .bankCard
        }
        let missing = networkWide ? [] : zones.subtracting(self.zones)
        return missing.isEmpty ? nil : .zones(missing.sorted())
    }
}

extension SeasonPass {
    /// The stored settings; nil without a pass. `validFrom` is seconds since the reference date.
    init?(days: Int, validFrom: Double, zones: String, networkWide: Bool, bankCard: Bool) {
        guard days > 0 else { return nil }
        self.init(days: days, validFrom: Date(timeIntervalSinceReferenceDate: validFrom),
                  zones: Self.zoneSet(zones), networkWide: networkWide, bankCard: bankCard)
    }

    /// Stored zones are comma-separated names.
    static func zoneSet(_ stored: String) -> Set<String> {
        Set(stored.split(separator: ",").map(String.init))
    }

    /// `stored` with `zone` switched; switching on 100 adds 101, switching off either city zone drops both.
    static func toggling(_ zone: String, in stored: String) -> String {
        var zones = zoneSet(stored)
        if zones.contains(zone) {
            zones.subtract(cityZones.contains(zone) ? cityZones : [zone])
        } else {
            zones.formUnion(zone == "100" ? cityZones : [zone])
        }
        return zones.sorted().joined(separator: ",")
    }
}

enum TicketCoverage: Equatable {
    /// The pass covers the whole journey.
    case covered(lastDay: Date)
    /// The pass ends before the journey does; `ended` once its last day is over.
    case expired(lastDay: Date, ended: Bool, ticket: TicketCatalogue.Ticket)
    /// The pass covers `passZones`; `ticket` covers the other `zones`, combined as IDS BK allows (PP A.12.8, A.12.9).
    case partlyCovered(passZones: [String], zones: [String], ticket: TicketCatalogue.Ticket)
    /// `reason` says why a pass in force for the whole trip doesn't cover it; nil without one.
    case notCovered(ticket: TicketCatalogue.Ticket, reason: SeasonPass.Mismatch? = nil)
    /// No catalogue yet, or a journey zone it does not list.
    case unknown
    /// Walking only.
    case noTransit

    init(journey: Journey, pass: SeasonPass?, catalogue: TicketCatalogue?, now: Date = Date()) {
        let transit = (journey.parts ?? []).filter { $0.routeType != 64 }
        guard let first = transit.first, let last = transit.last else {
            self = .noTransit
            return
        }
        guard let catalogue, let zones = catalogue.zoneNames(of: journey) else {
            self = .unknown
            return
        }
        // A ticket runs from boarding the first vehicle to leaving the last, like the R-API's ticket_id.
        let start = first.startDeparture
        let end = last.endArrival
        let minutes = Int((end.timeIntervalSince(start) / 60).rounded(.up))
        var reason: SeasonPass.Mismatch?
        if let pass, pass.start <= start, end <= pass.end {
            reason = pass.mismatch(in: zones, on: transit)
            if reason == nil {
                self = .covered(lastDay: pass.lastDay)
                return
            }
            // A single ticket for the other zones, timed for the whole trip. Not with bank-card passes (B.5.2),
            // and only on city lines and trains: not on regional buses (A.12.9) or lines we can't name.
            // Its zones count from where it is first used (B.3.3), so the stops outside the pass must be in
            // exactly the other zones, in one run at the start or the end of the trip.
            let uncovered = zones.subtracting(pass.zones)
            if !pass.bankCard, uncovered.count < zones.count,
               transit.allSatisfy({ isCityLine($0.routeShortName ?? "") || isTrain($0.routeShortName ?? "") }),
               let sequence = Self.zoneSequence(of: transit), Set(sequence).subtracting(pass.zones) == uncovered,
               [sequence, sequence.reversed()].contains(where: {
                   !$0.drop(while: uncovered.contains).contains(where: uncovered.contains)
               }),
               let ticket = catalogue.singleTicket(zoneCount: uncovered.count, minutes: minutes) {
                self = .partlyCovered(passZones: zones.intersection(pass.zones).sorted(), zones: uncovered.sorted(),
                                      ticket: ticket)
                return
            }
        }
        let rApiTicket = journey.ticketId.flatMap { id in catalogue.tickets?.first { $0.ticketId == id } }
        guard let ticket = rApiTicket ?? catalogue.singleTicket(zoneCount: zones.count, minutes: minutes) else {
            self = .unknown
            return
        }
        if let pass, pass.start <= start, pass.end < end {
            self = .expired(lastDay: pass.lastDay, ended: pass.end <= now, ticket: ticket)
        } else {
            self = .notCovered(ticket: ticket, reason: reason)
        }
    }

    /// The fare zones of `transit`'s stops in travel order, a zone repeated in a row once; nil while a leg's
    /// stops or a stop's zone are unknown.
    private static func zoneSequence(of transit: [Part]) -> [String]? {
        var sequence = [String]()
        for part in transit {
            guard let stops = part.stops, !stops.isEmpty else { return nil }
            for stop in stops {
                guard let zone = stop.zone else { return nil }
                if zone != sequence.last {
                    sequence.append(zone)
                }
            }
        }
        return sequence
    }
}
