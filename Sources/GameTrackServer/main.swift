import Darwin
import Foundation
import Logging

let usage = """
  Usage: gametrack-server

  Serves /graphql, /mcp, and /metrics on the sockets launchd hands it. Start it from a
  LaunchAgent plist; run directly, it exits.

  Socket labels: \(SocketLabel.allCases.map(\.rawValue).joined(separator: ", "))
  Environment variables:
  \(ConfigVariable.allCases.map { "  \($0.rawValue)" }.joined(separator: "\n"))

  See https://github.com/josh/gametrack-server/blob/main/docs/SERVER.md
  """

// Reports a fatal error on stderr and exits.
func fail(_ error: Error) -> Never {
  FileHandle.standardError.write(Data("error: \(error)\n".utf8))
  exit(1)
}

// launchd starts the server and owns its sockets; GAMETRACK_* environment variables in the
// plist configure it. The only arguments are --help and the developer dumps of the API
// docs.
Task.detached {
  do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    if arguments == ["--help"] || arguments == ["-h"] {
      print(usage)
    } else if arguments == ["--dump-mcp-tools"] {
      print(try mcpToolsJSON())
    } else if arguments == ["--dump-graphql-schema"] {
      print(try graphQLSchemaSDL())
    } else if !arguments.isEmpty {
      throw ServerError.internalError(
        "Use --help; the server is configured by GAMETRACK_* variables in its launchd plist")
    } else {
      let config = try ServerConfig(environment: ProcessInfo.processInfo.environment)
      let sockets = try activateLaunchdSockets()
      if sockets.contains(where: { $0.label == .tailscaleServe }),
        config.tailscaleAppCapability == nil
      {
        throw ServerError.internalError(
          "The TailscaleServe socket requires \(ConfigVariable.tailscaleAppCapability.rawValue)")
      }
      serverLogger.logLevel = config.logLevel
      startMainActorWatchdog()
      configureLibrary(path: config.databasePath)
      try await serve(sockets: sockets, config: config)
    }

    exit(0)
  } catch {
    fail(error)
  }

}
// The main thread serves the main queue, which the main actor runs on.
dispatchMain()
