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
    var installation = UUID().uuidString
    var language = "en"
    var platform = 2
}

