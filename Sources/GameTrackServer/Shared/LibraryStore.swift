import Foundation

import struct os.OSAllocatedUnfairLock

// Reads GameTrack's database without the app's help. Only Sendable records leave this
// file.
//
// The database has its own queue instead of the main actor, so a slow disk cannot stall
// the main-actor watchdog. The in-scope tables are small and read in milliseconds, so one
// snapshot of all of them serves requests until the files change or the snapshot grows
// old.
private let snapshotMaxAge: Duration = .seconds(300)
private let libraryQueue = DispatchQueue(label: "gametrack-server.library")

let defaultDatabasePath =
  NSHomeDirectory()
  + "/Library/Containers/com.joekw.gametrack/Data/Library/Application Support/GameTrack/GameData.sqlite"

// A file's size and modification time; GameTrack changes one or both on every write.
private struct FileStamp: Equatable {
  let seconds, nanoseconds: Int
  let size: Int64
  var modified: Date {
    Date(timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(nanoseconds) / 1e9)
  }
}
// The database and its write-ahead log, where recent writes live until a checkpoint.
private struct Signature: Equatable {
  let database: FileStamp
  let wal: FileStamp?
}

// Touched only on libraryQueue.
private final class LibraryState: @unchecked Sendable {
  var snapshot: (data: LibraryData, signature: Signature, loaded: ContinuousClock.Instant)?
}
private let state = LibraryState()
private let databasePath = OSAllocatedUnfairLock(initialState: defaultDatabasePath)

// Sets the database to read; called once at startup, before any read.
func configureLibrary(path: String) { databasePath.withLock { $0 = path } }

// Everything in scope, from the snapshot when the files have not changed since it.
func currentLibrary() async throws -> LibraryData {
  try await withCheckedThrowingContinuation { continuation in
    libraryQueue.async {
      continuation.resume(with: Result { try autoreleasepool { try readLibrary() } })
    }
  }
}

private func stamp(_ path: String) throws -> FileStamp? {
  var info = stat()
  guard stat(path, &info) == 0 else {
    let code = errno
    if code == ENOENT { return nil }
    if code == EPERM || code == EACCES { throw ServerError.notAuthorized(databaseAccessMessage) }
    throw ServerError.internalError(
      "The GameTrack database could not be examined (\(String(cString: strerror(code))))")
  }
  return FileStamp(
    seconds: info.st_mtimespec.tv_sec, nanoseconds: info.st_mtimespec.tv_nsec,
    size: Int64(info.st_size))
}

private func readLibrary() throws -> LibraryData {
  let path = databasePath.withLock { $0 }
  guard let database = try stamp(path) else {
    throw ServerError.internalError(
      "No GameTrack database at \(path); open GameTrack once on this Mac to create it")
  }
  let signature = Signature(database: database, wal: try stamp(path + "-wal"))
  if let snapshot = state.snapshot, snapshot.signature == signature,
    snapshot.loaded.duration(to: .now) < snapshotMaxAge
  {
    return snapshot.data
  }
  let started = ContinuousClock.now
  let data = try loadLibrary(
    path: path, modified: max(database.modified, signature.wal?.modified ?? .distantPast))
  state.snapshot = (data, signature, .now)
  serverLogger.debug(
    "Read database",
    metadata: [
      "games": "\(data.games.count)", "lists": "\(data.lists.count)",
      "duration_ms": "\(started.duration(to: .now) / .milliseconds(1))",
    ])
  return data
}

// Core Data's table and column names. Entity numbers, and so the names of the join
// tables that carry them, are reassigned whenever GameTrack's model gains an entity, and
// columns come and go between versions. Names are therefore read from the database on
// every load, and a column this version of the store lacks reads as nil.
private struct Schema {
  let database: Database
  let gameEntity: Int

  init(_ database: Database) throws {
    self.database = database
    guard
      let entity = try database.rows("SELECT Z_ENT FROM Z_PRIMARYKEY WHERE Z_NAME = 'Game'")
        .first?.int("Z_ENT")
    else { throw ServerError.internalError("The database has no Game entity") }
    gameEntity = entity
  }

