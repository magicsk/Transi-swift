//
//  TripQuestionIntent.swift
//  Transi
//
//  Created by magic_sk on 10/11/2026.
//

import AppIntents
import Foundation

/// The traveller's answer from the trip Live Activity to whether they are on the ride it asks about. The system performs
/// it in the app, which it launches in the background when needed; the widget extension only shows its buttons.
@available(iOS 17.0, *)
struct TripQuestionIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Answer the Trip Question"
    static var description = IntentDescription("Tells the followed trip whether you are on the ride it asks about.")
    static var isDiscoverable = false

    @Parameter(title: "Still on the ride")
    var stillOn: Bool

    init() {}

    init(stillOn: Bool) {
        self.stillOn = stillOn
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        await TripQuestion.answer?(stillOn)
        return .result()
    }
}

/// Where the app takes the answers in. Set at launch, after the followed trip is restored; nil in the widget extension.
enum TripQuestion {
    static var answer: ((_ stillOn: Bool) async -> Void)?
}
