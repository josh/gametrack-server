# Server

Requires macOS 14+. Serves `POST /graphql`, `POST /mcp`, and `GET /metrics`.
`swift build -c release` produces `.build/release/gametrack-server`.

## Setup

launchd owns the sockets and starts the server on connection, including after
exit. Direct launch is refused. Use absolute executable/socket paths (`~` is not
expanded); Unix socket paths have a 104-byte limit. Adjust this LaunchAgent to
the installed binary and user, and create its socket directory:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.github.josh.gametrack-server</string>
  <key>ProgramArguments</key>
  <array><string>/usr/local/bin/gametrack-server</string></array>
  <key>Sockets</key><dict>
    <key>Listeners</key><dict>
      <key>SockPathName</key><string>/Users/you/Library/Application Support/gametrack-server/server.sock</string>
      <key>SockPathMode</key><integer>384</integer>
    </dict>
  </dict>
</dict></plist>
```

Save as `~/Library/LaunchAgents/com.github.josh.gametrack-server.plist`, then load:

```sh
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.github.josh.gametrack-server.plist
```

## Access to GameTrack's data

GameTrack is sandboxed and keeps its database in its own container:

```
~/Library/Containers/com.joekw.gametrack/Data/Library/Application Support/GameTrack/GameData.sqlite
```

macOS protects another app's container. Give the executable launchd runs **Full
Disk Access** in System Settings > Privacy & Security; when a wrapper starts the
server, the grant belongs to the wrapper. A rebuilt ad-hoc signed binary is a new
executable to macOS and loses the grant; sign with a stable identity to keep it.

Without the grant, `/graphql` and `/mcp` answer `NOT_AUTHORIZED` with a message
naming the setting, `gametrack_database_up` reports 0, and the health metrics stay
available. The process does not exit, because launchd would only start it again
into the same refusal; the metrics collector retries the read.

The server only reads. It opens the database read-only and never launches
GameTrack, so what it serves is what GameTrack last wrote on this Mac: keep
GameTrack running, or open it regularly, for iCloud changes from other devices to
arrive. See [Database](DATABASE.md).

## Sockets

At least one `Sockets` label is required; each may hold multiple sockets. Use
`SockPathName`/`SockPathMode` for Unix or `SockNodeName`/`SockServiceName` for TCP.
Only `TailscaleServe` checks grants; other labels grant fixed access. Excluded
endpoints or missing grants return 403.

| Label            | Access                                                             |
| ---------------- | ------------------------------------------------------------------ |
| `Listeners`      | All endpoints. Restrict who can connect.                           |
| `Metrics`        | `/metrics` only.                                                   |
| `GraphQL`        | `/graphql`.                                                        |
| `MCP`            | `/mcp`.                                                            |
| `TailscaleServe` | Checks `Tailscale-App-Capabilities` for the configured capability. |

For `TailscaleServe`, a Unix socket with `SockPathName` and `SockPathMode` 384 is
recommended:

```sh
tailscale serve --bg --https=443 --accept-app-caps=example.com/cap/gametrack unix:/path/to/tailscale-serve.sock
```

`tailscaled` must run as root or as the socket's owner to open it. The sandboxed
Mac App Store build cannot use Unix sockets; use `SockNodeName=127.0.0.1`,
`SockServiceName=8175`, and an `http://127.0.0.1:8175` target instead. Any local
process can reach a loopback port and forge the capability header.

Capability grants are a list of objects mapping `graphql`/`mcp` to `r` or `rw`,
and `metrics` to `r`, under the configured capability key:

```json
{
  "example.com/cap/gametrack": [{ "graphql": "r", "mcp": "rw", "metrics": "r" }]
}
```

Combine grants using the greatest access per endpoint; omitted endpoints get none.
Unknown API names/levels, `metrics: "rw"`, malformed headers, or headers over
16 KiB deny access. Accept plain JSON or RFC 2047 UTF-8 Q-encoded header values.
Only a trusted Tailscale Serve proxy may reach this socket: the header is its
assertion of identity and access, not a credential the server verifies independently.

No built-in authentication or TLS beyond socket access: keep direct sockets private
and use Tailscale Serve remotely.

## Configuration

Configuration comes only from the plist's `EnvironmentVariables`. Invalid values
prevent startup; other environment variables are ignored.

| Variable                             | Default              | Value                                                                        |
| ------------------------------------ | -------------------- | ---------------------------------------------------------------------------- |
| `GAMETRACK_TAILSCALE_APP_CAPABILITY` | None                 | `domain/path`; required for `TailscaleServe`.                                |
| `GAMETRACK_ALLOWED_ORIGINS`          | None                 | Space-separated `http(s)://host[:port]` origins.                             |
| `GAMETRACK_EXIT_WHEN_IDLE_SECONDS`   | Stay running         | 1–86400 seconds without open connections.                                    |
| `GAMETRACK_LOG_LEVEL`                | `info`               | Minimum: `trace`, `debug`, `info`, `notice`, `warning`, `error`, `critical`. |
| `GAMETRACK_METRICS_INTERVAL_SECONDS` | `3600`               | Delay after collection, 1–604800 seconds.                                    |
| `GAMETRACK_DATABASE_PATH`            | GameTrack's database | Absolute path of a `GameData.sqlite` to read instead, such as a copy.        |

## HTTP

HTTP/1.1 supports concurrent requests, keep-alive, and chunked bodies. JSON POSTs
require `Content-Type: application/json` (415 otherwise). Bodies over 1 MiB,
including chunked uploads, receive 413.

Host is not validated. An unlisted `Origin` receives 403; allowed origins receive
CORS headers and OPTIONS preflight support. Configured origins cannot contain
paths, queries, fragments, or credentials; default ports are removed.
Repeated `Origin`, `Content-Type`, or `Tailscale-App-Capabilities` headers return
400 rather than choosing a value.

## Deadlines and recovery

GraphQL/MCP handlers have a 60-second deadline after the body is collected.
Expiry cancels their task and returns 504 without waiting for it to finish.

An independent watchdog checks the main actor every 10 seconds and exits with
status 1 after more than 120 seconds without a heartbeat, so launchd restarts a
stuck process. Database reads run on their own queue and do not hold the actor.
Idle exit counts open connections, including keep-alive connections, rather than
time since the last request.

## Errors

| Code               | Meaning                                                                 |
| ------------------ | ----------------------------------------------------------------------- |
| `INVALID_ARGUMENT` | Invalid input.                                                          |
| `NOT_AUTHORIZED`   | Full Disk Access is missing; the message says how to allow it.          |
| `INTERNAL`         | Unexpected failure, including a database that is missing or unreadable. |

## Limits

This version is read-only: GameTrack has no scripting dictionary, and the server
does not yet drive its Shortcuts actions.

The in-scope tables are read as a whole and kept as a snapshot. Every request
compares the size and modification time of the database and its write-ahead log
with the snapshot's and reloads when either changed, so a read reflects GameTrack's
last write; an unchanged snapshot is still reloaded after five minutes.

Smart lists are reported with their rules but without their games, which GameTrack
computes and does not store. Linked store games, achievements, diary entries,
franchises, and releases are not served.
