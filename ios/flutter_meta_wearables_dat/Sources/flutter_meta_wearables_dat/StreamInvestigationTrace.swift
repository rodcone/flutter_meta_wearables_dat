import Foundation

/// Opt-in release-device investigation. No timers, files, payload bytes or public API.
/// Launch with --mwdat-investigation or MWDAT_INVESTIGATION=1.
enum StreamInvestigationTrace {
  static let enabled = ProcessInfo.processInfo.environment["MWDAT_INVESTIGATION"] == "1"
    || ProcessInfo.processInfo.arguments.contains("--mwdat-investigation")
  private static let lock = NSLock()
  private static var sequence = 0
  private static let runId = UUID().uuidString

  struct Span {
    let id: String
    let phase: String
    let parentId: String?
    let startedUs: Int
  }

  private static func uptimeUs() -> Int {
    Int(ProcessInfo.processInfo.systemUptime * 1_000_000)
  }

  static func begin(_ phase: String, parent: Span? = nil) -> Span? {
    guard enabled else { return nil }
    let id = UUID().uuidString
    record("cleanupPhaseBegin", [
      "spanId": id, "phase": phase, "parentSpanId": parent?.id as Any? ?? NSNull()
    ])
    // Exclude begin-record emission from the operation duration. End records
    // carry both boundaries so the gap after the begin record is also visible.
    return Span(id: id, phase: phase, parentId: parent?.id, startedUs: uptimeUs())
  }

  static func end(_ span: Span?, _ fields: @autoclosure () -> [String: Any] = [:]) {
    guard let span else { return }
    let endedUs = uptimeUs()
    var entry = fields()
    entry["spanId"] = span.id
    entry["phase"] = span.phase
    entry["parentSpanId"] = span.parentId as Any? ?? NSNull()
    entry["operationStartUptimeUs"] = span.startedUs
    entry["operationEndUptimeUs"] = endedUs
    entry["durationUs"] = endedUs - span.startedUs
    record("cleanupPhaseEnd", entry)
  }

  // Bound by UTF-8 bytes so unusual Unicode cannot exceed collector limits.
  static func boundedText(_ text: String, key: String) -> [String: Any] {
    var bytes = Array(text.utf8.prefix(1_024))
    while String(bytes: bytes, encoding: .utf8) == nil { bytes.removeLast() }
    return [key: String(decoding: bytes, as: UTF8.self),
            "\(key)Truncated": text.utf8.count > 1_024]
  }

  static func record(_ event: String, _ fields: @autoclosure () -> [String: Any] = [:]) {
    guard enabled else { return }
    let calledUs = uptimeUs()
    // Snapshots may acquire tracker locks. Never evaluate them under the trace
    // lock: an SDK callback can already hold a tracker lock when tracing arrival.
    let capturedFields = fields()
    let capturedUs = uptimeUs()
    lock.lock()
    defer { lock.unlock() }
    let acquiredUs = uptimeUs()
    // One final marker makes truncation explicit. No unbounded logging.
    guard sequence <= 2_000 else { return }
    let limited = sequence == 2_000
    sequence += 1
    var entry = limited ? [:] : capturedFields
    entry["event"] = limited ? "traceLimitReached" : event
    entry["seq"] = sequence
    entry["runId"] = runId
    entry["uptimeUs"] = acquiredUs
    entry["traceCallUptimeUs"] = calledUs
    entry["traceFieldsUs"] = capturedUs - calledUs
    entry["traceLockWaitUs"] = acquiredUs - capturedUs
    entry["wallTimeUs"] = Int(Date().timeIntervalSince1970 * 1_000_000)
    guard let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
          let json = String(data: data, encoding: .utf8) else { return }
    NSLog("[MWDAT-TRACE] %@", json)
  }
}
