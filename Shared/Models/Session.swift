//
//  Session.swift
//  Transi
//
//  Created by magic_sk on 17/12/2023.
//

import Foundation

struct Session: Codable, Hashable {
    var session: String
}

struct SessionReq: Codable, Hashable {
    private static let persistedInstallation: String = {
        let key = "installationUUID"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let newUUID = UUID().uuidString
        UserDefaults.standard.set(newUUID, forKey: key)
        return newUUID
    }()
    var installation: String = SessionReq.persistedInstallation
    var language = "en"
    var platform = 2
}

