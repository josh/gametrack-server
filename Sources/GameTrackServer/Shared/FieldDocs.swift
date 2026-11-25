// Field descriptions shared by the GraphQL schema and the MCP catalog.
enum FieldDocs {
  enum Game {
    static let id = "The game's UUID in GameTrack, in uppercase; it does not change over time."
    static let igdbId = "The game's ID at IGDB, where GameTrack takes its metadata from."
    static let title = "The title."
    static let summary = "The game's description."
    static let developer = "The developer."
    static let publisher = "The publisher."
    static let posterUrl = "URL of the cover image."
    static let bannerUrl = "URL of the banner image."
    static let siteUrl = "URL of the game's web page."
    static let releaseDate =
      "When the game is released. 4001-01-01 means the date is to be announced, and a date at the last second of a year in Pacific time means only the year is known."
    static let releaseYear =
      "The release year as stored: 0 for most games, which have only a release date, and 3000 when the date is to be announced."
    static let platforms = "Every platform the game is released on."
    static let ownedPlatform = "The platform the user has the game on."
    static let additionalPlatforms = "Other platforms the user also has the game on."
    static let status =
      "An older status label, kept as stored; GameTrack no longer updates it and it often disagrees with state."
    static let state =
      "Where the game stands: IN_PROGRESS, QUEUED, COLLECTION, COMPLETED, ABANDONED, or WANTED for the wishlist. Derived from gameState; absent for a value the server does not know."
    static let gameState =
      "The state as stored: 1 in progress, 2 queued, 3 collection, 4 completed, 5 abandoned, 6 wanted."
    static let completionState =
      "How far a completed game was taken, as stored: 0 when not completed, otherwise 1 through 3."
    static let completion = "Progress through the game, as a percentage from 0 through 100."
    static let priority = "The priority as stored; -1 on every game seen so far."
    static let format = "The format owned, as stored; 0 for most games."
    static let userRating = "The user's rating from 1 through 10; 0 when unrated."
    static let userRatingValue =
      "The user's rating as GameTrack exports it: the fractional rating when one is set, otherwise userRating."
    static let criticRating = "The critics' score out of 100; 0 or -1 when there is none."
    static let hoursPlayed = "Hours played."
    static let additionalPlaytime = "Additional play time in hours, as stored."
    static let startDate = "When the user started the game."
    static let finishDate = "When the user finished or abandoned the game."
    static let addedDate = "When the game was added to GameTrack."
    static let updatedAt = "When the game's entry last changed."
    static let notes = "The user's notes."
    static let review = "The user's review."
    static let reviewSpoilers = "Whether the review is marked as containing spoilers."
    static let timeToBeatStory = "Hours to finish the main story; 0 when unknown."
    static let timeToBeatExtras = "Hours to finish the story and extras; 0 when unknown."
    static let timeToBeatComplete = "Hours to complete everything; 0 when unknown."
    static let timeToBeatType = "The time-to-beat type as stored: 0 through 2."
    static let steamDeckStatus =
      "Steam Deck compatibility as stored: -1 when not checked, otherwise 0 through 3."
    static let completionMode = "The completion mode as stored."
    static let steamId = "ID of the linked Steam game."
    static let xboxId = "ID of the linked Xbox game."
    static let playStationId = "ID of the linked PlayStation game."
    static let genres = "The game's genres, ordered by genre ID."
    static let tags = "Titles of the tags on the game, in alphabetical order."
    static let playthroughs = "The game's playthroughs, oldest first."
  }
  enum Playthrough {
    static let id = "The playthrough's UUID in GameTrack."
    static let gameId = "UUID of the playthrough's game."
    static let dateStarted = "When the playthrough started."
    static let dateFinished = "When the playthrough ended."
    static let duration = "Days from start to finish."
    static let progress = "Progress as a percentage from 0 through 100; -1 when not set."
    static let state =
      "The playthrough's state as stored, with the meanings of a game's gameState; 0 for a game on the wishlist."
    static let completionState = "How far the playthrough was taken, as a game's completionState."
    static let platform = "The platform played on."
    static let playHours = "Hours played in this playthrough."
    static let lastPlayedAt = "When the game was last played in this playthrough."
    static let name = "The name the user gave the playthrough."
    static let rating = "The user's rating of this playthrough; 0 when unrated."
    static let tags = "Tags on the playthrough, as stored."
  }
  enum Genre {
    static let id = "The genre's ID at IGDB."
    static let name = "The name, with the emoji GameTrack shows before it."
    static let gameCount = "Number of games with this genre."
  }
  enum Tag {
    static let id = "The tag's UUID in the database. GameTrack identifies tags by title."
    static let title = "The tag's title, which identifies it."
    static let tintColour = "The tag's colour as stored: a base64 archive of a UIColor."
    static let gameCount = "Number of games with this tag."
  }
  enum List {
    static let id = "The list's UUID in GameTrack, in uppercase."
    static let listId = "The list's numeric ID in GameTrack."
    static let name = "The list's name."
    static let description = "The list's description."
    static let type = "The list type as stored."
    static let tintColour = "The list's colour as stored: a base64 archive of a UIColor."
    static let iconName = "Name of the list's icon."
    static let ranked = "Whether the list is ranked."
    static let calendar = "Whether the list is shown in the calendar."
    static let position = "The list's place among the lists."
    static let sortType = "What the list sorts by, as stored."
    static let sortDirection = "ascending or descending."
    static let groupType = "What the list groups by, as stored."
    static let groupSortDirection = "ascending or descending."
    static let smartFilterMatching = "How a smart list combines its rules, as stored."
    static let smart =
      "Whether the list is a smart list, whose games GameTrack computes from smartFilters."
    static let smartFilters = "The rules of a smart list; empty for a manual list."
    static let games =
      "The games of a manual list in position order. Null for a smart list: GameTrack computes those from the rules and stores none."
  }
  enum SmartFilter {
    static let type = "What the rule tests, such as status, tags, or releaseDate."
    static let selectedOptions = "The values the rule matches, such as status or tag names."
    static let selectedRating = "The rating the rule compares with."
    static let selectedProgress = "The progress the rule compares with."
    static let selectedFromDate = "The start of the rule's date range."
    static let selectedToDate = "The end of the rule's date range."
    static let filterOption = "How the rule applies, such as exclude or before."
  }
  enum ListEntry {
    static let gameId = "UUID of the game."
    static let position = "The game's index in the list."
    static let section = "The section of the list the game is in."
  }
  enum GameFilter {
    static let query = "Case-insensitive substring of the title, developer, or publisher."
    static let states = "Match any of these states; [] matches nothing."
    static let platforms =
      "Match games owned on any of these platforms, ignoring case; [] matches nothing."
    static let tags = "Match games with any of these tag titles, ignoring case; [] matches nothing."
    static let excludeTags =
      "Leave out games with any of these tag titles, ignoring case; [] leaves out nothing."
    static let genres =
      "Match games with any of these genres, by name with or without its emoji, ignoring case; [] matches nothing."
    static let rated = "true for games the user has rated, false for unrated ones."
    static let releasedFrom =
      "Released at or after this RFC 3339 timestamp, or YYYY-MM-DD for that day's start in the host time zone."
    static let releasedBefore = "Released before this timestamp or day."
    static let addedFrom = "Added to GameTrack at or after this timestamp or day."
    static let addedBefore = "Added to GameTrack before this timestamp or day."
    static let finishedFrom = "Finished at or after this timestamp or day."
    static let finishedBefore = "Finished before this timestamp or day."
  }
  enum GameOrder {
    static let field = "What to sort by. Games without the value sort last."
    static let direction =
      "ASC for smallest or earliest first, DESC for the reverse; defaults to ASC."
  }
  enum GamePage {
    static let items = "Games in this page."
    static let totalCount = "Number of games matching the filter."
  }
  enum Summary {
    static let games = "Every game in GameTrack, wishlist included."
    static let libraryGames =
      "Games that are not on the wishlist, which GameTrack shows as All Games."
    static let wishlistGames = "Games on the wishlist."
    static let ratedGames = "Games the user has rated."
    static let hoursPlayed = "Total hours played."
    static let states = "Counts for each state."
    static let state = "The state."
    static let stateGames = "Games in this state."
    static let stateHoursPlayed = "Hours played across games in this state."
    static let lists = "Number of lists."
    static let tags = "Number of tags."
    static let genres = "Number of genres."
    static let modified = "When GameTrack last wrote its database on this Mac."
  }
}
