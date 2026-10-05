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

/// "Tomorrow" and "Yesterday".
private let relativeDayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    formatter.doesRelativeDateFormatting = true
    return formatter
}()

/// Other days, like "Wed 7 Oct".
private let shortDayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.setLocalizedDateFormatFromTemplate("EEEdMMM")
    return formatter
}()

/// The day of `date`, "Tomorrow", "Yesterday" or like "Wed 7 Oct"; nil when it is today. In the device's calendar and
/// time zone, as `timeStringFromDate` shows the time beside it.
func dayStringUnlessToday(_ date: Date) -> String? {
    let calendar = Calendar.current
    if calendar.isDateInToday(date) {
        return nil
    }
    let isNextToToday = calendar.isDateInTomorrow(date) || calendar.isDateInYesterday(date)
    return (isNextToToday ? relativeDayFormatter : shortDayFormatter).string(from: date)
}

extension Date {
    /// This scheduled time on a vehicle `delaySeconds` late (early when negative), as the trip Live Activity and the
    /// trip detail show it: moved by the whole minutes the delay reads as (`delayMinutes`), like the change buffers.
    func expected(delaySeconds: Int?) -> Date {
        self + TimeInterval(delayMinutes(delaySeconds ?? 0) * 60)
    }
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
