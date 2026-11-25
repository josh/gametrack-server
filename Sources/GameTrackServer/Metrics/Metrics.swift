import Foundation

import struct os.OSAllocatedUnfairLock

private let processStart = Date()
private struct RequestKey: Hashable { let route: String, code: Int }
private let requestCounts = OSAllocatedUnfairLock<[RequestKey: Int]>(initialState: [:])

func recordRequest(route: String, code: Int) {
  requestCounts.withLock { $0[RequestKey(route: route, code: code), default: 0] += 1 }
}

// Prometheus metric types the exposition uses.
enum MetricType: String { case counter, gauge }
private func familyHeader(_ name: String, _ type: MetricType, _ help: String) -> [String] {
  ["# HELP \(name) \(help)", "# TYPE \(name) \(type.rawValue)"]
}

// Served even when the game gauges are not: a failed database read must not blank the
// request and liveness series that explain it.
func runtimeMetrics(databaseUp: Bool) -> String {
  var lines: [String] = []
  lines += familyHeader(
    "process_start_time_seconds", .gauge,
    "Start time of the process since the Unix epoch; a change is a restart.")
  lines.append("process_start_time_seconds \(Int(processStart.timeIntervalSince1970))")
  lines += familyHeader(
    "gametrack_http_requests_total", .counter,
    "HTTP requests answered, by route and status code.")
  let counts = requestCounts.withLock { $0 }
  for (key, count) in counts.sorted(by: {
    ($0.key.route, $0.key.code) < ($1.key.route, $1.key.code)
  }) {
    lines.append(
      "gametrack_http_requests_total{route=\"\(metricEscape(key.route))\",code=\"\(key.code)\"} \(count)"
    )
  }
  lines += familyHeader(
    "gametrack_main_actor_heartbeat_age_seconds", .gauge,
    "Seconds since the main actor last ran a watchdog heartbeat; the process exits past \(mainActorWatchdogLimit.components.seconds)."
  )
  lines.append(
    "gametrack_main_actor_heartbeat_age_seconds \(mainActorHeartbeatAge() / .seconds(1))")
  lines += familyHeader(
    "gametrack_database_up", .gauge,
    "1 when the last background read of GameTrack's database succeeded and its gauges follow; 0 also while Full Disk Access is missing."
  )
  lines.append("gametrack_database_up \(databaseUp ? 1 : 0)")
  return lines.joined(separator: "\n") + "\n"
}

func metricEscape(_ text: String) -> String {
  text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\n", with: "\\n")
    .replacingOccurrences(of: "\"", with: "\\\"")
}
actor MetricsCollector {
  private(set) var exposition: String?

  func run(interval: Duration) async {
    var failed = false
    var delay = interval
    while !Task.isCancelled {
      do {
        exposition = try await collectMetrics()
        if failed { serverLogger.info("Metrics collection recovered") }
        failed = false
        delay = interval
      } catch {
        logFailure("Metrics collection failed", error: error)
        exposition = nil
        // Retry after a minute, doubling toward the interval so a lasting failure stays quiet.
        delay = failed ? min(delay * 2, interval) : min(.seconds(60), interval)
        failed = true
      }
      do { try await Task.sleep(for: delay) } catch { return }
    }
  }
}

private struct CountKey: Hashable {
  let year: Int
  let platform: String
}

// Game gauges. gametrack_game_count and gametrack_game_rating keep the names, labels,
// and values the gametrack-data exporter wrote, so existing dashboards read on.
func collectMetrics() async throws -> String {
  let now = Date()
  let data = try await currentLibrary()
  var lines: [String] = []
  func family(_ name: String, _ help: String) { lines += familyHeader(name, .gauge, help) }
  family(
    "gametrack_observation_timestamp_seconds",
    "When the game gauges were read, since the Unix epoch.")
  lines.append("gametrack_observation_timestamp_seconds \(Int(now.timeIntervalSince1970))")
  family(
    "gametrack_database_modified_timestamp_seconds",
    "When GameTrack last wrote its database on this Mac, since the Unix epoch; it stops advancing when GameTrack stops syncing."
  )
  lines.append(
    "gametrack_database_modified_timestamp_seconds \(Int(data.modified.timeIntervalSince1970))")

  // A game is counted under the year GameTrack stores, else its release date's year in
  // UTC, else 0. 3000 is GameTrack's year for a date still to be announced.
  var counts: [CountKey: [GameState: Int]] = [:]
  var ratings: [Int: [Int: Int]] = [:]
  var unknownState = 0
  for game in data.games {
    let year = game.effectiveReleaseYear ?? 0
    ratings[year, default: [:]][game.userRating ?? 0, default: 0] += 1
    guard let state = game.state else {
      unknownState += 1
      continue
    }
    counts[CountKey(year: year, platform: game.ownedPlatform ?? ""), default: [:]][
      state, default: 0] += 1
  }
  family(
    "gametrack_game_count",
    "Games by release year, owned platform, and status, wishlist included. Every status is emitted for each year and platform that has a game."
  )
  for key in counts.keys.sorted(by: { ($0.year, $0.platform) < ($1.year, $1.platform) }) {
    for state in GameState.allCases {
      lines.append(
        "gametrack_game_count{year=\"\(key.year)\",platform=\"\(metricEscape(key.platform))\",status=\"\(state.label)\"} \(counts[key]?[state] ?? 0)"
      )
    }
  }
  family(
    "gametrack_game_rating",
    "Games by release year and the user's rating from 1 through 10; unrated games are not counted."
  )
  for year in ratings.keys.sorted() {
    for rating in 1...10 {
      lines.append(
        "gametrack_game_rating{year=\"\(year)\",rating=\"\(rating)\"} \(ratings[year]?[rating] ?? 0)"
      )
    }
  }
  family(
    "gametrack_games_unknown_state",
    "Games whose stored state this server does not know, which gametrack_game_count leaves out.")
  lines.append("gametrack_games_unknown_state \(unknownState)")
  return lines.joined(separator: "\n") + "\n"
}
