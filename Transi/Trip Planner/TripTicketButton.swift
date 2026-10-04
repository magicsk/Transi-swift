//
//  TripTicketButton.swift
//  Transi
//
//  Created by magic_sk on 04/10/2026.
//

import SwiftUI

/// Whether "My pass" covers the journey, else the single ticket it needs, with a button to IDS BK.
struct TripTicketButton: View {
    /// Observed, not a `Journey` value: `Journey`'s `==` ignores stops, so the coverage would stay stale when
    /// the stops load.
    @ObservedObject var model: TripDetailModel

    @StateObject private var ticketCatalogue = GlobalController.ticketCatalogue
    @AppStorage(Stored.passDays) private var passDays = 0
    @AppStorage(Stored.passValidFrom) private var passValidFrom = 0.0
    @AppStorage(Stored.passZones) private var passZones = "100,101"
    @AppStorage(Stored.passNetworkWide) private var passNetworkWide = false
    @AppStorage(Stored.passBankCard) private var passBankCard = false

    private var coverage: TicketCoverage {
        let pass = SeasonPass(days: passDays, validFrom: passValidFrom, zones: passZones,
                              networkWide: passNetworkWide, bankCard: passBankCard)
        return TicketCoverage(journey: model.journey, pass: pass, catalogue: ticketCatalogue.catalogue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch coverage {
            case .covered(let lastDay):
                status("Covered by your pass", systemImage: "checkmark.seal.fill", color: .green,
                       detail: Text("until \(SeasonPass.dayFormatter.string(from: lastDay))"))
                openButton {
                    Text("Open IDS BK")
                }
            case .expired(let lastDay, let ended, let ticket):
                let day = SeasonPass.dayFormatter.string(from: lastDay)
                if ended {
                    status("Your pass expired on \(day)", systemImage: "exclamationmark.triangle.fill", color: .orange)
                } else {
                    status("Your pass ends on \(day), before this trip", systemImage: "exclamationmark.triangle.fill",
                           color: .orange)
                }
                buyButton(ticket)
            case .partlyCovered(let passZones, let zones, let ticket):
                status("Your pass covers \(zoneList(passZones))", systemImage: "checkmark.seal", color: .green)
                buyButton(ticket, for: zones)
            case .notCovered(let ticket, let reason):
                if let reason {
                    status("Your pass doesn't cover this trip", systemImage: "xmark.seal", color: .orange,
                           detail: mismatchText(reason))
                }
                buyButton(ticket)
            case .unknown:
                openButton {
                    Text("Buy ticket in IDS BK")
                }
            case .noTransit:
                EmptyView()
            }
        }
        .onAppear { ticketCatalogue.load() }
    }

    private func status(
        _ title: LocalizedStringKey, systemImage: String, color: Color, detail: Text? = nil
    ) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                if let detail {
                    detail
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .combine)
    }

    /// The ticket for the whole trip, or for `uncovered` zones only.
    private func buyButton(_ ticket: TicketCatalogue.Ticket, for uncovered: [String]? = nil) -> some View {
        let action = uncovered.map { Text("Buy ticket for \(zoneList($0))") } ?? Text("Buy ticket")
        let zones = ticket.zonesCount.map { Text("\($0) zones") } ?? Text("all zones")
        let price = ticket.price.formatted(.currency(code: ticket.currency))
        return VStack(spacing: 4) {
            openButton {
                Text("\(action) · \(ticket.timeDuration) min, \(zones) · \(price)")
            }
            .accessibilityLabel(Text("\(action), \(ticket.timeDuration) minutes, \(zones), \(price), basic fare"))
            Text("Basic fare")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
    }

    private func mismatchText(_ reason: SeasonPass.Mismatch) -> Text {
        switch reason {
        case .bankCard:
            return Text("Bank-card passes are valid only on city lines in zones 100 and 101")
        case .zones(let zones):
            let names = zones.joined(separator: ", ")
            return zones.count == 1 ? Text("Zone \(names) isn't on your pass") : Text("Zones \(names) aren't on your pass")
        }
    }

    /// "zone 111" or "zones 100, 101".
    private func zoneList(_ zones: [String]) -> Text {
        let names = zones.joined(separator: ", ")
        return zones.count == 1 ? Text("zone \(names)") : Text("zones \(names)")
    }

    /// Secondary, so the trip's own primary action stays the only prominent one.
    private func openButton(@ViewBuilder label: () -> some View) -> some View {
        Button {
            open(IdsBkLinks.openOrder.compactMap(URL.init(string:))[...])
        } label: {
            label()
                .font(.body.weight(.semibold))
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        // A fixed radius, not the capsule: a capsule around a multi-line label at large text sizes clips it.
        .buttonBorderShape(.roundedRectangle(radius: 24))
        .ticketButtonStyle()
        .accessibilityHint("Opens the IDS BK app, or its App Store page if the app isn't installed.")
    }

    /// Opens the first URL that works: the app when installed, else its App Store page.
    private func open(_ urls: ArraySlice<URL>) {
        guard let url = urls.first else { return }
        UIApplication.shared.open(url) { opened in
            if !opened { open(urls.dropFirst()) }
        }
    }
}

private extension View {
    @ViewBuilder
    func ticketButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            buttonStyle(.glass)
        } else {
            buttonStyle(.bordered)
        }
    }
}
