import Foundation

/// Opt-in release-device investigation. No timers, files, payload bytes or public API.
/// Launch with MWDAT_INVESTIGATION=1; collect tagged OS logs over USB.
enum StreamInvestigationTrace {
  static let enabled = ProcessInfo.processInfo.environment["MWDAT_INVESTIGATION"] == "1"
  private static let lock = NSLock()
  private static var sequence = 0
  private static let runId = UUID().uuidString

  static func record(_ event: String, _ fields: @autoclosure () -> [String: Any] = [:]) {
    guard enabled else { return }
    // Snapshots may acquire tracker locks. Never evaluate them under the trace
    // lock: an SDK callback can already hold a tracker lock when tracing arrival.
    let capturedFields = fields()
    lock.lock()
    defer { lock.unlock() }
    // One final marker makes truncation explicit. No unbounded logging.
    guard sequence <= 2_000 else { return }
    let limited = sequence == 2_000
    sequence += 1
    var entry = limited ? [:] : capturedFields
    entry["event"] = limited ? "traceLimitReached" : event
    entry["seq"] = sequence
    entry["runId"] = runId
    entry["uptimeUs"] = Int(ProcessInfo.processInfo.systemUptime * 1_000_000)
    entry["wallTimeUs"] = Int(Date().timeIntervalSince1970 * 1_000_000)
    guard let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
          let json = String(data: data, encoding: .utf8) else { return }
    NSLog("[MWDAT-TRACE] %@", json)
  }
}
