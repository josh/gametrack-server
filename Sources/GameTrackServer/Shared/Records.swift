import Foundation

// Codes are the client contract. GraphQL reports them in extensions.code and
// MCP in the error payload; the message is a sentence for people.
enum ErrorCode: String, Encodable, Sendable {
  case invalidArgument = "INVALID_ARGUMENT"
  case notFound = "NOT_FOUND"
  case forbidden = "FORBIDDEN"
  case notAuthorized = "NOT_AUTHORIZED"
  case internalError = "INTERNAL"
}
struct ServerError: Error, CustomStringConvertible, Sendable {
  let code: ErrorCode
  let message: String
  var description: String { message }
  static func invalidArgument(_ message: String) -> Self {
    .init(code: .invalidArgument, message: message)
  }
  static func notFound(_ message: String) -> Self { .init(code: .notFound, message: message) }
  static func forbidden(_ message: String) -> Self { .init(code: .forbidden, message: message) }
  static func notAuthorized(_ message: String) -> Self {
    .init(code: .notAuthorized, message: message)
  }
  static func internalError(_ message: String) -> Self {
    .init(code: .internalError, message: message)
  }
}

// Where a game stands, from the stored gameState integer. Raw values are the API
// spelling; `label` is what GameTrack shows and what the metrics carry.
enum GameState: String, CaseIterable, Codable, Sendable {
  case inProgress = "IN_PROGRESS"
  case queued = "QUEUED"
  case collection = "COLLECTION"
  case completed = "COMPLETED"
  case abandoned = "ABANDONED"
  case wanted = "WANTED"

  init?(stored: Int?) {
    guard let stored, (1...Self.allCases.count).contains(stored) else { return nil }
    self = Self.allCases[stored - 1]
  }
  var label: String {
    switch self {
    case .inProgress: "In Progress"
    case .queued: "Queued"
    case .collection: "Collection"
    case .completed: "Completed"
    case .abandoned: "Abandoned"
    case .wanted: "Wanted"
    }
  }
}

// A genre GameTrack takes from IGDB. `name` carries the emoji GameTrack shows before it.
struct GenreRecord: Encodable, Sendable {
  let id: Int
  let name: String
  var gameCount = 0
  enum CodingKeys: String, CodingKey { case id, name, gameCount }

  // The name without its emoji prefix, lowercased, for matching what a person types.
  var plainName: String { plainGenreName(name) }
}
func plainGenreName(_ name: String) -> String {
  let parts = name.split(separator: " ", maxSplits: 1)
  let plain = parts.count == 2 && !parts[0].contains(where: \.isLetter) ? String(parts[1]) : name
  return plain.lowercased()
}

// A tag the user made. GameTrack identifies tags by title.
struct TagRecord: Encodable, Sendable {
  let id: String?
  let title: String
  let tintColour: String?
  var gameCount = 0
  enum CodingKeys: String, CodingKey { case id, title, tintColour, gameCount }
  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encodeIfPresent(id, forKey: .id)
    try c.encode(title, forKey: .title)
    try c.encodeIfPresent(tintColour, forKey: .tintColour)
    try c.encode(gameCount, forKey: .gameCount)
  }
}

// One run through a game. GameTrack keeps at least one per game it has state for.
struct PlaythroughRecord: Encodable, Sendable {
  let id: String
  let gameId: String
  let dateStarted, dateFinished, lastPlayedAt: Date?
  let duration, progress, state, completionState: Int?
  let platform, name, tags: String?
  let playHours, rating: Double?

  enum CodingKeys: String, CodingKey {
    case id, gameId, dateStarted, dateFinished, duration, progress, state, completionState
    case platform, playHours, lastPlayedAt, name, rating, tags
  }
  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(gameId, forKey: .gameId)
    try c.encodeIfPresent(dateStarted.map(timestamp), forKey: .dateStarted)
    try c.encodeIfPresent(dateFinished.map(timestamp), forKey: .dateFinished)
    try c.encodeIfPresent(duration, forKey: .duration)
    try c.encodeIfPresent(progress, forKey: .progress)
    try c.encodeIfPresent(state, forKey: .state)
    try c.encodeIfPresent(completionState, forKey: .completionState)
    try c.encodeIfPresent(platform, forKey: .platform)
    try c.encodeIfPresent(playHours, forKey: .playHours)
    try c.encodeIfPresent(lastPlayedAt.map(timestamp), forKey: .lastPlayedAt)
    try c.encodeIfPresent(name, forKey: .name)
    try c.encodeIfPresent(rating, forKey: .rating)
    try c.encodeIfPresent(tags, forKey: .tags)
  }
}

