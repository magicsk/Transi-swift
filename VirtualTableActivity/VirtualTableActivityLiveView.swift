//
//  VirtualTableActivityLiveView.swift
//  VirtualTableActivityExtension
//
//  Created by magic_sk on 13/06/2024.
//

import ActivityKit
import SwiftUI
import WidgetKit

struct VirtualTableActivityLiveView: View {
    @Environment(\.colorScheme) var colorScheme

    var context: ActivityViewContext<VirtualTableActivityAttributes>

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                VirtualTableActivityLiveViewWithActivityFamily(context: context)
            } else {
                VirtualTableActivityLiveViewLarge(context: context)
                    .activityBackgroundTint(backgroundTint)
            }
        }
        .widgetURL(URL(string: "transi://table/\(context.state.connection.stopId)/\(context.state.connection.id)"))
    }

    private var backgroundTint: Color {
        colorScheme == .dark ? Color.black.opacity(0.43) : Color.systemBackground.opacity(0.43)
    }
}

@available(iOS 18.0, *)
private struct VirtualTableActivityLiveViewWithActivityFamily: View {
    @Environment(\.activityFamily) var activityFamily
    @Environment(\.colorScheme) var colorScheme

    var context: ActivityViewContext<VirtualTableActivityAttributes>

    var body: some View {
        VirtualTableActivityLiveDynamicView(context: context)
            .background {
                GeometryReader { proxy in
                    if usesCompactBackdrop(size: proxy.size) {
                        Color.black.opacity(0.85)
                    }
                }
            }
            .overlay {
                GeometryReader { proxy in
                    if usesEnlargedWatchBorder(size: proxy.size) {
                        RoundedRectangle(cornerRadius: 18.0, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.28), lineWidth: 1.0)
                            .padding(1.0)
                    }
                }
            }
            .activityBackgroundTint(backgroundTint)
    }

    private var backgroundTint: Color {
        if #available(iOS 26.0, *) {
            return Color.clear
        }
        return colorScheme == .dark ? Color.black.opacity(0.43) : Color.systemBackground.opacity(0.43)
    }

    private func usesCompactBackdrop(size: CGSize) -> Bool {
        activityFamily == .small || size.width < 260.0
    }

    private func usesEnlargedWatchBorder(size: CGSize) -> Bool {
        activityFamily == .medium && size.width < 260.0
    }
}
