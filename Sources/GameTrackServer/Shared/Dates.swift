import Foundation

private let timestampStyle = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
// UTC with milliseconds, rounded to the nearest one as GameTrack's own export does; the
// format style would truncate instead.
func timestamp(_ date: Date) -> String {
  let milliseconds = (date.timeIntervalSince1970 * 1000).rounded()
  let seconds = (milliseconds / 1000).rounded(.down)
  let whole = Date(timeIntervalSince1970: seconds).formatted(Date.ISO8601FormatStyle())
  return whole.dropLast() + String(format: ".%03dZ", Int(milliseconds - seconds * 1000))
}
func parseTimestamp(_ value: String) throws -> Date {
  let pattern =
    #"^\d{4}-\d{2}-\d{2}T(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d(\.\d+)?(Z|[+-](?:[01]\d|2[0-3]):[0-5]\d)$"#
  guard value.range(of: pattern, options: .regularExpression) != nil else {
    throw ServerError.invalidArgument(
      "expected RFC 3339 timestamp with an explicit offset")
  }
  try validateDay(String(value.prefix(10)))
  // The style accepts any number of fraction digits, or none, as RFC 3339 allows.
  guard let date = try? timestampStyle.parse(value) else {
    throw ServerError.invalidArgument("invalid timestamp")
  }
  return date
}
func validateDay(_ value: String) throws {
  let parts = value.split(separator: "-").map { Int($0) }
  guard value.range(of: #"^\d{4}-\d{2}-\d{2}\z"#, options: .regularExpression) != nil,
    parts.count == 3, let year = parts[0], let month = parts[1], let day = parts[2],
    (1...9999).contains(year),
    DateComponents(year: year, month: month, day: day)
      .isValidDate(in: Calendar(identifier: .gregorian))
  else {
    throw ServerError.invalidArgument("calendar days must be valid Gregorian YYYY-MM-DD")
  }
}

// A day without a time means that day in the host zone.
private var hostCalendar: Calendar {
  var calendar = Calendar(identifier: .gregorian)
  calendar.timeZone = .current
  return calendar
}
// Midnight in the host zone at the start of a YYYY-MM-DD day.
func startOfLocalDay(_ day: String) throws -> Date {
  try validateDay(day)
  let parts = day.split(separator: "-").compactMap { Int($0) }
  guard
    let date = hostCalendar.date(
      from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
  else { throw ServerError.invalidArgument("calendar day does not resolve in the host zone") }
  return date
}
// A window bound: an RFC 3339 timestamp, or a calendar day meaning its host-zone midnight.
func parseBound(_ value: String) throws -> Date {
  value.contains("T") ? try parseTimestamp(value) : try startOfLocalDay(value)
}
