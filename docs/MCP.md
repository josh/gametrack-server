# MCP

`POST /mcp` accepts one JSON-RPC 2.0 message using protocol `2025-11-25`.
Supports `initialize`, `ping`, `tools/list`, `tools/call`, and accepted notifications
(HTTP 202). GET returns 405. Stateless: no session header, SSE stream, server
requests, or resumability.

Send `Content-Type: application/json`, `Accept: application/json, text/event-stream`,
and, after initialization, `MCP-Protocol-Version: 2025-11-25`.

```sh
curl --unix-socket /path/to/server.sock http://localhost/mcp \
  -H 'Content-Type: application/json' -H 'Accept: application/json, text/event-stream' \
  --data '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"example","version":"1"}}}'
```

`tools/list` returns current descriptions and input/output schemas; the
[catalog](mcp-tools.json) is an export. Every tool is read-only and carries
`readOnlyHint: true`, so an `r` grant is enough.

## Tools

| Tool              | Returns                                                          |
| ----------------- | ---------------------------------------------------------------- |
| `games_search`    | A page of games matching a filter, by title unless ordered.      |
| `games_get`       | One game by `id` or `igdbId`, or null.                           |
| `lists_list`      | Every list with its rules.                                       |
| `lists_get`       | One list by `id`, or null.                                       |
| `tags_list`       | Every tag with its game count.                                   |
| `genres_list`     | Every genre with its game count.                                 |
| `library_summary` | Counts and hours played by state, and when GameTrack last wrote. |

All of them read GameTrack's database and never launch GameTrack. Games carry the
same fields as the GraphQL `Game` type, with the same
[stored values](GRAPHQL.md#games); a game's `tags` are tag titles and its `genres`
are `{id, name}`. Use `states: ["WANTED"]` for the wishlist.

A smart list has rules and no `games`; see [lists](GRAPHQL.md#lists).

## Inputs and results

Reject unknown argument fields and explicit null anywhere in tool arguments,
including nested values; omit optional inputs instead. Pagination cursors are
decimal offsets, not snapshots: keep filters, ordering, and limit unchanged, and
expect concurrent changes to affect later pages.

Optional stored values are omitted when absent. A missing item is null in `*_get`
results.

Successful calls return `structuredContent` and matching JSON text. Tool failures
set `isError: true` and omit `structuredContent`. Application errors return JSON
text shaped as `{"error":{"code":"...","message":"..."}}`; permission denials
return plain text. See [error codes](SERVER.md#errors).
Unknown tools and protocol/dispatch failures use JSON-RPC errors instead of tool
results. A successful HTTP response alone does not establish tool success.
