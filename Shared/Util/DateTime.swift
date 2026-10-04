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

/// Whole minutes between the clock minutes `timeStringFromDate` shows (it drops the seconds), so a
/// duration always matches the times beside it: 16:30:15 → 16:40:45 is 10 min.
func minutesBetween(_ from: Date, _ to: Date) -> Int {
    let minute = { (date: Date) in (date.timeIntervalSinceReferenceDate / 60).rounded(.down) }
    return Int(minute(to) - minute(from))
}

func timeDiffFromDates(_ from: Date, _ to: Date) -> String {
    "\(minutesBetween(from, to))"
}

func clockStringFromDate(_ time: Date) -> String {
    return clockFormatter.string(from: time)
}

func actualDateString() -> String {
    return dateDayFormatter.string(from: Date.now)
}