// One game. Fields carry what GameTrack stores, under the names its own export uses;
// `state` is the one derived field.
struct GameRecord: Encodable, Sendable {
  let id: String
  let igdbId: Int
  let title: String
  let summary, developer, publisher, posterUrl, bannerUrl, siteUrl: String?
  let releaseDate, startDate, finishDate, addedDate, updatedAt: Date?
  let releaseYear: Int?
  let platforms, additionalPlatforms: [String]
  let ownedPlatform, status: String?
  let gameState, completionState, completion, priority, format: Int?
  let userRating, criticRating, timeToBeatType, steamDeckStatus, completionMode: Int?
  let hoursPlayed, additionalPlaytime, userRatingValue: Double?
  let timeToBeatStory, timeToBeatExtras, timeToBeatComplete: Double?
  let notes, review: String?
  let reviewSpoilers: Bool
  let steamId, xboxId, playStationId: String?
  var genres: [GenreRecord] = []
  var tags: [String] = []
  var playthroughs: [PlaythroughRecord] = []

  var state: GameState? { GameState(stored: gameState) }
  var titleKey: String { title.lowercased() }
  // The year a game belongs to when grouped: the stored year, else the release date's,
  // else nil. GameTrack leaves the stored year 0 for most games that have a date.
  var effectiveReleaseYear: Int? {
    if let releaseYear, releaseYear != 0 { return releaseYear }
    return releaseDate.map { utcCalendar.component(.year, from: $0) }
  }

  enum CodingKeys: String, CodingKey {
    case id, igdbId, title, summary, developer, publisher, posterUrl, bannerUrl, siteUrl
    case releaseDate, releaseYear, platforms, ownedPlatform, additionalPlatforms, status, state
    case gameState, completionState, completion, priority, format, userRating, criticRating
    case hoursPlayed, additionalPlaytime, startDate, finishDate, addedDate, updatedAt, notes
    case review, reviewSpoilers, timeToBeatStory, timeToBeatExtras, timeToBeatComplete
    case timeToBeatType, steamDeckStatus, genres, userRatingValue, completionMode, steamId, xboxId
    case playStationId, tags, playthroughs
  }
  // Optional fields are omitted when absent.
  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encode(igdbId, forKey: .igdbId)
    try c.encode(title, forKey: .title)
    try c.encodeIfPresent(summary, forKey: .summary)
    try c.encodeIfPresent(developer, forKey: .developer)
    try c.encodeIfPresent(publisher, forKey: .publisher)
    try c.encodeIfPresent(posterUrl, forKey: .posterUrl)
    try c.encodeIfPresent(bannerUrl, forKey: .bannerUrl)
    try c.encodeIfPresent(siteUrl, forKey: .siteUrl)
    try c.encodeIfPresent(releaseDate.map(timestamp), forKey: .releaseDate)
    try c.encodeIfPresent(releaseYear, forKey: .releaseYear)
    try c.encode(platforms, forKey: .platforms)
    try c.encodeIfPresent(ownedPlatform, forKey: .ownedPlatform)
    try c.encode(additionalPlatforms, forKey: .additionalPlatforms)
    try c.encodeIfPresent(status, forKey: .status)
    try c.encodeIfPresent(state, forKey: .state)
    try c.encodeIfPresent(gameState, forKey: .gameState)
    try c.encodeIfPresent(completionState, forKey: .completionState)
    try c.encodeIfPresent(completion, forKey: .completion)
    try c.encodeIfPresent(priority, forKey: .priority)
    try c.encodeIfPresent(format, forKey: .format)
    try c.encodeIfPresent(userRating, forKey: .userRating)
    try c.encodeIfPresent(criticRating, forKey: .criticRating)
    try c.encodeIfPresent(hoursPlayed, forKey: .hoursPlayed)
    try c.encodeIfPresent(additionalPlaytime, forKey: .additionalPlaytime)
    try c.encodeIfPresent(startDate.map(timestamp), forKey: .startDate)
    try c.encodeIfPresent(finishDate.map(timestamp), forKey: .finishDate)
    try c.encodeIfPresent(addedDate.map(timestamp), forKey: .addedDate)
    try c.encodeIfPresent(updatedAt.map(timestamp), forKey: .updatedAt)
    try c.encodeIfPresent(notes, forKey: .notes)
    try c.encodeIfPresent(review, forKey: .review)
    try c.encode(reviewSpoilers, forKey: .reviewSpoilers)
    try c.encodeIfPresent(timeToBeatStory, forKey: .timeToBeatStory)
    try c.encodeIfPresent(timeToBeatExtras, forKey: .timeToBeatExtras)
    try c.encodeIfPresent(timeToBeatComplete, forKey: .timeToBeatComplete)
    try c.encodeIfPresent(timeToBeatType, forKey: .timeToBeatType)
    try c.encodeIfPresent(steamDeckStatus, forKey: .steamDeckStatus)
    try c.encode(genres.map(GameGenre.init), forKey: .genres)
    try c.encodeIfPresent(userRatingValue, forKey: .userRatingValue)
    try c.encodeIfPresent(completionMode, forKey: .completionMode)
    try c.encodeIfPresent(steamId, forKey: .steamId)
    try c.encodeIfPresent(xboxId, forKey: .xboxId)
    try c.encodeIfPresent(playStationId, forKey: .playStationId)
    try c.encode(tags, forKey: .tags)
    try c.encode(playthroughs, forKey: .playthroughs)
  }
}
// A genre as it appears on a game, without the library-wide count.
struct GameGenre: Encodable, Sendable {
  let id: Int
  let name: String
  enum CodingKeys: String, CodingKey { case id, name }
  init(_ genre: GenreRecord) {
    id = genre.id
    name = genre.name
  }
}
private let utcCalendar: Calendar = {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = TimeZone(identifier: "UTC")!
  return calendar
}()

