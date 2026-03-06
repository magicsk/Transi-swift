//
//  SQLite.swift
//  Transi
//
//  Created by magic_sk on 26/02/2026.
//

import Foundation
import SQLite3

class SQLiteDatabase {
    private var db: OpaquePointer?

    init?(path: String) {
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE, nil) != SQLITE_OK {
            sqlite3_close(db)
            return nil
        }
        // Convert from WAL to DELETE journal mode to avoid WAL/SHM file issues
        sqlite3_exec(db, "PRAGMA journal_mode=DELETE", nil, nil, nil)
    }

    deinit {
        sqlite3_close(db)
    }

    func execute(_ sql: String) {
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    func query(_ sql: String, params: [Any] = []) -> [[String: Any]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }

        for (i, param) in params.enumerated() {
            let idx = Int32(i + 1)
            switch param {
            case let v as Int:
                sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as Int64:
                sqlite3_bind_int64(stmt, idx, v)
            case let v as String:
                sqlite3_bind_text(stmt, idx, (v as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case let v as Double:
                sqlite3_bind_double(stmt, idx, v)
            default:
                sqlite3_bind_null(stmt, idx)
            }
        }

        var results = [[String: Any]]()
        let colCount = sqlite3_column_count(stmt)
        while sqlite3_step(stmt) == SQLITE_ROW {
            var row = [String: Any]()
            for col in 0 ..< colCount {
                let name = String(cString: sqlite3_column_name(stmt, col))
                switch sqlite3_column_type(stmt, col) {
                case SQLITE_INTEGER:
                    row[name] = Int(sqlite3_column_int64(stmt, col))
                case SQLITE_FLOAT:
                    row[name] = sqlite3_column_double(stmt, col)
                case SQLITE_TEXT:
                    row[name] = String(cString: sqlite3_column_text(stmt, col))
                default:
                    row[name] = nil as Any?
                }
            }
            results.append(row)
        }
        return results
    }
}
