import CSQLite
import Foundation

/// Минимальная обёртка над встроенной SQLite: база в памяти или в файле, запросы с параметрами.
public enum SQLiteError: Error, CustomStringConvertible {
    case sqlite(code: Int32, message: String)
    public var description: String {
        switch self {
        case .sqlite(let code, let message): return "SQLite \(code): \(message)"
        }
    }
}

public enum SQLValue: Equatable, Sendable {
    case null
    case int(Int64)
    case real(Double)
    case text(String)
    case blob([UInt8])

    public var int: Int64? { if case .int(let v) = self { return v } else { return nil } }
    public var text: String? { if case .text(let v) = self { return v } else { return nil } }
    public var blob: [UInt8]? {
        switch self {
        case .blob(let v): return v
        case .text(let v): return Array(v.utf8)
        default: return nil
        }
    }
}

private let SQLITE_TRANSIENT_DESTRUCTOR = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class SQLiteDatabase {
    private var handle: OpaquePointer?

    /// `path` = ":memory:" — база в памяти.
    public init(path: String, readOnly: Bool = false) throws {
        let flags = readOnly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        let rc = sqlite3_open_v2(path, &handle, flags | SQLITE_OPEN_NOMUTEX, nil)
        guard rc == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "не открыта"
            sqlite3_close(handle)
            throw SQLiteError.sqlite(code: rc, message: message)
        }
    }

    deinit { sqlite3_close(handle) }

    private func fail(_ rc: Int32) -> SQLiteError {
        SQLiteError.sqlite(code: rc, message: String(cString: sqlite3_errmsg(handle)))
    }

    public func execute(_ sql: String) throws {
        let rc = sqlite3_exec(handle, sql, nil, nil, nil)
        guard rc == SQLITE_OK else { throw fail(rc) }
    }

    /// Выполнить запрос с параметрами; вернуть все строки.
    @discardableResult
    public func query(_ sql: String, _ params: [SQLValue] = []) throws -> [[SQLValue]] {
        var stmt: OpaquePointer?
        var rc = sqlite3_prepare_v2(handle, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK else { throw fail(rc) }
        defer { sqlite3_finalize(stmt) }
        for (i, p) in params.enumerated() {
            let idx = Int32(i + 1)
            switch p {
            case .null: rc = sqlite3_bind_null(stmt, idx)
            case .int(let v): rc = sqlite3_bind_int64(stmt, idx, v)
            case .real(let v): rc = sqlite3_bind_double(stmt, idx, v)
            case .text(let v): rc = sqlite3_bind_text(stmt, idx, v, -1, SQLITE_TRANSIENT_DESTRUCTOR)
            case .blob(let v):
                rc = v.withUnsafeBytes { sqlite3_bind_blob(stmt, idx, $0.baseAddress, Int32(v.count), SQLITE_TRANSIENT_DESTRUCTOR) }
            }
            guard rc == SQLITE_OK else { throw fail(rc) }
        }
        var rows: [[SQLValue]] = []
        while true {
            rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else { throw fail(rc) }
            var row: [SQLValue] = []
            for c in 0..<sqlite3_column_count(stmt) {
                switch sqlite3_column_type(stmt, c) {
                case SQLITE_INTEGER: row.append(.int(sqlite3_column_int64(stmt, c)))
                case SQLITE_FLOAT: row.append(.real(sqlite3_column_double(stmt, c)))
                case SQLITE_TEXT: row.append(.text(String(cString: sqlite3_column_text(stmt, c))))
                case SQLITE_BLOB:
                    let n = Int(sqlite3_column_bytes(stmt, c))
                    if n == 0 {
                        row.append(.blob([]))
                    } else {
                        let ptr = sqlite3_column_blob(stmt, c)!.assumingMemoryBound(to: UInt8.self)
                        row.append(.blob(Array(UnsafeBufferPointer(start: ptr, count: n))))
                    }
                default: row.append(.null)
                }
            }
            rows.append(row)
        }
        return rows
    }

    /// Содержимое базы как файл (через временный файл: переносимо и без расширений SQLite).
    public static func serialize(_ build: (SQLiteDatabase) throws -> Void) throws -> [UInt8] {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pe-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        do {
            let db = try SQLiteDatabase(path: url.path)
            try db.execute("PRAGMA journal_mode=OFF")
            try build(db)
        }
        guard let data = FileManager.default.contents(atPath: url.path) else { throw SQLiteError.sqlite(code: -1, message: "не прочитан временный файл базы") }
        return [UInt8](data)
    }

    /// Открыть базу из байтов (копия во временный файл, только чтение).
    public static func open(bytes: [UInt8], _ use: (SQLiteDatabase) throws -> Void) throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("pe-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        guard FileManager.default.createFile(atPath: url.path, contents: Data(bytes)) else {
            throw SQLiteError.sqlite(code: -1, message: "не записан временный файл базы")
        }
        let db = try SQLiteDatabase(path: url.path, readOnly: true)
        try use(db)
    }
}
