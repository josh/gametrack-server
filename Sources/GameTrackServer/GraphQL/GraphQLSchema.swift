import Foundation
import GraphQL

// Resolvers receive the Swift record their parent field returned.
func record<Source>(_ source: any Sendable, as _: Source.Type) throws -> Source {
  guard let value = source as? Source else {
    throw ServerError.internalError("Unexpected GraphQL source; expected \(Source.self)")
  }
  return value
}
func field<Source, Value: Sendable>(
  _ type: GraphQLOutputType, _ value: @escaping @Sendable (Source) throws -> Value,
  description: String? = nil
) -> GraphQLField {
  GraphQLField(
    type: type, description: description,
    resolve: { source, _, _, _ in try value(record(source, as: Source.self)) })
}
func requestContext(_ context: (any Sendable)?) throws -> GraphQLContext {
  guard let context = context as? GraphQLContext else {
    throw ServerError.internalError("Missing GraphQL request context")
  }
  return context
}
private func library(_ context: (any Sendable)?) async throws -> LibraryData {
  try await requestContext(context).library()
}
struct PageInfo: Sendable {
  let offset, limit: Int
  let hasNextPage, hasPreviousPage: Bool
}
struct GraphQLPage<Item: Sendable>: Sendable {
  let items: [Item]
  let totalCount: Int
  let pageInfo: PageInfo
}
func page<Item: Sendable>(_ values: [Item], limit: Int, offset: Int) throws -> GraphQLPage<Item> {
  guard (1...100).contains(limit), offset >= 0 else {
    throw ServerError.invalidArgument("limit must be 1...100 and offset must be nonnegative")
  }
  let start = min(offset, values.count)
  let end = min(start + limit, values.count)
  return GraphQLPage(
    items: Array(values[start..<end]), totalCount: values.count,
    pageInfo: PageInfo(
      offset: offset, limit: limit, hasNextPage: end < values.count,
      hasPreviousPage: offset > 0 && !values.isEmpty))
}

// One read of the database per HTTP execution, shared by every field and root alias, so
// a query sees one moment even if GameTrack writes while it runs. A Task caches failures
// as well as successes and coalesces concurrent resolver calls.
actor GraphQLContext {
  private var data: Task<LibraryData, Error>?
  func library() async throws -> LibraryData {
    if data == nil { data = Task { try await currentLibrary() } }
    return try await data!.value
  }
}

