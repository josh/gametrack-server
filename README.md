# gametrack-server

A Swift HTTP server for reading the games in [GameTrack](https://gametrack.app) on
macOS through GraphQL and MCP, with Prometheus metrics for library counts. It reads
GameTrack's database directly and never writes to it.

| Endpoint        | Documentation                                                |
| --------------- | ------------------------------------------------------------ |
| `POST /graphql` | [GraphQL](docs/GRAPHQL.md), [schema](docs/gametrack.graphql) |
| `POST /mcp`     | [MCP](docs/MCP.md), [tool catalog](docs/mcp-tools.json)      |
| `GET /metrics`  | [Metrics](docs/METRICS.md), [example](docs/metrics.prom)     |

## Running

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.github.josh.gametrack-server</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/bin/gametrack-server</string>
  </array>
  <key>Sockets</key>
  <dict>
    <key>Listeners</key>
    <dict>
      <key>SockPathName</key>
      <string>/Users/you/Library/Application Support/gametrack-server/server.sock</string>
      <key>SockPathMode</key>
      <integer>384</integer>
    </dict>
  </dict>
</dict>
</plist>
```

See [Server](docs/SERVER.md) for setup, the macOS grant it needs, sockets, and
configuration.
