//
//  DateTime.swift
//  Transi
//
//  Created by magic_sk on 14/05/2023.
//

import Foundation

private let clockFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter
}()

private let dateDayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyyMMdd"
    return formatter
}()

private let isoDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.formatOptions = [
        .withFullDate,
        .withFullTime,
        .withDashSeparatorInDate,
        .withFractionalSeconds,
    ]
    return formatter
}()

func dateFromUtc(_ isoString: String?) -> Date {
    guard let isoString = isoString else { return Date() }
    return isoDateFormatter.date(from: isoString) ?? Date()
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
    return clockFormatter.string(from: time)
}

func actualDateString() -> String {
    return dateDayFormatter.string(from: Date.now)
}
