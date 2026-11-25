# GraphQL

`POST /graphql`. The [schema](gametrack.graphql) documents types, fields, inputs, and
validation. Queries only: no mutations and no subscriptions.

```sh
curl --unix-socket /path/to/server.sock http://localhost/graphql \
  -H 'Content-Type: application/json' \
  --data '{"query":"{ games(limit: 10, filter: {states: [IN_PROGRESS]}) { totalCount items { id title ownedPlatform hoursPlayed } } }"}'
```

The endpoint follows [GraphQL over HTTP](https://http-spec.graphql.org/September2026/).
Responses use `application/graphql-response+json` when Accept allows it or is absent,
else `application/json` on 2xx; Accept without either returns 406.

Null `variables`/`operationName` mean absent. Request errors carry no `data`: a body
that is not JSON or a document that does not parse returns 400; a malformed envelope,
failed validation, an ambiguous operation, or variables that do not coerce return 422.
Other methods return 405 with `Allow: POST`. Execution errors use HTTP 200 with
`data` and `errors`; clients must inspect the body.

## Reads

Everything comes from GameTrack's database, read without launching GameTrack.
Within a request the database is read once, so every field and alias sees the same
moment.

`games` filters and sorts before pagination. `limit` is 1–100 (default 50),
`offset` is nonnegative, and an offset beyond the end returns an empty page with
the full matching count. Pages across requests have no shared snapshot. Filter
criteria intersect; an empty list matches nothing. Date bounds are RFC 3339
timestamps or `YYYY-MM-DD` days meaning midnight in the host zone; `From` is
inclusive and `Before` exclusive, and a game without the date matches no bound.

Games sort by title, ignoring case. Missing values sort last and ties use the
title, then the ID. `lists`, `tags`, and `genres` are short and returned whole.

`game` takes exactly one of `id`, the game's UUID in GameTrack, and `igdbId`.

## Games

`Game` carries what GameTrack stores, under the names of the columns in GameTrack's
own export, in camelCase. Values are not reinterpreted:

- `releaseYear` is 0 for most games, which have only a `releaseDate`, and 3000 when
  the date is still to be announced (`releaseDate` is then `4001-01-01`). A release
  date at the last second of a year in Pacific time means only the year is known.
- `userRating` is 0 when unrated, and `criticRating` is 0 or -1 when there is none.
- `status` is an older label GameTrack no longer updates. Use `state`.
- `completionState`, `format`, `timeToBeatType`, `steamDeckStatus`, and
  `completionMode` are the stored integers; see [Database](DATABASE.md#integers).

`state` is the one derived field: `gameState` 1–6 as `IN_PROGRESS`, `QUEUED`,
`COLLECTION`, `COMPLETED`, `ABANDONED`, `WANTED`. `WANTED` games are the wishlist;
GameTrack's "All Games" is every other state, which `summary.libraryGames` counts.

`genres` are ordered by genre ID and `tags` by title; GameTrack stores neither in
any order. `playthroughs` are oldest first.

The `platforms` filter matches `ownedPlatform`. The `genres` filter accepts a name
with or without its emoji.

## Lists

A list with `smartFilters` is a smart list: GameTrack computes its games from the
rules whenever it shows the list and stores none, so `games` is null. The rules are
reported as stored (`type`, `filterOption`, `selectedOptions`, dates, rating, and
progress). The `games` filter can reproduce status, tag, and release date rules
with `states`, `tags`, `excludeTags`, and `releasedBefore`; other rule types have
no equivalent. Status rule options are GameTrack's display names, such as
`Play Next`, not `GameState` values.

A manual list has `games`, each with its `position` and `section`.
