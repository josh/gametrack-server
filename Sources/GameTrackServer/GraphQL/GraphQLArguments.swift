import Foundation

// Typed collection arguments. GraphQL has already checked their types and filled
// defaults; decoding gives resolvers named fields instead of map lookups.

struct GraphQLGameSearch: Decodable {
  let filter: Filter?
  let orderBy: Order?
  let limit, offset: Int

  struct Filter: Decodable, Sendable {
    let query: String?
    let states: [GameState]?
    let platforms, tags, excludeTags, genres: [String]?
    let rated: Bool?
    let releasedFrom, releasedBefore, addedFrom, addedBefore, finishedFrom, finishedBefore: String?
  }
  struct Order: Decodable, Sendable {
    let field: GameSortField
    let direction: SortDirection?
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

struct GraphQLIDArguments: Decodable {
  let id: String
}

// A game is found by its UUID or its IGDB ID; exactly one must be given.
struct GraphQLGameArguments: Decodable {
  let id: String?
  let igdbId: Int?
}