// One rule of a smart list, as stored. GameTrack evaluates the rules; the server only
// reports them.
struct SmartFilterRecord: Encodable, Sendable {
  let type, filterOption: String?
  let selectedOptions: [String]
  let selectedRating, selectedProgress: Int?
  let selectedFromDate, selectedToDate: Date?

  enum CodingKeys: String, CodingKey {
    case type, selectedOptions, selectedRating, selectedProgress, selectedFromDate
    case selectedToDate, filterOption
  }
  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encodeIfPresent(type, forKey: .type)
    try c.encode(selectedOptions, forKey: .selectedOptions)
    try c.encodeIfPresent(selectedRating, forKey: .selectedRating)
    try c.encodeIfPresent(selectedProgress, forKey: .selectedProgress)
    try c.encodeIfPresent(selectedFromDate.map(timestamp), forKey: .selectedFromDate)
    try c.encodeIfPresent(selectedToDate.map(timestamp), forKey: .selectedToDate)
    try c.encodeIfPresent(filterOption, forKey: .filterOption)
  }
}
// A game's place in a manual list.
struct ListEntryRecord: Encodable, Sendable {
  let gameId: String
  let position: Int?
  let section: String?
  enum CodingKeys: String, CodingKey { case gameId, position, section }
  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(gameId, forKey: .gameId)
    try c.encodeIfPresent(position, forKey: .position)
    try c.encodeIfPresent(section, forKey: .section)
  }
}
// A list. A list with rules is a smart list: GameTrack computes its games from the rules
// and stores none, so `games` is nil for it.
struct ListRecord: Encodable, Sendable {
  let id: String
  let listId, position, smartFilterMatching: Int?
  let name: String
  let description, type, tintColour, iconName: String?
  let sortType, sortDirection, groupType, groupSortDirection: String?
  let ranked, calendar: Bool
  let smartFilters: [SmartFilterRecord]
  let entries: [ListEntryRecord]

  var smart: Bool { !smartFilters.isEmpty }
  var games: [ListEntryRecord]? { smart ? nil : entries }

