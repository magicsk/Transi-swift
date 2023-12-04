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