  func columns(_ table: String) throws -> [String] {
    try database.rows("SELECT name FROM pragma_table_info('\(table)')").compactMap {
      $0.text("name")
    }
  }
  // The wanted columns the table has; no rows when the table is missing.
  func select(_ table: String, _ wanted: [String]) throws -> [Database.Row] {
    let present = Set(try columns(table))
    let names = wanted.filter(present.contains)
    guard !names.isEmpty else { return [] }
    return try database.rows("SELECT \(names.joined(separator: ", ")) FROM \(table)")
  }
  // Pairs of (game primary key, other primary key) from one of Game's many-to-many join
  // tables, named Z_<entity><RELATIONSHIP> with a Z_<entity>GAMES... column for the game.
  func pairs(relationship: String) throws -> [(game: Int, other: Int)] {
    let table = "Z_\(gameEntity)\(relationship)"
    let names = try columns(table)
    guard names.count == 2, let game = names.first(where: { $0.hasPrefix("Z_\(gameEntity)GAMES") }),
      let other = names.first(where: { $0 != game })
    else {
      serverLogger.warning("Join table not found", metadata: ["table": "\(table)"])
      return []
    }
    return try database.rows("SELECT \(game), \(other) FROM \(table)").compactMap { row in
      guard let gameKey = row.int(game), let otherKey = row.int(other) else { return nil }
      return (gameKey, otherKey)
    }
  }
}

