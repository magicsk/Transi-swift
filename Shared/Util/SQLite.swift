//
//  SQLite.swift
//  Transi
//
//  Created by magic_sk on 26/02/2026.
//

import Foundation
import SQLite3

struct SQLiteDatabaseFingerprint: Hashable {
    let path: String
    let size: UInt64
    let modificationTime: TimeInterval
}

class SQLiteDatabase {
    private var db: OpaquePointer?
    let path: String
    let fingerprint: SQLiteDatabaseFingerprint

    init?(path: String) {
        self.path = URL(fileURLWithPath: path).standardizedFileURL.path
        self.fingerprint = Self.fingerprint(for: self.path)
        // Searches may run at once on one connection; the full mutex serializes them.
        if sqlite3_open_v2(path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX, nil) != SQLITE_OK {
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
        var results = [[String: Any]]()
        forEachRow(sql, params: params) { row in
            var values = [String: Any]()
            for col in 0 ..< row.columnCount {
                let name = String(cString: sqlite3_column_name(row.stmt, col))
                switch sqlite3_column_type(row.stmt, col) {
                case SQLITE_INTEGER:
                    values[name] = row.int(col)
                case SQLITE_FLOAT:
                    values[name] = row.double(col)
                case SQLITE_TEXT:
                    values[name] = row.string(col)
                default:
                    values[name] = nil as Any?
                }
            }
            results.append(values)
        }
        return results
    }

    /// Steps through the result rows without building dictionaries; read columns by index with the typed getters.
    func forEachRow(_ sql: String, params: [Any] = [], _ body: (SQLiteRow) -> Void) {
        var stmt: OpaquePointer?
        let status = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        if status != SQLITE_OK {
            let errmsg = String(cString: sqlite3_errmsg(db))
            print("SQLite Prepare Error: \(errmsg) for SQL: \(sql)")
            return
        }
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

        guard let stmt else { return }
        let row = SQLiteRow(stmt: stmt, columnCount: sqlite3_column_count(stmt))
        while sqlite3_step(stmt) == SQLITE_ROW {
            body(row)
        }
    }

    private static func fingerprint(for path: String) -> SQLiteDatabaseFingerprint {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let size = (attributes?[.size] as? NSNumber)?.uint64Value ?? 0
        let modificationTime = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return SQLiteDatabaseFingerprint(path: path, size: size, modificationTime: modificationTime)
    }
}

/// The current row of `SQLiteDatabase.forEachRow`; only valid inside the callback.
struct SQLiteRow {
    fileprivate let stmt: OpaquePointer
    let columnCount: Int32

    func int(_ column: Int32) -> Int {
        Int(sqlite3_column_int64(stmt, column))
    }

    func double(_ column: Int32) -> Double {
        sqlite3_column_double(stmt, column)
    }

    /// Nil for NULL.
    func string(_ column: Int32) -> String? {
        sqlite3_column_text(stmt, column).map { String(cString: $0) }
    }
}
