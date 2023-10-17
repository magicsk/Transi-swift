//
//  DateTime.swift
//  Transi
//
//  Created by magic_sk on 14/05/2023.
//

import Foundation

func dateFromUtc(_ isoString: String?) -> Date? {
    if isoString == nil {
        return nil
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
            return nil
        }
    }
}

func timeStringFromUtc(_ isoString: String?) -> String {
    if isoString == nil {
        return "Error"
    } else {
        if let date = dateFromUtc(isoString) {
            return date.formatted(date: .omitted, time: .shortened)
        } else {
            return "Error"
        }
    }
}

func timeDiffFromUtc(_ from: String?, _ to: String?) -> String {
    if from != nil && to != nil {
        if let fromDate = dateFromUtc(from!) {
            if let toDate = dateFromUtc(to!) {
                let diff = toDate - fromDate
                return "\(Int(diff / 60))"
            }
        }
    }
    return "Error"
}

func clockStringFromDate(_ time: Date) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"
    return formatter.string(from: time)
}
