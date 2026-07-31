import Foundation
import SQLite3
import os

/// Thin SQLite3 wrapper. Callers own threading (stores use `@MainActor`).
final class SQLiteDatabase {
    private static let logger = Logger(subsystem: "com.atlasbound.app", category: "sqlite")

    private var handle: OpaquePointer?

    var isOpen: Bool { handle != nil }

    init(fileURL: URL) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        var db: OpaquePointer?
        let status = sqlite3_open_v2(fileURL.path, &db, flags, nil)
        guard status == SQLITE_OK, let db else {
            throw SQLiteError.openFailed(fileURL.path, status)
        }
        handle = db
        try execute("PRAGMA foreign_keys = ON;")
        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA synchronous = NORMAL;")
    }

    deinit {
        if let handle {
            sqlite3_close(handle)
        }
    }

    func execute(_ sql: String) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        let status = sqlite3_exec(handle, sql, nil, nil, &errorMessage)
        if status != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? sqliteMessage
            sqlite3_free(errorMessage)
            throw SQLiteError.executeFailed(sql, message)
        }
    }

    func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        let status = sqlite3_prepare_v2(handle, sql, -1, &statement, nil)
        guard status == SQLITE_OK, let statement else {
            throw SQLiteError.prepareFailed(sql, sqliteMessage)
        }
        return statement
    }

    @discardableResult
    func transaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE;")
        do {
            let value = try body()
            try execute("COMMIT;")
            return value
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    var sqliteMessage: String {
        guard let handle else { return "database closed" }
        return String(cString: sqlite3_errmsg(handle))
    }

    static func bindText(_ statement: OpaquePointer, index: Int32, value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    static func bindDouble(_ statement: OpaquePointer, index: Int32, value: Double?) {
        if let value {
            sqlite3_bind_double(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    static func bindInt(_ statement: OpaquePointer, index: Int32, value: Int) {
        sqlite3_bind_int64(statement, index, Int64(value))
    }

    static func columnText(_ statement: OpaquePointer, index: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: pointer)
    }

    static func columnInt(_ statement: OpaquePointer, index: Int32) -> Int {
        Int(sqlite3_column_int64(statement, index))
    }

    static func columnDouble(_ statement: OpaquePointer, index: Int32) -> Double? {
        if sqlite3_column_type(statement, index) == SQLITE_NULL { return nil }
        return sqlite3_column_double(statement, index)
    }
}

enum SQLiteError: Error, LocalizedError {
    case openFailed(String, Int32)
    case executeFailed(String, String)
    case prepareFailed(String, String)
    case stepFailed(String)

    var errorDescription: String? {
        switch self {
        case let .openFailed(path, code):
            return "Failed to open SQLite at \(path) (\(code))"
        case let .executeFailed(sql, message):
            return "SQLite execute failed: \(message) — \(sql)"
        case let .prepareFailed(sql, message):
            return "SQLite prepare failed: \(message) — \(sql)"
        case let .stepFailed(message):
            return "SQLite step failed: \(message)"
        }
    }
}
