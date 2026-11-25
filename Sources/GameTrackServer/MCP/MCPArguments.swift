import Foundation

// Typed tool arguments. Each rejects keys its tool does not declare. MCP rejects
// explicit nulls before decoding, so optional fields are plain optionals.

struct IDArguments: Decodable {
  let id: String
  enum CodingKeys: String, CodingKey, CaseIterable { case id }
  init(from decoder: Decoder) throws {
    id = try decoder.inputContainer(keyedBy: CodingKeys.self).decode(String.self, forKey: .id)
    guard !id.isEmpty else { throw ServerError.invalidArgument("id required") }
  }
}

// A game is found by its UUID or its IGDB ID; exactly one must be given.
struct GameArguments: Decodable {
  let id: String?
  let igdbId: Int?
  enum CodingKeys: String, CodingKey, CaseIterable { case id, igdbId }
  init(from decoder: Decoder) throws {
    let c = try decoder.inputContainer(keyedBy: CodingKeys.self)
    id = try c.decodeIfPresent(String.self, forKey: .id)
    igdbId = try c.decodeIfPresent(Int.self, forKey: .igdbId)
    guard (id == nil) != (igdbId == nil), id != "" else {
      throw ServerError.invalidArgument("Give exactly one of id and igdbId")
    }
  }
}

struct GameSearchArguments: Decodable {
  let filter: Filter?
  let orderBy: Order?
  let limit: Int?
  let cursor: String?

  struct Filter: Decodable {
    let query: String?
    let states: [GameState]?
    let platforms, tags, excludeTags, genres: [String]?
    let rated: Bool?
    let releasedFrom, releasedBefore, addedFrom, addedBefore, finishedFrom, finishedBefore: String?
    enum CodingKeys: String, CodingKey, CaseIterable {
      case query, states, platforms, tags, excludeTags, genres, rated, releasedFrom, releasedBefore,
        addedFrom
      case addedBefore, finishedFrom, finishedBefore
    }
    init(from decoder: Decoder) throws {
      let c = try decoder.inputContainer(keyedBy: CodingKeys.self)
      query = try c.decodeIfPresent(String.self, forKey: .query)
      states = try c.decodeIfPresent([GameState].self, forKey: .states)
      platforms = try c.decodeIfPresent([String].self, forKey: .platforms)
      tags = try c.decodeIfPresent([String].self, forKey: .tags)
      excludeTags = try c.decodeIfPresent([String].self, forKey: .excludeTags)
      genres = try c.decodeIfPresent([String].self, forKey: .genres)
      rated = try c.decodeIfPresent(Bool.self, forKey: .rated)
      releasedFrom = try c.decodeIfPresent(String.self, forKey: .releasedFrom)
      releasedBefore = try c.decodeIfPresent(String.self, forKey: .releasedBefore)
      addedFrom = try c.decodeIfPresent(String.self, forKey: .addedFrom)
      addedBefore = try c.decodeIfPresent(String.self, forKey: .addedBefore)
      finishedFrom = try c.decodeIfPresent(String.self, forKey: .finishedFrom)
      finishedBefore = try c.decodeIfPresent(String.self, forKey: .finishedBefore)
    }
  }
  struct Order: Decodable {
    let field: GameSortField
    let direction: SortDirection?
    enum CodingKeys: String, CodingKey, CaseIterable { case field, direction }
    init(from decoder: Decoder) throws {
      let c = try decoder.inputContainer(keyedBy: CodingKeys.self)
      field = try c.decode(GameSortField.self, forKey: .field)
      direction = try c.decodeIfPresent(SortDirection.self, forKey: .direction)
    }
  }
  enum CodingKeys: String, CodingKey, CaseIterable { case filter, orderBy, limit, cursor }
  init(from decoder: Decoder) throws {
    let c = try decoder.inputContainer(keyedBy: CodingKeys.self)
    filter = try c.decodeIfPresent(Filter.self, forKey: .filter)
    orderBy = try c.decodeIfPresent(Order.self, forKey: .orderBy)
    limit = try c.decodeIfPresent(Int.self, forKey: .limit)
    cursor = try c.decodeIfPresent(String.self, forKey: .cursor)
  }

  var search: Search {
    var search = Search()
    if let filter {
      search.query = filter.query
      search.states = filter.states
      search.platforms = filter.platforms
      search.tags = filter.tags
      search.excludeTags = filter.excludeTags
      search.genres = filter.genres
      search.rated = filter.rated
      search.releasedFrom = filter.releasedFrom
      search.releasedBefore = filter.releasedBefore
      search.addedFrom = filter.addedFrom
      search.addedBefore = filter.addedBefore
      search.finishedFrom = filter.finishedFrom
      search.finishedBefore = filter.finishedBefore
    }
    if let orderBy {
      search.order = orderBy.field
      search.direction = orderBy.direction ?? .ascending
    }
    return search
  }
}
