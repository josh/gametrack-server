import Foundation
import Logging

var serverLogger = Logger(label: "gametrack-server") {
  StreamLogHandler.standardError(label: $0)
}

func logFailure(_ message: String, error: Error) {
  let native = error as NSError
  var metadata: Logger.Metadata = [
    "error_type": "\(type(of: error))",
    "error_domain": "\(native.domain)",
    "error_code": "\(native.code)",
  ]
  // The server's own code says which condition failed; the native code is always 1 for it.
  if let server = error as? ServerError { metadata["code"] = "\(server.code.rawValue)" }
  serverLogger.error("\(message)", metadata: metadata)
}