private func loadLibrary(path: String, modified: Date) throws -> LibraryData {
  let database = try Database(path: path)
  // One read transaction, so every table is seen as of the same moment.
  _ = try database.rows("BEGIN")
  defer { _ = try? database.rows("COMMIT") }
  let schema = try Schema(database)

  var genresByKey: [Int: GenreRecord] = [:]
  for row in try schema.select("ZGENRE", ["Z_PK", "ZID", "ZNAME"]) {
    guard let key = row.int("Z_PK"), let id = row.int("ZID") else { continue }
    genresByKey[key] = GenreRecord(id: id, name: row.text("ZNAME") ?? "")
  }
  var tagsByKey: [Int: TagRecord] = [:]
  for row in try schema.select("ZGAMETAG", ["Z_PK", "ZID", "ZTITLE", "ZTINTCOLOUR"]) {
    guard let key = row.int("Z_PK"), let title = row.text("ZTITLE") else { continue }
    tagsByKey[key] = TagRecord(
      id: row.uuid("ZID"), title: title, tintColour: row.text("ZTINTCOLOUR"))
  }

  var gamesByKey: [Int: GameRecord] = [:]
  let gameRows = try schema.select(
    "ZGAME",
    [
      "Z_PK", "ZID", "ZGAMEID", "ZTITLE", "ZSUMMARY", "ZDEVELOPER", "ZPUBLISHER", "ZPOSTERURL",
      "ZBANNERURL", "ZSITEURL", "ZRELEASEDATE", "ZRELEASEYEAR", "ZPLATFORMS",
      "ZADDITIONALPLATFORMS", "ZOWNEDPLATFORM", "ZSTATUS", "ZGAMESTATE", "ZCOMPLETIONSTATE",
      "ZCOMPLETION", "ZPRIORITY", "ZFORMAT", "ZUSERRATING", "ZCRITICRATING", "ZHOURSPLAYED",
      "ZADDITIONALPLAYTIME", "ZSTARTDATE", "ZFINISHDATE", "ZADDEDDATE", "ZUPDATEDAT", "ZNOTES",
      "ZREVIEW", "ZREVIEWSPOILERS", "ZTIMETOBEATSTORY", "ZTIMETOBEATEXTRAS",
      "ZTIMETOBEATCOMPLETE", "ZTIMETOBEATTYPE", "ZSTEAMDECKSTATUS", "ZUSERRATINGVALUE",
      "ZCOMPLETIONMODE", "ZSTEAMID", "ZXBOXID", "ZPLAYSTATIONID",
    ])
  for row in gameRows {
    guard let key = row.int("Z_PK"), let id = row.uuid("ZID"), let igdbId = row.int("ZGAMEID")
    else { continue }
    let userRating = row.int("ZUSERRATING")
    // GameTrack 7 added a fractional rating beside the integer one and exports whichever
    // is set, preferring the new value.
    let ratingValue = row.double("ZUSERRATINGVALUE") ?? 0
    gamesByKey[key] = GameRecord(
      id: id, igdbId: igdbId, title: row.text("ZTITLE") ?? "", summary: row.text("ZSUMMARY"),
      developer: row.text("ZDEVELOPER"), publisher: row.text("ZPUBLISHER"),
      posterUrl: row.text("ZPOSTERURL"), bannerUrl: row.text("ZBANNERURL"),
      siteUrl: row.text("ZSITEURL"), releaseDate: row.date("ZRELEASEDATE"),
      startDate: row.date("ZSTARTDATE"), finishDate: row.date("ZFINISHDATE"),
      addedDate: row.date("ZADDEDDATE"), updatedAt: row.date("ZUPDATEDAT"),
      releaseYear: row.int("ZRELEASEYEAR"), platforms: row.strings("ZPLATFORMS"),
      additionalPlatforms: row.strings("ZADDITIONALPLATFORMS"),
      ownedPlatform: row.text("ZOWNEDPLATFORM"), status: row.text("ZSTATUS"),
      gameState: row.int("ZGAMESTATE"), completionState: row.int("ZCOMPLETIONSTATE"),
      completion: row.int("ZCOMPLETION"), priority: row.int("ZPRIORITY"),
      format: row.int("ZFORMAT"), userRating: userRating,
      criticRating: row.int("ZCRITICRATING"), timeToBeatType: row.int("ZTIMETOBEATTYPE"),
      steamDeckStatus: row.int("ZSTEAMDECKSTATUS"), completionMode: row.int("ZCOMPLETIONMODE"),
      hoursPlayed: row.double("ZHOURSPLAYED"),
      additionalPlaytime: row.double("ZADDITIONALPLAYTIME"),
      userRatingValue: ratingValue > 0 ? ratingValue : userRating.map(Double.init),
      timeToBeatStory: row.double("ZTIMETOBEATSTORY"),
      timeToBeatExtras: row.double("ZTIMETOBEATEXTRAS"),
      timeToBeatComplete: row.double("ZTIMETOBEATCOMPLETE"), notes: row.text("ZNOTES"),
      review: row.text("ZREVIEW"), reviewSpoilers: row.bool("ZREVIEWSPOILERS") ?? false,
      steamId: row.text("ZSTEAMID"), xboxId: row.text("ZXBOXID"),
      playStationId: row.text("ZPLAYSTATIONID"))
  }
  if gamesByKey.count != gameRows.count {
    serverLogger.warning(
      "Skipped games without an id",
      metadata: ["skipped": "\(gameRows.count - gamesByKey.count)"])
  }

  // Counted first, so the genres on each game carry their final counts.
  let genrePairs = try schema.pairs(relationship: "GAMEGENRES").filter {
    gamesByKey[$0.game] != nil && genresByKey[$0.other] != nil
  }
  for (_, genre) in genrePairs { genresByKey[genre]!.gameCount += 1 }
  for (game, genre) in genrePairs { gamesByKey[game]!.genres.append(genresByKey[genre]!) }
  for (game, tag) in try schema.pairs(relationship: "GAMETAGS") {
    guard let record = tagsByKey[tag], gamesByKey[game] != nil else { continue }
    gamesByKey[game]!.tags.append(record.title)
    tagsByKey[tag]!.gameCount += 1
  }
  let playthroughRows = try schema.select(
    "ZPLAYTHROUGH",
    [
      "ZID", "ZGAME", "ZDATESTARTED", "ZDATEFINISHED", "ZLASTPLAYEDAT", "ZDURATION", "ZPROGRESS",
      "ZSTATE", "ZCOMPLETIONSTATE", "ZPLATFORM", "ZNAME", "ZTAGS", "ZHOURSPLAYED", "ZRATING",
    ])
  for row in playthroughRows {
    guard let id = row.uuid("ZID"), let game = row.int("ZGAME"), let gameId = gamesByKey[game]?.id
    else { continue }
    gamesByKey[game]!.playthroughs.append(
      PlaythroughRecord(
        id: id, gameId: gameId, dateStarted: row.date("ZDATESTARTED"),
        dateFinished: row.date("ZDATEFINISHED"), lastPlayedAt: row.date("ZLASTPLAYEDAT"),
        duration: row.int("ZDURATION"), progress: row.int("ZPROGRESS"), state: row.int("ZSTATE"),
        completionState: row.int("ZCOMPLETIONSTATE"), platform: row.text("ZPLATFORM"),
        name: row.text("ZNAME"), tags: row.text("ZTAGS"), playHours: row.double("ZHOURSPLAYED"),
        rating: row.double("ZRATING")))
  }
  // Relationships have no stored order; these orders make every read agree.
  for key in gamesByKey.keys {
    gamesByKey[key]!.genres.sort { $0.id < $1.id }
    gamesByKey[key]!.tags.sort()
    gamesByKey[key]!.playthroughs.sort {
      ($0.dateStarted ?? .distantPast, $0.id) < ($1.dateStarted ?? .distantPast, $1.id)
    }
  }

  // Manual lists store their games in a join table, and each game's place in a Position.
  var entries: [Int: [Int: ListEntryRecord]] = [:]
  for (game, list) in try schema.pairs(relationship: "LIST") {
    guard let gameId = gamesByKey[game]?.id else { continue }
    entries[list, default: [:]][game] = ListEntryRecord(
      gameId: gameId, position: nil, section: nil)
  }
  for row in try schema.select("ZPOSITION", ["ZGAME", "ZLIST", "ZINDEX", "ZSECTION"]) {
    guard let game = row.int("ZGAME"), let list = row.int("ZLIST"),
      let gameId = gamesByKey[game]?.id
    else { continue }
    entries[list, default: [:]][game] = ListEntryRecord(
      gameId: gameId, position: row.int("ZINDEX"), section: row.text("ZSECTION"))
  }
  var filters: [Int: [SmartFilterRecord]] = [:]
  let filterRows = try schema.select(
    "ZSMARTFILTER",
    [
      "Z_PK", "ZLIST", "ZTYPE", "ZFILTEROPTION", "ZSELECTEDOPTIONS", "ZSELECTEDRATING",
      "ZSELECTEDPROGRESS", "ZSELECTEDFROMDATE", "ZSELECTEDTODATE",
    ])
  for row in filterRows.sorted(by: { ($0.int("Z_PK") ?? 0) < ($1.int("Z_PK") ?? 0) }) {
    guard let list = row.int("ZLIST") else { continue }
    filters[list, default: []].append(
      SmartFilterRecord(
        type: row.text("ZTYPE"), filterOption: row.text("ZFILTEROPTION"),
        selectedOptions: row.strings("ZSELECTEDOPTIONS"),
        selectedRating: row.int("ZSELECTEDRATING"),
        selectedProgress: row.int("ZSELECTEDPROGRESS"),
        selectedFromDate: row.date("ZSELECTEDFROMDATE"),
        selectedToDate: row.date("ZSELECTEDTODATE")))
  }
  let listRows = try schema.select(
    "ZLIST",
    [
      "Z_PK", "ZID", "ZLISTID", "ZLISTNAME", "ZLISTDESCRIPTION", "ZLISTTYPE", "ZTINTCOLOUR",
      "ZICONNAME", "ZRANKED", "ZCALENDAR", "ZLISTPOSITION", "ZSORTTYPE", "ZSORTDIRECTION",
      "ZGROUPTYPE", "ZGROUPSORTDIRECTION", "ZSMARTFILTERMATCHING",
    ])
  let lists = listRows.compactMap { row -> ListRecord? in
    guard let key = row.int("Z_PK"), let id = row.uuid("ZID") else { return nil }
    return ListRecord(
      id: id, listId: row.int("ZLISTID"), position: row.int("ZLISTPOSITION"),
      smartFilterMatching: row.int("ZSMARTFILTERMATCHING"), name: row.text("ZLISTNAME") ?? "",
      description: row.text("ZLISTDESCRIPTION"), type: row.text("ZLISTTYPE"),
      tintColour: row.text("ZTINTCOLOUR"), iconName: row.text("ZICONNAME"),
      sortType: row.text("ZSORTTYPE"), sortDirection: row.text("ZSORTDIRECTION"),
      groupType: row.text("ZGROUPTYPE"), groupSortDirection: row.text("ZGROUPSORTDIRECTION"),
      ranked: row.bool("ZRANKED") ?? false, calendar: row.bool("ZCALENDAR") ?? false,
      smartFilters: filters[key] ?? [],
      entries: (entries[key] ?? [:]).values.sorted {
        ($0.position ?? .max, $0.gameId) < ($1.position ?? .max, $1.gameId)
      })
  }.sorted { ($0.name.lowercased(), $0.id) < ($1.name.lowercased(), $1.id) }

  return LibraryData(
    games: Array(gamesByKey.values), lists: lists,
    tags: tagsByKey.values.sorted { $0.title.lowercased() < $1.title.lowercased() },
    genres: genresByKey.values.sorted { $0.id < $1.id }, modified: modified)
}
