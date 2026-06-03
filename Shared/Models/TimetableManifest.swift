//
//  TimetableManifest.swift
//  Transi
//
//  Created by magic_sk on 26/02/2026.
//

import Foundation

struct TimetableManifest: Codable {
    var schemaVersion: Int
    var generatedAt: String
    var databases: TimetableDatabases
}

struct TimetableDatabases: Codable {
    var base: TimetableDatabaseInfo
    var schedule: TimetableDatabaseInfo
}

struct TimetableDatabaseInfo: Codable {
    var version: String
    var url: String
    var sizeBytes: Int
    var sizeBytesGz: Int
    var sha256: String
    var validFrom: String
    var validUntil: String
}
