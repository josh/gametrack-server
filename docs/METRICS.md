# Metrics

`GET /metrics` serves health and cached game counts in Prometheus text format
0.0.4. [metrics.prom](metrics.prom) is a synthetic example of every metric, type,
label, and help text; see the [format specification](https://prometheus.io/docs/instrumenting/exposition_formats/).

## Counts

| Metric                  | Labels                       |
| ----------------------- | ---------------------------- |
| `gametrack_game_count`  | `year`, `platform`, `status` |
| `gametrack_game_rating` | `year`, `rating`             |

Both keep the names, labels, and values of the
[gametrack-data](https://github.com/josh/gametrack-data) exporter this server
replaces, so queries written against it keep working.

`gametrack_game_count` counts every game, wishlist included; sum it without
`status="Wanted"` for what GameTrack shows as "All Games".

- `status` is `In Progress`, `Queued`, `Collection`, `Completed`, `Abandoned`, or
  `Wanted`. The six partition the games, so they can be summed.
- `platform` is the platform the game is owned on, and empty when none is set.
- `year` is the release year GameTrack stores, else the year of the release date in
  UTC, else `0`. `3000` is GameTrack's year for a date still to be announced.

All six statuses are emitted for each `year` and `platform` pair that has a game,
zeros included, so a status that empties reads 0. A pair no game has is not
emitted; the old exporter emitted every combination of year, platform, and status.

`gametrack_game_rating` counts rated games by the user's rating, 1 through 10, for
every year that has a game, zeros included. Unrated games are not counted.

`gametrack_games_unknown_state` counts games whose stored state is not one of the
six, which `gametrack_game_count` leaves out; it is normally 0.

Labels exclude game titles and IDs.

## Freshness

`gametrack_database_modified_timestamp_seconds` is when GameTrack last wrote its
database on this Mac. The server serves only what GameTrack has written, so a value
that stops advancing while games change on other devices means GameTrack is not
running or not syncing here. `gametrack_observation_timestamp_seconds` is when the
counts were read.

## Refresh

Collect at startup, then wait `GAMETRACK_METRICS_INTERVAL_SECONDS` (default 3600)
after each collection. Scrapes and API requests do not trigger collection. Counts
remain available during refresh and may lag by the interval plus collection time.

Before the first success or after failure, omit the game gauges and report
`gametrack_database_up 0`; health metrics remain. Failures clear previous counts
and retry after min(60 seconds, interval), doubling up to the interval. The health
series cover the current process; restarts reset counters, and this collector keeps
no disk cache.
