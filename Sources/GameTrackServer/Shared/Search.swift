import Foundation

// One filter for GraphQL and MCP searches.
enum SortDirection: String, CaseIterable, Decodable, Sendable {
  case ascending = "ASC"
  case descending = "DESC"
}
// What games sort by.
enum GameSortField: String, CaseIterable, Decodable, Sendable {
  case title = "TITLE"
  case igdbId = "IGDB_ID"
  case releaseDate = "RELEASE_DATE"
  case addedDate = "ADDED_DATE"
  case startDate = "START_DATE"
  case finishDate = "FINISH_DATE"
  case updatedAt = "UPDATED_AT"
  case userRating = "USER_RATING"
  case criticRating = "CRITIC_RATING"
  case hoursPlayed = "HOURS_PLAYED"
}

struct Search: Sendable {
  var direction = SortDirection.ascending
  var order: GameSortField?
  var query: String?
  var states: [GameState]?
  var platforms, tags, excludeTags, genres: [String]?
  var rated: Bool?
  // Each date bound is a timestamp or YYYY-MM-DD.
  var releasedFrom, releasedBefore, addedFrom, addedBefore, finishedFrom, finishedBefore: String?

  // Matching games, by title unless ordered otherwise.
  func games(_ data: LibraryData) throws -> [GameRecord] {
    let text = query?.lowercased()
    let platforms = platforms.map { Set($0.map { $0.lowercased() }) }
    let tags = tags.map { Set($0.map { $0.lowercased() }) }
    let excluded = Set((excludeTags ?? []).map { $0.lowercased() })
    let genres = genres.map { Set($0.map { $0.lowercased() }) }
    let released = try DateRange(from: releasedFrom, before: releasedBefore, name: "released")
    let added = try DateRange(from: addedFrom, before: addedBefore, name: "added")
    let finished = try DateRange(from: finishedFrom, before: finishedBefore, name: "finished")
    let matching = data.games.filter { game in
      (states == nil || game.state.map(states!.contains) == true)
        && (platforms == nil
          || game.ownedPlatform.map { platforms!.contains($0.lowercased()) } == true)
        && (tags == nil || game.tags.contains { tags!.contains($0.lowercased()) })
        && !game.tags.contains { excluded.contains($0.lowercased()) }
        && (genres == nil
          || game.genres.contains {
            genres!.contains($0.name.lowercased()) || genres!.contains($0.plainName)
          })
        && (rated == nil || rated == ((game.userRating ?? 0) > 0))
        && released.contains(game.releaseDate) && added.contains(game.addedDate)
        && finished.contains(game.finishDate)
        && (text == nil || text!.isEmpty || game.titleKey.contains(text!)
          || (game.developer ?? "").lowercased().contains(text!)
          || (game.publisher ?? "").lowercased().contains(text!))
    }
    let descending = direction == .descending
    func compare<T: Comparable>(_ a: T?, _ b: T?) -> Bool? {
      if a == b { return nil }
      guard let a else { return false }
      guard let b else { return true }
      return descending ? a > b : a < b
    }
    // GameTrack stores 0 or -1 for a rating that is not set; those sort last, as absent.
    func set(_ rating: Int?) -> Int? { rating.flatMap { $0 > 0 ? $0 : nil } }
    return matching.sorted { a, b in
      let result: Bool?
      switch order ?? .title {
      case .title: result = compare(a.titleKey, b.titleKey)
      case .igdbId: result = compare(a.igdbId, b.igdbId)
      case .releaseDate: result = compare(a.releaseDate, b.releaseDate)
      case .addedDate: result = compare(a.addedDate, b.addedDate)
      case .startDate: result = compare(a.startDate, b.startDate)
      case .finishDate: result = compare(a.finishDate, b.finishDate)
      case .updatedAt: result = compare(a.updatedAt, b.updatedAt)
      case .userRating: result = compare(set(a.userRating), set(b.userRating))
      case .criticRating: result = compare(set(a.criticRating), set(b.criticRating))
      case .hoursPlayed: result = compare(a.hoursPlayed, b.hoursPlayed)
      }
      // Ties fall back to title, then identifier, so pages are stable.
      return result ?? (a.titleKey == b.titleKey ? a.id < b.id : a.titleKey < b.titleKey)
    }
  }
}

// A half-open range of instants; a game without the date matches only an unbounded range.
private struct DateRange {
  let from, before: Date?
  init(from: String?, before: String?, name: String) throws {
    self.from = try from.map(parseBound)
    self.before = try before.map(parseBound)
    if let lower = self.from, let upper = self.before, lower >= upper {
      throw ServerError.invalidArgument("\(name)From must precede \(name)Before")
    }
  }
  func contains(_ date: Date?) -> Bool {
    if from == nil && before == nil { return true }
    guard let date else { return false }
    return (from == nil || date >= from!) && (before == nil || date < before!)
  }
}
