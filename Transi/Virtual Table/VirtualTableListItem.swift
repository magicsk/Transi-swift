//
//  VirtualTableListItem.swift
//  Transi
//
//  Created by magic_sk on 09/04/2023.
//

import ActivityKit
import MarqueeText
import SwiftUI

struct VirtualTableListItem: View {
    var connection: Connection
    var platformLabels: [PlatformLabel]?
    var vehicleInfo: VehicleInfo?
    var isLast: Bool
    @State var date = Date()
    @State var expanded: Bool = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ connection: Connection, _ platformLabels: [PlatformLabel]?, _ vehicleInfo: VehicleInfo?, isLast: Bool)
    {
        self.connection = connection
        self.platformLabels = platformLabels
        self.vehicleInfo = vehicleInfo
        self.isLast = isLast
    }

    var body: some View {
        VStack(spacing: 12.0) {
            HStack {
                VStack {
                    LineText(connection.line, 20.0)
                }
                .width(50.0)
                VStack {
                    HStack {
                        VStack(alignment: .leading, spacing: .zero) {
                            // Wraps where a scrolling marquee would be hard to read or move too much.
                            if reduceMotion || dynamicTypeSize.isAccessibilitySize {
                                Text(connection.headsign)
                                    .font(Font(headsignFont))
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                MarqueeText(
                                    text: connection.headsign,
                                    font: headsignFont,
                                    leftFade: 0,
                                    rightFade: 0,
                                    startDelay: 1
                                )
                            }
                            if connection.lastStopName != "none" && !expanded {
                                HStack(spacing: 4.0) {
                                    StopIcon()
                                    Text(connection.lastStopName)
                                        .font(.caption)
                                        .foregroundColor(.secondaryLabel)
                                }
                                .padding(.leading, 1.5)
                            }
                        }
                        Spacer()
                        VStack {
                            Spacer()
                        }
                        HStack(spacing: 6.0) {
                            if connection.stuck {
                                Image("exclamationmark.triangle.fill").foregroundColor(
                                    .yellow)
                            }
                            RemainingTime(connection.departureTimeRemaining)
                            Text(getPlatformLabel(platformLabels, connection.platform))
                                .font(.callout.weight(.light))
                                .frame(minWidth: 22.0)
                        }
                    }
                }
            }
            .foregroundColor(.label)
            // One element, not loose fragments such as a lone platform letter.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
            .accessibilityHint(expanded ? "Hides vehicle details" : "Shows vehicle details")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                withAnimation {
                    expanded.toggle()
                }
            }
            // Details live in this row, not a row of their own, so a live reorder moves them together.
            if expanded {
                VirtualTableConnectionDetail(connection, vehicleInfo, true)
            }
        }
        // Keeps the header in place while the row's height animates instead of centering it.
        .frame(maxHeight: .infinity, alignment: .top)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                expanded.toggle()
            }
        }
        .onAppear {
            expanded = expanded ? true : connection.expanded
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            // Requesting an activity throws while Live Activities are off for the app.
            if ActivityAuthorizationInfo().areActivitiesEnabled {
                Button {
                    _ = try? VirtualTableLiveActivityController.startActivity(connection, vehicleInfo)
                } label: {
                    Label("Notify", systemImage: "bell.fill")
                }
                .tint(.blue)
                .labelStyle(.iconOnly)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                let url = URL(string: "transi://table/\(connection.stopId)/\(connection.id)")
                let av = UIActivityViewController(activityItems: [url!], applicationActivities: nil)
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   var top = windowScene.windows.first?.rootViewController
                {
                    // From the map's stop sheet the root is already presenting, and an iPad needs an anchor.
                    while let presented = top.presentedViewController { top = presented }
                    av.popoverPresentationController?.sourceView = top.view
                    av.popoverPresentationController?.sourceRect = CGRect(
                        x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0
                    )
                    top.present(av, animated: true, completion: nil)
                }
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .tint(.yellow)
            .labelStyle(.iconOnly)
            // Only with a last-seen stop to show; without one the button did nothing.
            if connection.lastStopName != "none" {
                Button {
                    if let stopId = GlobalController.stopsListProvider.getStopIdFromName(
                        connection.lastStopName)
                    {
                        GlobalController.appState.pendingNavigation = .map(stopId: stopId)
                    }
                } label: {
                    Label("Last stop on map", systemImage: "map.fill")
                }
                .tint(.red)
                .labelStyle(.iconOnly)
            }
            // "►" isn't a line with a timetable to open.
            if connection.line != "►" {
                Button {
                    GlobalController.appState.pendingNavigation = .timetable(line: connection.line)
                } label: {
                    Label("Timetable", systemImage: "calendar")
                }
                .tint(.green)
                .labelStyle(.iconOnly)
            }
        }
        .alignmentGuide(.listRowSeparatorLeading) { _ in
            55
        }
        .onChange(of: expanded) { expanded in
            if expanded == true {
                GlobalController.virtualTable.lastExpandedConnection = connection
            }
        }
    }

    /// Grows with the text size, like the remaining time beside it.
    private var headsignFont: UIFont {
        UIFontMetrics(forTextStyle: .callout).scaledFont(
            for: .systemFont(ofSize: 16.0, weight: .medium),
            compatibleWith: UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
        )
    }

    private var accessibilityText: String {
        let remaining = connection.departureTimeRemaining
        // "~" marks a time from the timetable, without a live vehicle.
        let scheduled = remaining.hasPrefix("~")
        let time = scheduled ? String(remaining.dropFirst()) : remaining
        var spokenTime: String
        switch time {
        case "now": spokenTime = "departing now"
        case "<1 min": spokenTime = "in less than a minute"
        default: spokenTime = time.contains(":") ? "at \(time)" : "in \(time)"
        }
        if scheduled {
            spokenTime += " by timetable"
        }
        // "Kramáre ► Červený most" runs via Kramáre; VoiceOver would read the arrow's name.
        let headsign = connection.headsign.replacingOccurrences(of: " ► ", with: ", then ")
        // "►" stands in for a line number on some departures.
        var text = connection.line == "►" ? "To \(headsign), \(spokenTime)" : "Line \(connection.line) to \(headsign), \(spokenTime)"
        let platform = getPlatformLabel(platformLabels, connection.platform)
        if !platform.isEmpty {
            text += ", platform \(platform)"
        }
        if connection.lastStopName != "none" {
            text += ", last seen at \(connection.lastStopName)"
        }
        if connection.stuck {
            text += ", vehicle is not moving"
        }
        return text
    }
}

@available(iOS 17.0, *)
#Preview {
    NavigationStack {
        List([Connection.example2, Connection.example, Connection.example3], id: \.self) {
            connection in
            VirtualTableListItem(
                connection, [PlatformLabel.example], VehicleInfo.example, isLast: false)
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text("Preview"))
    }
}
