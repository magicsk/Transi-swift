//
//  Errors.swift
//  Transi
//
//  Created by magic_sk on 04/12/2023.
//

import Foundation

enum TripError: LocalizedError {
    case basic
    case noJourneys
    
    var errorDescription: String? {
        switch self {
        case .basic:
            return "Something went wrong"
        case .noJourneys:
            return "No routes found"
        }
    }
    
    var errorMessage: String? {
        switch self {
        case .basic:
            return "Please try again later."
        case .noJourneys:
            return "In next 2 hours there are not routes available, try different time or other type of transport."
        }
    }
}

enum StopsListError: LocalizedError {
    case basic
    
    var errorDescription: String? {
        switch self {
        case .basic:
            return "Failed to fetch stops list"
        }
    }
    
    var failureReason: String? {
        switch self {
        case .basic:
            return "Check your internet connection or try again later."
        }
    }
}

enum TimetableError: LocalizedError {
    case singular
    case plural
    case directions
    
    var errorDescription: String? {
        switch self {
        case .singular:
            return "Failed to fetch timetable"
                
        case .plural:
            return "Failed to fetch timetables"
            
        case .directions:
            return "Failed to fetch timetable directions"
        }
    }
    
    var failureReason: String? {
        switch self {
        case .singular, .plural, .directions:
            return "Check your internet connection or try again later."
        }
    }
}

enum DefaultError: LocalizedError {
    case basic
    
    var errorDescription: String? {
        switch self {
        case .basic:
            return "Failed to fetch"
        }
    }
    
    var failureReason: String? {
        switch self {
        case .basic:
            return "Check your internet connection or try again later."
        }
    }
}
