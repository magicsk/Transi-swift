//
//  DateTime.swift
//  Transi
//
//  Created by magic_sk on 14/05/2023.
//

import Foundation

func dateFromUtc(_ isoString: String?) -> Date {
    if isoString == nil {
        return Date()
    } else {
        let isoDateFormatter = ISO8601DateFormatter()
        isoDateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        isoDateFormatter.formatOptions = [
            .withFullDate,
            .withFullTime,
            .withDashSeparatorInDate,
            .withFractionalSeconds,
        ]

        if let date = isoDateFormatter.date(from: isoString!) {
            return date
        } else {
            return Date()
        }
    }
}

func timeStringFromDate(_ date: Date) -> String {
    return date.formatted(date: .omitted, time: .shortened)
}

func dateStringFromDate(_ date: Date) -> String {
    return date.formatted(date: .numeric, time: .omitted)
}

func timeDiffFromDates(_ from: Date, _ to: Date) -> String {
    let diff = to - from
    return "\(Int(diff / 60))"
}

func clockStringFromDate(_ time: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: time)
}

func actualDateString() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd"
    return formatter.string(from: Date.now)
}
