import Foundation
import SQLite3

// A read-only connection to GameTrack's Core Data store. The server never writes to it:
// the store mirrors to CloudKit, and a foreign write would corrupt its change history.
final class Database {
  private var handle: OpaquePointer?

  // GameTrack keeps the store in WAL mode. A read-only connection reads the WAL through
  // the -shm file the app leaves beside it. When the app last quit cleanly there is no WAL
  // and SQLite may refuse a read-only open for want of one; only then is the file opened
  // as immutable, which skips the WAL and so must never be used while one exists.
  init(path: String) throws {
    do {
      try open(path: path, immutable: false)
    } catch let error as ServerError where error.code == .internalError {
      guard !FileManager.default.fileExists(atPath: path + "-wal") else { throw error }
      close()
      try open(path: path, immutable: true)
    }
  }
  deinit { close() }

  private func close() {
    sqlite3_close_v2(handle)
    handle = nil
  }

  private func open(path: String, immutable: Bool) throws {
    let uri =
      URL(fileURLWithPath: path).absoluteString + (immutable ? "?immutable=1" : "?mode=ro")
    let status = sqlite3_open_v2(uri, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
    guard status == SQLITE_OK else { throw failure("open") }
    sqlite3_busy_timeout(handle, 5000)
    // The open is lazy; the first read is what finds a file that cannot be used.
    _ = try rows("SELECT count(*) FROM sqlite_master")
  }

  private func failure(_ action: String) -> ServerError {
    let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "out of memory"
    let system = handle.map { sqlite3_system_errno($0) } ?? 0
    if system == EPERM || system == EACCES {
      return .notAuthorized(databaseAccessMessage)
    }
    return .internalError("The GameTrack database could not be read (\(action): \(message))")
  }

  // Every row of a query. Statements are fixed strings built from names the schema
  // resolver read out of the database itself; no request input reaches SQL.
  func rows(_ sql: String) throws -> [Row] {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
      throw failure("prepare")
    }
    defer { sqlite3_finalize(statement) }
    let count = sqlite3_column_count(statement)
    let names = (0..<count).map { String(cString: sqlite3_column_name(statement, $0)) }
    var result: [Row] = []
    while true {
      let step = sqlite3_step(statement)
      if step == SQLITE_DONE { break }
      guard step == SQLITE_ROW else { throw failure("step") }
      var values: [String: Value] = [:]
      for index in 0..<count {
        switch sqlite3_column_type(statement, index) {
        case SQLITE_INTEGER:
          values[names[Int(index)]] = .integer(sqlite3_column_int64(statement, index))
        case SQLITE_FLOAT:
          values[names[Int(index)]] = .real(sqlite3_column_double(statement, index))
        case SQLITE_TEXT:
          values[names[Int(index)]] = .text(String(cString: sqlite3_column_text(statement, index)))
        case SQLITE_BLOB:
          let bytes = Int(sqlite3_column_bytes(statement, index))
          values[names[Int(index)]] = .blob(
            sqlite3_column_blob(statement, index).map { Data(bytes: $0, count: bytes) } ?? Data())
        default: break
        }
      }
      result.append(Row(values: values))
    }
    return result
  }

  enum Value {
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)
  }

  // One result row. A column the query did not select, or that holds NULL, reads as nil.
  struct Row {
    fileprivate let values: [String: Value]

    func int(_ column: String) -> Int? {
      switch values[column] {
      case .integer(let value): Int(value)
      case .real(let value): Int(exactly: value)
      default: nil
      }
    }
    func double(_ column: String) -> Double? {
      switch values[column] {
      case .real(let value): value
      case .integer(let value): Double(value)
      default: nil
      }
    }
    func bool(_ column: String) -> Bool? { int(column).map { $0 != 0 } }
    // Core Data stores the empty string and NULL alike for an unset attribute.
    func text(_ column: String) -> String? {
      guard case .text(let value) = values[column], !value.isEmpty else { return nil }
      return value
    }
    func blob(_ column: String) -> Data? {
      guard case .blob(let value) = values[column] else { return nil }
      return value
    }
    // Core Data dates are seconds since 2001-01-01 UTC.
    func date(_ column: String) -> Date? {
      double(column).map(Date.init(timeIntervalSinceReferenceDate:))
    }
    // Core Data stores a UUID attribute as its 16 bytes.
    func uuid(_ column: String) -> String? {
      guard let data = blob(column), data.count == 16 else { return nil }
      return data.withUnsafeBytes {
        NSUUID(uuidBytes: $0.bindMemory(to: UInt8.self).baseAddress).uuidString
      }
    }
    // A transformable [String] attribute, archived with NSKeyedArchiver.
    func strings(_ column: String) -> [String] {
      guard let data = blob(column),
        let array = try? NSKeyedUnarchiver.unarchivedArrayOfObjects(
          ofClass: NSString.self, from: data)
      else { return [] }
      return array.map { $0 as String }
    }
  }
}

let databaseAccessMessage =
  "macOS denied this server access to GameTrack's data; allow it in System Settings > Privacy & Security > Full Disk Access"
