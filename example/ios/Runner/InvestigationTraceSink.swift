import Foundation

/// Example-only, main-thread sink. No frame bytes, files or background tasks.
final class InvestigationTraceSink {
  private let enabled: Bool
  private let emit: (String) -> Void
  private let runId = UUID().uuidString
  private var initialized = false
  private var count = 0

  init(
    enabled: Bool = ProcessInfo.processInfo.environment["MWDAT_INVESTIGATION"] == "1"
      || ProcessInfo.processInfo.arguments.contains("--mwdat-investigation"),
    emit: @escaping (String) -> Void = { NSLog("%@", $0) }
  ) {
    self.enabled = enabled
    self.emit = emit
  }

  func initialize() -> Bool {
    guard enabled else { return false }
    if !initialized {
      initialized = true
      write("BRIDGE", ["event": "bridgeReady", "seq": 1, "runId": runId])
    }
    return true
  }

  func record(_ payload: String) -> Bool {
    guard enabled, initialized, count < 2_001, payload.utf8.count <= 16_384,
          let data = payload.data(using: .utf8),
          var entry = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          entry["event"] is String, entry["seq"] is Int,
          entry["runId"] is String, entry["elapsedUs"] is Int,
          entry["wallTimeUs"] is Int else { return false }
    count += 1
    entry["bridgeRunId"] = runId
    write("DART", entry)
    return true
  }

  private func write(_ source: String, _ fields: [String: Any]) {
    var entry = fields
    entry["nativeReceiptUptimeUs"] = Int(ProcessInfo.processInfo.systemUptime * 1_000_000)
    guard let data = try? JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys]),
          let json = String(data: data, encoding: .utf8) else { return }
    emit("[MWDAT-TRACE-\(source)] \(json)")
  }
}