  enum CodingKeys: String, CodingKey {
    case id, listId, name, description, type, tintColour, iconName, ranked, calendar, position
    case sortType, sortDirection, groupType, groupSortDirection, smartFilterMatching, smart
    case smartFilters, games
  }
  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(id, forKey: .id)
    try c.encodeIfPresent(listId, forKey: .listId)
    try c.encode(name, forKey: .name)
    try c.encodeIfPresent(description, forKey: .description)
    try c.encodeIfPresent(type, forKey: .type)
    try c.encodeIfPresent(tintColour, forKey: .tintColour)
    try c.encodeIfPresent(iconName, forKey: .iconName)
    try c.encode(ranked, forKey: .ranked)
    try c.encode(calendar, forKey: .calendar)
    try c.encodeIfPresent(position, forKey: .position)
    try c.encodeIfPresent(sortType, forKey: .sortType)
    try c.encodeIfPresent(sortDirection, forKey: .sortDirection)
    try c.encodeIfPresent(groupType, forKey: .groupType)
    try c.encodeIfPresent(groupSortDirection, forKey: .groupSortDirection)
    try c.encodeIfPresent(smartFilterMatching, forKey: .smartFilterMatching)
    try c.encode(smart, forKey: .smart)
    try c.encode(smartFilters, forKey: .smartFilters)
    try c.encodeIfPresent(games, forKey: .games)
  }
}

// One read of the database.
struct LibraryData: Sendable {
  let games: [GameRecord]
  let lists: [ListRecord]
  let tags: [TagRecord]
  let genres: [GenreRecord]
  // When GameTrack last wrote the store: the newer of the database and its WAL.
  let modified: Date
  private let byID: [String: Int]
  private let byIGDB: [Int: Int]

  init(
    games: [GameRecord], lists: [ListRecord], tags: [TagRecord], genres: [GenreRecord],
    modified: Date
  ) {
    self.games = games.sorted {
      $0.titleKey == $1.titleKey ? $0.id < $1.id : $0.titleKey < $1.titleKey
    }
    self.lists = lists
    self.tags = tags
    self.genres = genres
    self.modified = modified
    byID = Dictionary(
      self.games.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    byIGDB = Dictionary(
      self.games.enumerated().map { ($1.igdbId, $0) }, uniquingKeysWith: { first, _ in first })
  }
  // UUIDs are spelled in uppercase, as GameTrack exports them.
  func game(id: String) -> GameRecord? { byID[id.uppercased()].map { games[$0] } }
  func game(igdbId: Int) -> GameRecord? { byIGDB[igdbId].map { games[$0] } }
  func list(id: String) -> ListRecord? { lists.first { $0.id == id.uppercased() } }
}

// Counts for one game state.
struct StateSummary: Encodable, Sendable {
  let state: GameState
  let games: Int
  let hoursPlayed: Double
  enum CodingKeys: String, CodingKey { case state, games, hoursPlayed }
}
// Counts across the whole database. The library is every game that is not Wanted, which
// is what GameTrack counts as "All Games".
struct LibrarySummary: Encodable, Sendable {
  let games, libraryGames, wishlistGames, ratedGames: Int
  let hoursPlayed: Double
  let states: [StateSummary]
  let lists, tags, genres: Int
  let modified: Date

  enum CodingKeys: String, CodingKey {
    case games, libraryGames, wishlistGames, ratedGames, hoursPlayed, states, lists, tags
    case genres, modified
  }
  init(_ data: LibraryData) {
    games = data.games.count
    wishlistGames = data.games.count { $0.state == .wanted }
    libraryGames = games - wishlistGames
    ratedGames = data.games.count { ($0.userRating ?? 0) > 0 }
    hoursPlayed = data.games.reduce(0) { $0 + ($1.hoursPlayed ?? 0) }
    states = GameState.allCases.map { state in
      let matching = data.games.filter { $0.state == state }
      return StateSummary(
        state: state, games: matching.count,
        hoursPlayed: matching.reduce(0) { $0 + ($1.hoursPlayed ?? 0) })
    }
    lists = data.lists.count
    tags = data.tags.count
    genres = data.genres.count
    modified = data.modified
  }
  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(games, forKey: .games)
    try c.encode(libraryGames, forKey: .libraryGames)
    try c.encode(wishlistGames, forKey: .wishlistGames)
    try c.encode(ratedGames, forKey: .ratedGames)
    try c.encode(hoursPlayed, forKey: .hoursPlayed)
    try c.encode(states, forKey: .states)
    try c.encode(lists, forKey: .lists)
    try c.encode(tags, forKey: .tags)
    try c.encode(genres, forKey: .genres)
    try c.encode(timestamp(modified), forKey: .modified)
  }
}
