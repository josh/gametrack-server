# Agents

- Never write to GameTrack's database, and never open it any way but read-only. It mirrors to CloudKit; a foreign write corrupts its change history.
- `.snapshot/` holds a copy of a real database for development, with the user's notes and reviews. Never commit it, an official GameTrack export, or rows from either. Examples in docs use made-up games.
- Develop against the copy by setting `GAMETRACK_DATABASE_PATH` in a dev LaunchAgent; reading the real container needs Full Disk Access for the binary, and a rebuilt binary is ad-hoc signed and loses it.
- Table and column names move between GameTrack versions; resolve them at runtime as `Shared/LibraryStore.swift` does, and record what a new version changes in `docs/DATABASE.md`.
- API fields follow the columns of GameTrack's own export and carry stored values unreinterpreted. Check a change against an export taken at the same time as the snapshot.
- `gametrack_game_count` and `gametrack_game_rating` keep the names, labels, and values of the gametrack-data exporter this server replaced.
- Prefer existing dependencies. Do not add permanent unit/integration tests unless requested.

Regenerate the GraphQL schema and MCP tool catalog after changing either:

```sh
swift run gametrack-server --dump-graphql-schema >docs/gametrack.graphql
swift run gametrack-server --dump-mcp-tools >docs/mcp-tools.json
prettier --write docs/gametrack.graphql docs/mcp-tools.json
```