func makeSchema() throws -> GraphQLSchema {
  func enumeration(_ name: String, _ values: [String], descriptions: [String: String] = [:])
    throws -> GraphQLEnumType
  {
    try GraphQLEnumType(
      name: name,
      values: GraphQLEnumValueMap(
        uniqueKeysWithValues: values.map {
          ($0, GraphQLEnumValue(value: .string($0), description: descriptions[$0]))
        }))
  }
  let dateTime = try GraphQLScalarType(
    name: "DateTime", description: "RFC 3339 timestamp with an explicit offset, serialized in UTC.",
    // Every output date comes from timestamp() and is already canonical UTC.
    serialize: { value in
      guard let text = value as? String else {
        throw ServerError.internalError("DateTime output is not a string")
      }
      return .string(text)
    },
    parseValue: { value in
      _ = try parseTimestamp(value.stringValue())
      return value
    },
    parseLiteral: { node in
      let value = try valueFromASTUntyped(valueAST: node)
      _ = try parseTimestamp(value.stringValue())
      return value
    })
  let gameState = try enumeration(
    "GameState", GameState.allCases.map(\.rawValue),
    descriptions: [
      "IN_PROGRESS": "Being played.", "QUEUED": "Lined up to play.",
      "COLLECTION": "Owned, with no plan to play yet.", "COMPLETED": "Finished.",
      "ABANDONED": "Dropped.", "WANTED": "On the wishlist; not owned.",
    ])
  let direction = try enumeration(
    "SortDirection", SortDirection.allCases.map(\.rawValue),
    descriptions: ["ASC": "Smallest or earliest first.", "DESC": "Largest or latest first."])
  let gameSortField = try enumeration(
    "GameSortField", GameSortField.allCases.map(\.rawValue),
    descriptions: [
      "TITLE": "The title, ignoring case.", "IGDB_ID": "The IGDB ID.",
      "RELEASE_DATE": "When the game is released.",
      "ADDED_DATE": "When the game was added to GameTrack.",
      "START_DATE": "When the user started the game.",
      "FINISH_DATE": "When the user finished or abandoned the game.",
      "UPDATED_AT": "When the game's entry last changed.",
      "USER_RATING": "The user's rating; unrated games sort last.",
      "CRITIC_RATING": "The critics' score; games without one sort last.",
      "HOURS_PLAYED": "Hours played.",
    ])
  let strings = GraphQLNonNull(GraphQLList(GraphQLNonNull(GraphQLString)))
  let nonNullInt = GraphQLNonNull(GraphQLInt)
  let nonNullString = GraphQLNonNull(GraphQLString)
  let nonNullBoolean = GraphQLNonNull(GraphQLBoolean)

  let genre = try GraphQLObjectType(
    name: "Genre", description: "A genre, as GameTrack takes it from IGDB.",
    fields: [
      "id": field(nonNullInt, \GenreRecord.id, description: FieldDocs.Genre.id),
      "name": field(nonNullString, \GenreRecord.name, description: FieldDocs.Genre.name),
      "gameCount": field(
        nonNullInt, \GenreRecord.gameCount, description: FieldDocs.Genre.gameCount),
    ])
  let tag = try GraphQLObjectType(
    name: "Tag", description: "A tag the user made.",
    fields: [
      "id": field(GraphQLID, \TagRecord.id, description: FieldDocs.Tag.id),
      "title": field(nonNullString, \TagRecord.title, description: FieldDocs.Tag.title),
      "tintColour": field(
        GraphQLString, \TagRecord.tintColour, description: FieldDocs.Tag.tintColour),
      "gameCount": field(nonNullInt, \TagRecord.gameCount, description: FieldDocs.Tag.gameCount),
    ])

  func playthroughDate(
    _ value: KeyPath<PlaythroughRecord, Date?> & Sendable, _ description: String
  ) -> GraphQLField {
    field(
      dateTime, { (item: PlaythroughRecord) in item[keyPath: value].map(timestamp) },
      description: description)
  }
  let playthrough = try GraphQLObjectType(
    name: "Playthrough", description: "One run through a game.",
    fields: [
      "id": field(
        GraphQLNonNull(GraphQLID), \PlaythroughRecord.id, description: FieldDocs.Playthrough.id),
      "dateStarted": playthroughDate(\.dateStarted, FieldDocs.Playthrough.dateStarted),
      "dateFinished": playthroughDate(\.dateFinished, FieldDocs.Playthrough.dateFinished),
      "duration": field(
        GraphQLInt, \PlaythroughRecord.duration, description: FieldDocs.Playthrough.duration),
      "progress": field(
        GraphQLInt, \PlaythroughRecord.progress, description: FieldDocs.Playthrough.progress),
      "state": field(
        GraphQLInt, \PlaythroughRecord.state, description: FieldDocs.Playthrough.state),
      "completionState": field(
        GraphQLInt, \PlaythroughRecord.completionState,
        description: FieldDocs.Playthrough.completionState),
      "platform": field(
        GraphQLString, \PlaythroughRecord.platform, description: FieldDocs.Playthrough.platform),
      "playHours": field(
        GraphQLFloat, \PlaythroughRecord.playHours,
        description: FieldDocs.Playthrough.playHours),
      "lastPlayedAt": playthroughDate(\.lastPlayedAt, FieldDocs.Playthrough.lastPlayedAt),
      "name": field(
        GraphQLString, \PlaythroughRecord.name, description: FieldDocs.Playthrough.name),
      "rating": field(
        GraphQLFloat, \PlaythroughRecord.rating, description: FieldDocs.Playthrough.rating),
      "tags": field(
        GraphQLString, \PlaythroughRecord.tags, description: FieldDocs.Playthrough.tags),
    ])

  func date(_ value: KeyPath<GameRecord, Date?> & Sendable, _ description: String)
    -> GraphQLField
  {
    field(
      dateTime, { (game: GameRecord) in game[keyPath: value].map(timestamp) },
      description: description)
  }
  func int(_ value: KeyPath<GameRecord, Int?> & Sendable, _ description: String) -> GraphQLField {
    field(GraphQLInt, { (game: GameRecord) in game[keyPath: value] }, description: description)
  }
  func float(_ value: KeyPath<GameRecord, Double?> & Sendable, _ description: String)
    -> GraphQLField
  {
    field(GraphQLFloat, { (game: GameRecord) in game[keyPath: value] }, description: description)
  }
  func string(_ value: KeyPath<GameRecord, String?> & Sendable, _ description: String)
    -> GraphQLField
  {
    field(GraphQLString, { (game: GameRecord) in game[keyPath: value] }, description: description)
  }
  let game = try GraphQLObjectType(
    name: "Game",
    description:
      "A game in GameTrack. Fields carry what GameTrack stores, under the names its own export uses.",
    fields: [
      "id": field(GraphQLNonNull(GraphQLID), \GameRecord.id, description: FieldDocs.Game.id),
      "igdbId": field(nonNullInt, \GameRecord.igdbId, description: FieldDocs.Game.igdbId),
      "title": field(nonNullString, \GameRecord.title, description: FieldDocs.Game.title),
      "summary": string(\.summary, FieldDocs.Game.summary),
      "developer": string(\.developer, FieldDocs.Game.developer),
      "publisher": string(\.publisher, FieldDocs.Game.publisher),
      "posterUrl": string(\.posterUrl, FieldDocs.Game.posterUrl),
      "bannerUrl": string(\.bannerUrl, FieldDocs.Game.bannerUrl),
      "siteUrl": string(\.siteUrl, FieldDocs.Game.siteUrl),
      "releaseDate": date(\.releaseDate, FieldDocs.Game.releaseDate),
      "releaseYear": int(\.releaseYear, FieldDocs.Game.releaseYear),
      "platforms": field(strings, \GameRecord.platforms, description: FieldDocs.Game.platforms),
      "ownedPlatform": string(\.ownedPlatform, FieldDocs.Game.ownedPlatform),
      "additionalPlatforms": field(
        strings, \GameRecord.additionalPlatforms,
        description: FieldDocs.Game.additionalPlatforms),
      "status": string(\.status, FieldDocs.Game.status),
      "state": field(
        gameState, { (game: GameRecord) in game.state?.rawValue },
        description: FieldDocs.Game.state),
      "gameState": int(\.gameState, FieldDocs.Game.gameState),
      "completionState": int(\.completionState, FieldDocs.Game.completionState),
      "completion": int(\.completion, FieldDocs.Game.completion),
      "priority": int(\.priority, FieldDocs.Game.priority),
      "format": int(\.format, FieldDocs.Game.format),
      "userRating": int(\.userRating, FieldDocs.Game.userRating),
      "userRatingValue": float(\.userRatingValue, FieldDocs.Game.userRatingValue),
      "criticRating": int(\.criticRating, FieldDocs.Game.criticRating),
      "hoursPlayed": float(\.hoursPlayed, FieldDocs.Game.hoursPlayed),
      "additionalPlaytime": float(\.additionalPlaytime, FieldDocs.Game.additionalPlaytime),
      "startDate": date(\.startDate, FieldDocs.Game.startDate),
      "finishDate": date(\.finishDate, FieldDocs.Game.finishDate),
      "addedDate": date(\.addedDate, FieldDocs.Game.addedDate),
      "updatedAt": date(\.updatedAt, FieldDocs.Game.updatedAt),
      "notes": string(\.notes, FieldDocs.Game.notes),
      "review": string(\.review, FieldDocs.Game.review),
      "reviewSpoilers": field(
        nonNullBoolean, \GameRecord.reviewSpoilers, description: FieldDocs.Game.reviewSpoilers),
      "timeToBeatStory": float(\.timeToBeatStory, FieldDocs.Game.timeToBeatStory),
      "timeToBeatExtras": float(\.timeToBeatExtras, FieldDocs.Game.timeToBeatExtras),
      "timeToBeatComplete": float(\.timeToBeatComplete, FieldDocs.Game.timeToBeatComplete),
      "timeToBeatType": int(\.timeToBeatType, FieldDocs.Game.timeToBeatType),
      "steamDeckStatus": int(\.steamDeckStatus, FieldDocs.Game.steamDeckStatus),
      "completionMode": int(\.completionMode, FieldDocs.Game.completionMode),
      "steamId": string(\.steamId, FieldDocs.Game.steamId),
      "xboxId": string(\.xboxId, FieldDocs.Game.xboxId),
      "playStationId": string(\.playStationId, FieldDocs.Game.playStationId),
      "genres": field(
        GraphQLNonNull(GraphQLList(GraphQLNonNull(genre))), \GameRecord.genres,
        description: FieldDocs.Game.genres),
      "tags": GraphQLField(
        type: GraphQLNonNull(GraphQLList(GraphQLNonNull(tag))),
        description: "The tags on the game, in alphabetical order.",
        resolve: { source, _, context, _ in
          let titles = try record(source, as: GameRecord.self).tags
          let tags = try await library(context).tags
          return titles.compactMap { title in tags.first { $0.title == title } }
        }),
      "playthroughs": field(
        GraphQLNonNull(GraphQLList(GraphQLNonNull(playthrough))), \GameRecord.playthroughs,
        description: FieldDocs.Game.playthroughs),
    ])

  let pageInfo = try GraphQLObjectType(
    name: "PageInfo",
    fields: [
      "offset": field(nonNullInt, \PageInfo.offset, description: "Requested zero-based offset."),
      "limit": field(nonNullInt, \PageInfo.limit, description: "Requested maximum page size."),
      "hasNextPage": field(
        nonNullBoolean, \PageInfo.hasNextPage,
        description: "Whether results exist after this page."),
      "hasPreviousPage": field(
        nonNullBoolean, \PageInfo.hasPreviousPage,
        description: "Whether matching results exist before the requested offset."),
    ])
  let gamePage = try GraphQLObjectType(
    name: "GamePage",
    fields: [
      "items": field(
        GraphQLNonNull(GraphQLList(GraphQLNonNull(game))), \GraphQLPage<GameRecord>.items,
        description: FieldDocs.GamePage.items),
      "totalCount": field(
        nonNullInt, \GraphQLPage<GameRecord>.totalCount,
        description: FieldDocs.GamePage.totalCount),
      "pageInfo": field(
        GraphQLNonNull(pageInfo), \GraphQLPage<GameRecord>.pageInfo,
        description: "Position and availability of neighboring pages."),
    ])

  func filterDate(_ value: KeyPath<SmartFilterRecord, Date?> & Sendable, _ description: String)
    -> GraphQLField
  {
    field(
      dateTime, { (filter: SmartFilterRecord) in filter[keyPath: value].map(timestamp) },
      description: description)
  }
  let smartFilter = try GraphQLObjectType(
    name: "SmartFilter",
    description: "One rule of a smart list, as stored. GameTrack evaluates the rules.",
    fields: [
      "type": field(
        GraphQLString, \SmartFilterRecord.type, description: FieldDocs.SmartFilter.type),
      "selectedOptions": field(
        strings, \SmartFilterRecord.selectedOptions,
        description: FieldDocs.SmartFilter.selectedOptions),
      "selectedRating": field(
        GraphQLInt, \SmartFilterRecord.selectedRating,
        description: FieldDocs.SmartFilter.selectedRating),
      "selectedProgress": field(
        GraphQLInt, \SmartFilterRecord.selectedProgress,
        description: FieldDocs.SmartFilter.selectedProgress),
      "selectedFromDate": filterDate(\.selectedFromDate, FieldDocs.SmartFilter.selectedFromDate),
      "selectedToDate": filterDate(\.selectedToDate, FieldDocs.SmartFilter.selectedToDate),
      "filterOption": field(
        GraphQLString, \SmartFilterRecord.filterOption,
        description: FieldDocs.SmartFilter.filterOption),
    ])
  let listEntry = try GraphQLObjectType(
    name: "ListEntry", description: "A game's place in a manual list.",
    fields: [
      "game": GraphQLField(
        type: GraphQLNonNull(game), description: "The game.",
        resolve: { source, _, context, _ in
          let id = try record(source, as: ListEntryRecord.self).gameId
          guard let game = try await library(context).game(id: id) else {
            throw ServerError.internalError("A list names a game the database does not have")
          }
          return game
        }),
      "position": field(
        GraphQLInt, \ListEntryRecord.position, description: FieldDocs.ListEntry.position),
      "section": field(
        GraphQLString, \ListEntryRecord.section, description: FieldDocs.ListEntry.section),
    ])
  func listString(_ value: KeyPath<ListRecord, String?> & Sendable, _ description: String)
    -> GraphQLField
  {
    field(GraphQLString, { (list: ListRecord) in list[keyPath: value] }, description: description)
  }
  let list = try GraphQLObjectType(
    name: "List", description: "A list of games, either manual or a smart list defined by rules.",
    fields: [
      "id": field(GraphQLNonNull(GraphQLID), \ListRecord.id, description: FieldDocs.List.id),
      "listId": field(GraphQLInt, \ListRecord.listId, description: FieldDocs.List.listId),
      "name": field(nonNullString, \ListRecord.name, description: FieldDocs.List.name),
      "description": listString(\.description, FieldDocs.List.description),
      "type": listString(\.type, FieldDocs.List.type),
      "tintColour": listString(\.tintColour, FieldDocs.List.tintColour),
      "iconName": listString(\.iconName, FieldDocs.List.iconName),
      "ranked": field(nonNullBoolean, \ListRecord.ranked, description: FieldDocs.List.ranked),
      "calendar": field(
        nonNullBoolean, \ListRecord.calendar, description: FieldDocs.List.calendar),
      "position": field(GraphQLInt, \ListRecord.position, description: FieldDocs.List.position),
      "sortType": listString(\.sortType, FieldDocs.List.sortType),
      "sortDirection": listString(\.sortDirection, FieldDocs.List.sortDirection),
      "groupType": listString(\.groupType, FieldDocs.List.groupType),
      "groupSortDirection": listString(\.groupSortDirection, FieldDocs.List.groupSortDirection),
      "smartFilterMatching": field(
        GraphQLInt, \ListRecord.smartFilterMatching,
        description: FieldDocs.List.smartFilterMatching),
      "smart": field(nonNullBoolean, \ListRecord.smart, description: FieldDocs.List.smart),
      "smartFilters": field(
        GraphQLNonNull(GraphQLList(GraphQLNonNull(smartFilter))), \ListRecord.smartFilters,
        description: FieldDocs.List.smartFilters),
      "games": field(
        GraphQLList(GraphQLNonNull(listEntry)), \ListRecord.games,
        description: FieldDocs.List.games),
    ])

  let stateSummary = try GraphQLObjectType(
    name: "StateSummary", description: "Counts for one game state.",
    fields: [
      "state": field(
        GraphQLNonNull(gameState), { (summary: StateSummary) in summary.state.rawValue },
        description: FieldDocs.Summary.state),
      "games": field(nonNullInt, \StateSummary.games, description: FieldDocs.Summary.stateGames),
      "hoursPlayed": field(
        GraphQLNonNull(GraphQLFloat), \StateSummary.hoursPlayed,
        description: FieldDocs.Summary.stateHoursPlayed),
    ])
  func count(_ value: KeyPath<LibrarySummary, Int> & Sendable, _ description: String)
    -> GraphQLField
  {
    field(
      nonNullInt, { (summary: LibrarySummary) in summary[keyPath: value] },
      description: description)
  }
  let librarySummary = try GraphQLObjectType(
    name: "LibrarySummary", description: "Counts across everything in GameTrack.",
    fields: [
      "games": count(\.games, FieldDocs.Summary.games),
      "libraryGames": count(\.libraryGames, FieldDocs.Summary.libraryGames),
      "wishlistGames": count(\.wishlistGames, FieldDocs.Summary.wishlistGames),
      "ratedGames": count(\.ratedGames, FieldDocs.Summary.ratedGames),
      "hoursPlayed": field(
        GraphQLNonNull(GraphQLFloat), \LibrarySummary.hoursPlayed,
        description: FieldDocs.Summary.hoursPlayed),
      "states": field(
        GraphQLNonNull(GraphQLList(GraphQLNonNull(stateSummary))), \LibrarySummary.states,
        description: FieldDocs.Summary.states),
      "lists": count(\.lists, FieldDocs.Summary.lists),
      "tags": count(\.tags, FieldDocs.Summary.tags),
      "genres": count(\.genres, FieldDocs.Summary.genres),
      "modified": field(
        GraphQLNonNull(dateTime), { (summary: LibrarySummary) in timestamp(summary.modified) },
        description: FieldDocs.Summary.modified),
    ])

  let listOfStrings = GraphQLList(GraphQLNonNull(GraphQLString))
  let gameFilter = try GraphQLInputObjectType(
    name: "GameFilter",
    fields: [
      "query": InputObjectField(type: GraphQLString, description: FieldDocs.GameFilter.query),
      "states": InputObjectField(
        type: GraphQLList(GraphQLNonNull(gameState)), description: FieldDocs.GameFilter.states),
      "platforms": InputObjectField(
        type: listOfStrings, description: FieldDocs.GameFilter.platforms),
      "tags": InputObjectField(type: listOfStrings, description: FieldDocs.GameFilter.tags),
      "excludeTags": InputObjectField(
        type: listOfStrings, description: FieldDocs.GameFilter.excludeTags),
      "genres": InputObjectField(type: listOfStrings, description: FieldDocs.GameFilter.genres),
      "rated": InputObjectField(type: GraphQLBoolean, description: FieldDocs.GameFilter.rated),
      "releasedFrom": InputObjectField(
        type: GraphQLString, description: FieldDocs.GameFilter.releasedFrom),
      "releasedBefore": InputObjectField(
        type: GraphQLString, description: FieldDocs.GameFilter.releasedBefore),
      "addedFrom": InputObjectField(
        type: GraphQLString, description: FieldDocs.GameFilter.addedFrom),
      "addedBefore": InputObjectField(
        type: GraphQLString, description: FieldDocs.GameFilter.addedBefore),
      "finishedFrom": InputObjectField(
        type: GraphQLString, description: FieldDocs.GameFilter.finishedFrom),
      "finishedBefore": InputObjectField(
        type: GraphQLString, description: FieldDocs.GameFilter.finishedBefore),
    ])
  let gameOrder = try GraphQLInputObjectType(
    name: "GameOrder",
    fields: [
      "field": InputObjectField(
        type: GraphQLNonNull(gameSortField), description: FieldDocs.GameOrder.field),
      "direction": InputObjectField(
        type: direction, defaultValue: "ASC", description: FieldDocs.GameOrder.direction),
    ])
  let idArg: GraphQLArgumentConfigMap = ["id": GraphQLArgument(type: GraphQLNonNull(GraphQLID))]

  return try GraphQLSchema(
    query: GraphQLObjectType(
      name: "Query",
      fields: [
        "games": GraphQLField(
          type: GraphQLNonNull(gamePage),
          description: "Games in GameTrack, wishlist included, by title unless ordered otherwise.",
          args: [
            "filter": GraphQLArgument(type: gameFilter),
            "orderBy": GraphQLArgument(type: gameOrder),
            "limit": GraphQLArgument(type: nonNullInt, defaultValue: 50),
            "offset": GraphQLArgument(type: nonNullInt, defaultValue: 0),
          ],
          resolve: { _, args, context, _ in
            let arguments = try decodeInput(GraphQLGameSearch.self, from: args)
            return try page(
              arguments.search.games(try await library(context)), limit: arguments.limit,
              offset: arguments.offset)
          }),
        "game": GraphQLField(
          type: game,
          description: "Find a game by its UUID or by its IGDB ID, giving one; null when missing.",
          args: [
            "id": GraphQLArgument(type: GraphQLID, description: FieldDocs.Game.id),
            "igdbId": GraphQLArgument(type: GraphQLInt, description: FieldDocs.Game.igdbId),
          ],
          resolve: { _, args, context, _ in
            let arguments = try decodeInput(GraphQLGameArguments.self, from: args)
            switch (arguments.id, arguments.igdbId) {
            case (let id?, nil): return try await library(context).game(id: id)
            case (nil, let igdbId?): return try await library(context).game(igdbId: igdbId)
            default: throw ServerError.invalidArgument("Give exactly one of id and igdbId")
            }
          }),
        "lists": GraphQLField(
          type: GraphQLNonNull(GraphQLList(GraphQLNonNull(list))),
          description: "Every list, by name.",
          resolve: { _, _, context, _ in try await library(context).lists }),
        "list": GraphQLField(
          type: list, description: "Find a list by its UUID; null when missing.", args: idArg,
          resolve: { _, args, context, _ in
            let id = try decodeInput(GraphQLIDArguments.self, from: args).id
            return try await library(context).list(id: id)
          }),
        "tags": GraphQLField(
          type: GraphQLNonNull(GraphQLList(GraphQLNonNull(tag))),
          description: "Every tag, by title.",
          resolve: { _, _, context, _ in try await library(context).tags }),
        "genres": GraphQLField(
          type: GraphQLNonNull(GraphQLList(GraphQLNonNull(genre))),
          description: "Every genre GameTrack knows, by ID.",
          resolve: { _, _, context, _ in try await library(context).genres }),
        "summary": GraphQLField(
          type: GraphQLNonNull(librarySummary),
          description: "Counts across everything in GameTrack.",
          resolve: { _, _, context, _ in LibrarySummary(try await library(context)) }),
      ]))
}
