//
//  AnyCodable.swift
//  Transi
//
//  Created by magic_sk on 11/01/2026.
//

struct AnyCodable: Codable {
    let value: Any?

    init(_ value: Any?) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            value = nil
            return
        }

        if let x = try? container.decode(Int.self) {
            value = x
        } else if let x = try? container.decode(String.self) {
            value = x
        } else if let x = try? container.decode(Bool.self) {
            value = x
        } else if let x = try? container.decode(Double.self) {
            value = x
        } else if let x = try? container.decode([AnyCodable].self) {
            value = x.map { $0.value }
        } else if let x = try? container.decode([String: AnyCodable].self) {
            value = x.mapValues { $0.value }
        } else {
            throw DecodingError.typeMismatch(
                AnyCodable.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath, debugDescription: "Type not supported"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        guard let value = value else {
            try container.encodeNil()
            return
        }

        if let x = value as? Int {
            try container.encode(x)
        } else if let x = value as? String {
            try container.encode(x)
        } else if let x = value as? Bool {
            try container.encode(x)
        } else if let x = value as? Double {
            try container.encode(x)
        } else if let x = value as? [Any?] {
            try container.encode(x.map { AnyCodable($0) })
        } else if let x = value as? [String: Any?] {
            try container.encode(x.mapValues { AnyCodable($0) })
        } else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: encoder.codingPath, debugDescription: "Type not supported"))
        }
    }
}
