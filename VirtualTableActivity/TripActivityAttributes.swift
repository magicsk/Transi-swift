//
//  TripActivityAttributes.swift
//  Transi
//
//  Created by magic_sk on 04/10/2026.
//

import ActivityKit
import Foundation

/// The trip Live Activity. The app follows the journey and sends ready-to-show values for the current step;
/// the journey itself stays in the app, which keeps the payload far below the ActivityKit limit.
struct TripActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        enum Step: String, Codable {
            case board, ride, change, walk, arrived
        }

        enum Warning: String, Codable {
            case tightChange, likelyMissedChange
        }

        var step: Step
        /// The line to board, ride or change to; nil for walks and the arrival.
        var line: String?
        /// "Board at Hronská", "Get off in 3 stops", "Walk to platform D", "Arrived".
        var title: String
        /// "Platform A · in 4 min", "Hlavná stanica, platform X", "31 leaves in 6 min".
        var detail: String
        /// When that vehicle leaves or arrives, delay included; the arrival for walks.
        var time: Date
        /// Minutes late, negative when early; nil without delay data.
        var delay: Int?
        /// How far the ride has got, 0...1; nil outside rides.
        var progress: Double?
        /// Dynamic Island text: "4 min", "3 stops", "D · 6m".
        var compact: String
        /// Minimal Dynamic Island text: "4m", "3", "D".
        var minimal: String
        /// The next change's spare time is short or gone.
        var warning: Warning?
        /// Alerts already shown, so each one fires once per step, also after the app relaunches.
        var alerted: Set<String> = []
    }
}
