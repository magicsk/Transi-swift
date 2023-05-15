//
//  VehicleInfo.swift
//  Transi
//
//  Created by magic_sk on 10/04/2023.
//

import Foundation

struct VehicleInfo: Codable, Identifiable, Hashable {
    var id: Int
    var issi: String
    var lf: Int
    var ac: Bool
    var img: Int
    var imgt: String
    var type: String
    static let example = VehicleInfo(id: 13142, issi: "1:2552", lf: 1, ac: true, img: 1017, imgt: "vm", type: "SOR NS 12 Diesel")
}

extension VehicleInfo {
    init?(json: [String: Any]) {
        self.id = json["id"] as? Int ?? 0
        self.issi = json["issi"] as? String ?? "error"
        self.lf = json["lf"] as? Int ?? 0
        self.ac = (json["ac"] as? Int ?? 0) == 1
        self.img = json["img"] as? Int ?? 0
        self.imgt = (json["imgt"] as? Int ?? 0) == 0 ? "vm" : "vs"
        self.type = json["type"] as? String ?? "error"
    }
}
