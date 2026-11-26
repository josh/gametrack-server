import Foundation
import MCP
import NIOHTTP1

private struct PageOutput<Item: Encodable>: Encodable {
  let items: [Item]
  let totalCount: Int
  let nextCursor: String?
  enum CodingKeys: String, CodingKey { case items, totalCount, nextCursor }
}
private struct GameOutput: Encodable {
  let game: GameRecord?
  enum CodingKeys: CodingKey { case game }
  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(game, forKey: .game)
  }
}
private struct ListOutput: Encodable {
  let list: ListRecord?
  enum CodingKeys: CodingKey { case list }
  func encode(to encoder: Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encode(list, forKey: .list)
  }
}
private struct ListsOutput: Encodable {
  let lists: [ListRecord]
  enum CodingKeys: CodingKey { case lists }
}
private struct TagsOutput: Encodable {
  let tags: [TagRecord]
  enum CodingKeys: CodingKey { case tags }
}
private struct GenresOutput: Encodable {
  let genres: [GenreRecord]
  enum CodingKeys: CodingKey { case genres }
}
private func describe(_ value: Value, _ text: String) -> Value {
  guard case .object(var object) = value else { return value }
  object["description"] = .string(text)
  return .object(object)
}
private func object(_ properties: [String: Value], required: [String] = []) -> Value {
  .object([
    "type": .string(JSONType.object.rawValue), "properties": .object(properties),
    "required": .array(required.map(Value.string)), "additionalProperties": false,
  ])
}
// An object schema whose property names are the coding keys of the type it describes,
// so the schema cannot name a field the encoder or decoder does not use.
private func schema<Key: CodingKey>(
  _: Key.Type, _ properties: KeyValuePairs<Key, Value>, required: [Key] = []
) -> Value {
  object(
    Dictionary(uniqueKeysWithValues: properties.map { ($0.key.stringValue, $0.value) }),
    required: required.map(\.stringValue))
}
// JSON Schema type names.
private enum JSONType: String { case object, array, string, integer, number, boolean, null }
// A value of one JSON type, with optional keywords such as minimum or default.
private func primitive(_ type: JSONType, _ keywords: [String: Value] = [:]) -> Value {
  .object(keywords.merging(["type": .string(type.rawValue)]) { _, type in type })
}
private func array(_ item: Value) -> Value {
  .object(["type": .string(JSONType.array.rawValue), "items": item])
}
private func enumeration(_ values: [String]) -> Value {
  primitive(.string, ["enum": .array(values.map(Value.string))])
}
private func nullable(_ value: Value) -> Value {
  .object(["anyOf": .array([value, primitive(.null)])])
}
private func toolsCatalog() -> [Tool] {
  let integer = primitive(.integer)
  let number = primitive(.number)
  let string = primitive(.string)
  let boolean = primitive(.boolean)
  let limit = describe(
    primitive(.integer, ["minimum": 1, "maximum": 100, "default": 50]),
    "Maximum items in the page, from 1 through 100; defaults to 50.")
  let cursor = describe(
    string, "nextCursor from the previous page; omit for the first page.")
  let states = enumeration(GameState.allCases.map(\.rawValue))

  let gameGenre = schema(
    GameGenre.CodingKeys.self,
    [
      .id: describe(integer, FieldDocs.Genre.id),
      .name: describe(string, FieldDocs.Genre.name),
    ], required: [.id, .name])
  let genre = schema(
    GenreRecord.CodingKeys.self,
    [
      .id: describe(integer, FieldDocs.Genre.id),
      .name: describe(string, FieldDocs.Genre.name),
      .gameCount: describe(integer, FieldDocs.Genre.gameCount),
    ], required: [.id, .name, .gameCount])
  let tag = schema(
    TagRecord.CodingKeys.self,
    [
      .id: describe(string, FieldDocs.Tag.id),
      .title: describe(string, FieldDocs.Tag.title),
      .tintColour: describe(string, FieldDocs.Tag.tintColour),
      .gameCount: describe(integer, FieldDocs.Tag.gameCount),
    ], required: [.title, .gameCount])
  let playthrough = schema(
    PlaythroughRecord.CodingKeys.self,
    [
      .id: describe(string, FieldDocs.Playthrough.id),
      .gameId: describe(string, FieldDocs.Playthrough.gameId),
      .dateStarted: describe(string, FieldDocs.Playthrough.dateStarted),
      .dateFinished: describe(string, FieldDocs.Playthrough.dateFinished),
      .duration: describe(integer, FieldDocs.Playthrough.duration),
      .progress: describe(integer, FieldDocs.Playthrough.progress),
      .state: describe(integer, FieldDocs.Playthrough.state),
      .completionState: describe(integer, FieldDocs.Playthrough.completionState),
      .platform: describe(string, FieldDocs.Playthrough.platform),
      .playHours: describe(number, FieldDocs.Playthrough.playHours),
      .lastPlayedAt: describe(string, FieldDocs.Playthrough.lastPlayedAt),
      .name: describe(string, FieldDocs.Playthrough.name),
      .rating: describe(number, FieldDocs.Playthrough.rating),
      .tags: describe(string, FieldDocs.Playthrough.tags),
    ], required: [.id, .gameId])
  let game = schema(
    GameRecord.CodingKeys.self,
    [
      .id: describe(string, FieldDocs.Game.id),
      .igdbId: describe(integer, FieldDocs.Game.igdbId),
      .title: describe(string, FieldDocs.Game.title),
      .summary: describe(string, FieldDocs.Game.summary),
      .developer: describe(string, FieldDocs.Game.developer),
      .publisher: describe(string, FieldDocs.Game.publisher),
      .posterUrl: describe(string, FieldDocs.Game.posterUrl),
      .bannerUrl: describe(string, FieldDocs.Game.bannerUrl),
      .siteUrl: describe(string, FieldDocs.Game.siteUrl),
      .releaseDate: describe(string, FieldDocs.Game.releaseDate),
      .releaseYear: describe(integer, FieldDocs.Game.releaseYear),
      .platforms: describe(array(string), FieldDocs.Game.platforms),
      .ownedPlatform: describe(string, FieldDocs.Game.ownedPlatform),
      .additionalPlatforms: describe(array(string), FieldDocs.Game.additionalPlatforms),
      .status: describe(string, FieldDocs.Game.status),
      .state: describe(states, FieldDocs.Game.state),
      .gameState: describe(integer, FieldDocs.Game.gameState),
      .completionState: describe(integer, FieldDocs.Game.completionState),
      .completion: describe(integer, FieldDocs.Game.completion),
      .priority: describe(integer, FieldDocs.Game.priority),
      .format: describe(integer, FieldDocs.Game.format),
      .userRating: describe(integer, FieldDocs.Game.userRating),
      .criticRating: describe(integer, FieldDocs.Game.criticRating),
      .hoursPlayed: describe(number, FieldDocs.Game.hoursPlayed),
      .additionalPlaytime: describe(number, FieldDocs.Game.additionalPlaytime),
      .startDate: describe(string, FieldDocs.Game.startDate),
      .finishDate: describe(string, FieldDocs.Game.finishDate),
      .addedDate: describe(string, FieldDocs.Game.addedDate),
      .updatedAt: describe(string, FieldDocs.Game.updatedAt),
      .notes: describe(string, FieldDocs.Game.notes),
      .review: describe(string, FieldDocs.Game.review),
      .reviewSpoilers: describe(boolean, FieldDocs.Game.reviewSpoilers),
      .timeToBeatStory: describe(number, FieldDocs.Game.timeToBeatStory),
      .timeToBeatExtras: describe(number, FieldDocs.Game.timeToBeatExtras),
      .timeToBeatComplete: describe(number, FieldDocs.Game.timeToBeatComplete),
      .timeToBeatType: describe(integer, FieldDocs.Game.timeToBeatType),
      .steamDeckStatus: describe(integer, FieldDocs.Game.steamDeckStatus),
      .genres: describe(array(gameGenre), FieldDocs.Game.genres),
      .userRatingValue: describe(number, FieldDocs.Game.userRatingValue),
      .completionMode: describe(integer, FieldDocs.Game.completionMode),
      .steamId: describe(string, FieldDocs.Game.steamId),
      .xboxId: describe(string, FieldDocs.Game.xboxId),
      .playStationId: describe(string, FieldDocs.Game.playStationId),
      .tags: describe(array(string), FieldDocs.Game.tags),
      .playthroughs: describe(array(playthrough), FieldDocs.Game.playthroughs),
    ],
    required: [
      .id, .igdbId, .title, .platforms, .additionalPlatforms, .reviewSpoilers, .genres, .tags,
      .playthroughs,
    ])
  let smartFilter = schema(
    SmartFilterRecord.CodingKeys.self,
    [
      .type: describe(string, FieldDocs.SmartFilter.type),
      .selectedOptions: describe(array(string), FieldDocs.SmartFilter.selectedOptions),
      .selectedRating: describe(integer, FieldDocs.SmartFilter.selectedRating),
      .selectedProgress: describe(integer, FieldDocs.SmartFilter.selectedProgress),
      .selectedFromDate: describe(string, FieldDocs.SmartFilter.selectedFromDate),
      .selectedToDate: describe(string, FieldDocs.SmartFilter.selectedToDate),
      .filterOption: describe(string, FieldDocs.SmartFilter.filterOption),
    ], required: [.selectedOptions])
  let listEntry = schema(
    ListEntryRecord.CodingKeys.self,
    [
      .gameId: describe(string, FieldDocs.ListEntry.gameId),
      .position: describe(integer, FieldDocs.ListEntry.position),
      .section: describe(string, FieldDocs.ListEntry.section),
    ], required: [.gameId])
  let list = schema(
    ListRecord.CodingKeys.self,
    [
      .id: describe(string, FieldDocs.List.id),
      .listId: describe(integer, FieldDocs.List.listId),
      .name: describe(string, FieldDocs.List.name),
      .description: describe(string, FieldDocs.List.description),
      .type: describe(string, FieldDocs.List.type),
      .tintColour: describe(string, FieldDocs.List.tintColour),
      .iconName: describe(string, FieldDocs.List.iconName),
      .ranked: describe(boolean, FieldDocs.List.ranked),
      .calendar: describe(boolean, FieldDocs.List.calendar),
      .position: describe(integer, FieldDocs.List.position),
      .sortType: describe(string, FieldDocs.List.sortType),
      .sortDirection: describe(string, FieldDocs.List.sortDirection),
      .groupType: describe(string, FieldDocs.List.groupType),
      .groupSortDirection: describe(string, FieldDocs.List.groupSortDirection),
      .smartFilterMatching: describe(integer, FieldDocs.List.smartFilterMatching),
      .smart: describe(boolean, FieldDocs.List.smart),
      .smartFilters: describe(array(smartFilter), FieldDocs.List.smartFilters),
      .games: describe(
        array(listEntry),
        "The games of a manual list in position order. Omitted for a smart list: GameTrack computes those from the rules and stores none."
      ),
    ], required: [.id, .name, .ranked, .calendar, .smart, .smartFilters])
  let stateSummary = schema(
    StateSummary.CodingKeys.self,
    [
      .state: describe(states, FieldDocs.Summary.state),
      .games: describe(integer, FieldDocs.Summary.stateGames),
      .hoursPlayed: describe(number, FieldDocs.Summary.stateHoursPlayed),
    ], required: [.state, .games, .hoursPlayed])

  let gameSearch = schema(
    GameSearchArguments.CodingKeys.self,
    [
      .filter: describe(
        schema(
          GameSearchArguments.Filter.CodingKeys.self,
          [
            .query: describe(string, FieldDocs.GameFilter.query),
            .states: describe(array(states), FieldDocs.GameFilter.states),
            .platforms: describe(array(string), FieldDocs.GameFilter.platforms),
            .tags: describe(array(string), FieldDocs.GameFilter.tags),
            .excludeTags: describe(array(string), FieldDocs.GameFilter.excludeTags),
            .genres: describe(array(string), FieldDocs.GameFilter.genres),
            .rated: describe(boolean, FieldDocs.GameFilter.rated),
            .releasedFrom: describe(string, FieldDocs.GameFilter.releasedFrom),
            .releasedBefore: describe(string, FieldDocs.GameFilter.releasedBefore),
            .addedFrom: describe(string, FieldDocs.GameFilter.addedFrom),
            .addedBefore: describe(string, FieldDocs.GameFilter.addedBefore),
            .finishedFrom: describe(string, FieldDocs.GameFilter.finishedFrom),
            .finishedBefore: describe(string, FieldDocs.GameFilter.finishedBefore),
          ]), "Criteria to match; they intersect."),
      .orderBy: schema(
        GameSearchArguments.Order.CodingKeys.self,
        [
          .field: describe(
            enumeration(GameSortField.allCases.map(\.rawValue)), FieldDocs.GameOrder.field),
          .direction: describe(
            enumeration(SortDirection.allCases.map(\.rawValue)), FieldDocs.GameOrder.direction),
        ], required: [.field]),
      .limit: limit, .cursor: cursor,
    ])
  let annotations = Tool.Annotations(
    readOnlyHint: true, destructiveHint: false, idempotentHint: true, openWorldHint: false)
  let noArguments = object([:])
  return [
    Tool(
      name: ToolName.gamesSearch.rawValue,
      description:
        "Read games in GameTrack, wishlist included, by title unless orderBy says otherwise. Use states [\"WANTED\"] for the wishlist. Filters intersect; empty arrays match nothing. Cursor is the next page offset; keep the criteria and limit unchanged across pages.",
      inputSchema: gameSearch, annotations: annotations,
      outputSchema: schema(
        PageOutput<GameRecord>.CodingKeys.self,
        [
          .items: describe(array(game), FieldDocs.GamePage.items),
          .totalCount: describe(integer, FieldDocs.GamePage.totalCount),
          .nextCursor: describe(string, "Cursor for the next page; omitted on the last page."),
        ], required: [.items, .totalCount])),
    Tool(
      name: ToolName.gamesGet.rawValue,
      description:
        "Read one game by its GameTrack UUID or its IGDB ID, giving exactly one; returns null when absent.",
      inputSchema: schema(
        GameArguments.CodingKeys.self,
        [
          .id: describe(string, FieldDocs.Game.id),
          .igdbId: describe(integer, FieldDocs.Game.igdbId),
        ]),
      annotations: annotations,
      outputSchema: schema(
        GameOutput.CodingKeys.self,
        [.game: describe(nullable(game), "The game, or null when absent.")], required: [.game])),
    Tool(
      name: ToolName.listsList.rawValue,
      description:
        "Read every list, by name, with its rules. A smart list has rules and no stored games: GameTrack computes them. games_search can reproduce status, tag, and release date rules with states, tags, excludeTags, and releasedBefore.",
      inputSchema: noArguments, annotations: annotations,
      outputSchema: schema(
        ListsOutput.CodingKeys.self, [.lists: describe(array(list), "Every list.")],
        required: [.lists])),
    Tool(
      name: ToolName.listsGet.rawValue,
      description: "Read one list by its UUID; returns null when absent.",
      inputSchema: schema(
        IDArguments.CodingKeys.self, [.id: describe(string, FieldDocs.List.id)], required: [.id]),
      annotations: annotations,
      outputSchema: schema(
        ListOutput.CodingKeys.self,
        [.list: describe(nullable(list), "The list, or null when absent.")], required: [.list])),
    Tool(
      name: ToolName.tagsList.rawValue,
      description: "Read every tag, by title, with the number of games carrying it.",
      inputSchema: noArguments, annotations: annotations,
      outputSchema: schema(
        TagsOutput.CodingKeys.self, [.tags: describe(array(tag), "Every tag.")],
        required: [.tags])),
    Tool(
      name: ToolName.genresList.rawValue,
      description: "Read every genre GameTrack knows, by ID, with the number of games in it.",
      inputSchema: noArguments, annotations: annotations,
      outputSchema: schema(
        GenresOutput.CodingKeys.self, [.genres: describe(array(genre), "Every genre.")],
        required: [.genres])),
    Tool(
      name: ToolName.librarySummary.rawValue,
      description:
        "Count the games in GameTrack by state, with hours played. The library is every game not on the wishlist.",
      inputSchema: noArguments, annotations: annotations,
      outputSchema: schema(
        LibrarySummary.CodingKeys.self,
        [
          .games: describe(integer, FieldDocs.Summary.games),
          .libraryGames: describe(integer, FieldDocs.Summary.libraryGames),
          .wishlistGames: describe(integer, FieldDocs.Summary.wishlistGames),
          .ratedGames: describe(integer, FieldDocs.Summary.ratedGames),
          .hoursPlayed: describe(number, FieldDocs.Summary.hoursPlayed),
          .states: describe(array(stateSummary), FieldDocs.Summary.states),
          .lists: describe(integer, FieldDocs.Summary.lists),
          .tags: describe(integer, FieldDocs.Summary.tags),
          .genres: describe(integer, FieldDocs.Summary.genres),
          .modified: describe(string, FieldDocs.Summary.modified),
        ],
        required: [
          .games, .libraryGames, .wishlistGames, .ratedGames, .hoursPlayed, .states, .lists,
          .tags, .genres, .modified,
        ])),
  ]
}
// MCP inputs omit optional values; an explicit null anywhere is invalid.
private func rejectNulls(_ value: Value) throws {
  switch value {
  case .null: throw ServerError.invalidArgument("Omit optional MCP inputs instead of sending null")
  case .object(let object): for value in object.values { try rejectNulls(value) }
  case .array(let array): for value in array { try rejectNulls(value) }
  default: break
  }
}
private func result<T: Encodable>(_ value: T) throws -> CallTool.Result {
  let bytes = try JSONEncoder().encode(value)
  return try .init(
    content: [.text(text: String(decoding: bytes, as: UTF8.self), annotations: nil, _meta: nil)],
    structuredContent: try JSONDecoder().decode(Value.self, from: bytes), isError: false)
}
// Tool names are the MCP contract; the catalog and dispatch both use these cases.
enum ToolName: String {
  case gamesGet = "games_get"
  case gamesSearch = "games_search"
  case genresList = "genres_list"
  case librarySummary = "library_summary"
  case listsGet = "lists_get"
  case listsList = "lists_list"
  case tagsList = "tags_list"
}
private func callTool(_ tool: ToolName, _ params: CallTool.Parameters) async throws
  -> CallTool.Result
{
  let args = params.arguments ?? [:]
  try rejectNulls(.object(args))
  func arguments<T: Decodable>(_ type: T.Type) throws -> T { try decodeInput(type, from: args) }
  func noArguments() throws {
    guard args.isEmpty else { throw ServerError.invalidArgument("Unknown input field") }
  }
  // The page at the cursor offset; nextCursor is the following page's offset, and the
  // client keeps the criteria unchanged.
  func page<Item: Encodable>(
    _ items: [Item], limit: Int?, cursor: String?
  ) throws -> PageOutput<Item> {
    let limit = limit ?? 50
    guard (1...100).contains(limit) else {
      throw ServerError.invalidArgument("limit must be 1...100")
    }
    let offset =
      try cursor.map { token in
        guard let value = Int(token), value >= 0 else {
          throw ServerError.invalidArgument(
            "cursor must be a nextCursor string from the previous response. Omit cursor for the first page."
          )
        }
        return value
      } ?? 0
    let pageItems = Array(items.dropFirst(offset).prefix(limit))
    let end = offset + pageItems.count
    return PageOutput(
      items: pageItems, totalCount: items.count, nextCursor: end < items.count ? String(end) : nil)
  }
  switch tool {
  case .gamesSearch:
    let request = try arguments(GameSearchArguments.self)
    // Check paging before the read, so a bad limit or cursor does not cost one.
    _ = try page([Int](), limit: request.limit, cursor: request.cursor)
    return try result(
      page(
        request.search.games(await currentLibrary()), limit: request.limit,
        cursor: request.cursor))
  case .gamesGet:
    let request = try arguments(GameArguments.self)
    let data = try await currentLibrary()
    return try result(
      GameOutput(game: request.id.map(data.game(id:)) ?? request.igdbId.flatMap(data.game(igdbId:)))
    )
  case .listsList:
    try noArguments()
    return try result(ListsOutput(lists: await currentLibrary().lists))
  case .listsGet:
    let id = try arguments(IDArguments.self).id
    return try result(ListOutput(list: await currentLibrary().list(id: id)))
  case .tagsList:
    try noArguments()
    return try result(TagsOutput(tags: await currentLibrary().tags))
  case .genresList:
    try noArguments()
    return try result(GenresOutput(genres: await currentLibrary().genres))
  case .librarySummary:
    try noArguments()
    return try result(LibrarySummary(await currentLibrary()))
  }
}
private let tools = toolsCatalog()
// A tool without readOnlyHint requires write access.
private let readOnlyTools = Set(tools.filter { $0.annotations.readOnlyHint == true }.map(\.name))

func mcpToolsJSON() throws -> String {
  let encoder = JSONEncoder()
  encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
  return String(decoding: try encoder.encode(ListTools.Result(tools: tools)), as: UTF8.self)
}

// Tool errors are JSON like successful results, with the code clients act on.
private struct ToolError: Encodable {
  struct Body: Encodable {
    let code: ErrorCode
    let message: String
  }
  let error: Body
}
private func errorText(_ error: Error) -> String {
  let server = error as? ServerError
  let payload = ToolError(
    error: .init(
      code: server?.code ?? .internalError, message: server?.message ?? String(describing: error)))
  // Sorted keys put code before message; JSONEncoder does not keep declaration order.
  let encoder = JSONEncoder()
  encoder.outputFormatting = .sortedKeys
  // A code and a message are plain strings, which always encode.
  return String(decoding: try! encoder.encode(payload), as: UTF8.self)
}

// The JSON-RPC method of a request body, for logging.
private func jsonRPCMethod(_ body: Data) -> String {
  switch try? JSONDecoder().decode(RPCEnvelope.self, from: body) {
  case .message(let method?, _): method
  case .batch: "batch"
  default: "unknown"
  }
}
// The JSON-RPC envelope fields the server logs; params and results stay undecoded.
private enum RPCEnvelope: Decodable {
  case message(method: String?, hasError: Bool)
  case batch
  enum CodingKeys: String, CodingKey { case method, error }
  init(from decoder: Decoder) throws {
    guard let c = try? decoder.container(keyedBy: CodingKeys.self) else {
      _ = try decoder.unkeyedContainer()
      self = .batch
      return
    }
    self = .message(
      method: try? c.decode(String.self, forKey: .method), hasError: c.contains(.error))
  }
}

// Records the tool outcome so the logger need not reparse large result bodies.
private final class ToolOutcome: @unchecked Sendable {
  var ran = false
  var failed = false
}
@Sendable func handleMCP(
  method: HTTPMethod, headers: [String: String], body: Data,
  access: Capabilities.Access
) async throws -> ServiceResponse {
  let outcome = ToolOutcome()
  // Each HTTP request has isolated SDK protocol state, permitting independent clients.
  // The HTTP listener enforces Origin policy for all endpoints.
  let transport = StatelessHTTPServerTransport(
    validationPipeline: StandardValidationPipeline(validators: [
      AcceptHeaderValidator(mode: .jsonOnly),
      ContentTypeValidator(),
      ProtocolVersionValidator(),
    ]))
  let server = Server(
    name: "gametrack-server", version: "0.1.1",
    capabilities: .init(tools: .init(listChanged: false)))
  await server.withMethodHandler(ListTools.self) { params in
    guard params.cursor == nil else { throw MCPError.invalidParams("Tool catalog has no cursor") }
    outcome.ran = true
    return .init(tools: tools)
  }
  await server.withMethodHandler(CallTool.self) { params in
    guard let tool = ToolName(rawValue: params.name) else {
      throw MCPError.invalidParams("Unknown tool")
    }
    outcome.ran = true
    guard access == .write || (access == .read && readOnlyTools.contains(params.name)) else {
      outcome.failed = true
      return .init(
        content: [
          .text(text: "Forbidden: MCP write access required", annotations: nil, _meta: nil)
        ], isError: true)
    }
    do { return try await callTool(tool, params) } catch {
      outcome.failed = true
      return .init(
        content: [.text(text: errorText(error), annotations: nil, _meta: nil)], isError: true)
    }
  }
  do { try await server.start(transport: transport) } catch {
    await server.stop()
    throw error
  }
  let response = await transport.handleRequest(
    .init(method: method.rawValue, headers: headers, body: body, path: Route.mcp.rawValue))
  await server.stop()
  let responseBody = response.bodyData ?? Data()
  var failure: Failure? = outcome.failed ? .mcpTool : nil
  // Protocol replies (no tool or catalog handler ran) report errors in the JSON-RPC body.
  if !outcome.ran,
    case .message(_, hasError: true)? = try? JSONDecoder().decode(
      RPCEnvelope.self, from: responseBody)
  {
    failure = .mcpProtocol
  }
  var headers = HTTPHeaders(response.headers.map { ($0.key, $0.value) })
  if !headers.contains(name: "Content-Type") {
    headers.add(name: "Content-Type", value: "application/json")
  }
  return ServiceResponse(
    status: .init(statusCode: response.statusCode), headers: headers, body: responseBody,
    failure: failure,
    logMetadata: method == .POST ? ["rpc": jsonRPCMethod(body)] : [:])
}
