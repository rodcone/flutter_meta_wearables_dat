import Foundation

var lines: [String] = []
let disabled = InvestigationTraceSink(enabled: false, emit: { lines.append($0) })
precondition(!disabled.initialize())
precondition(!disabled.record("{}"))
precondition(lines.isEmpty)

let sink = InvestigationTraceSink(enabled: true, emit: { lines.append($0) })
let payload = "{\"event\":\"traceStarted\",\"seq\":1,\"runId\":\"dart-run\",\"elapsedUs\":10,\"wallTimeUs\":20}"
precondition(!sink.record(payload))
precondition(sink.initialize())
precondition(sink.initialize())
precondition(lines.count == 1)
precondition(!sink.record("{}"))
precondition(!sink.record("[]"))
precondition(!sink.record(String(repeating: "x", count: 16_385)))
precondition(sink.record(payload))
let json = lines[1].components(separatedBy: "] ")[1].data(using: .utf8)!
let entry = try! JSONSerialization.jsonObject(with: json) as! [String: Any]
precondition(entry["runId"] as? String == "dart-run")
precondition(entry["seq"] as? Int == 1)
precondition(entry["elapsedUs"] as? Int == 10)
precondition(entry["wallTimeUs"] as? Int == 20)
precondition(entry["nativeReceiptUptimeUs"] as! Int > 0)
precondition(entry["bridgeRunId"] is String)
for _ in 0..<2000 { precondition(sink.record(payload)) }
precondition(!sink.record(payload))
precondition(lines.count == 2002) // bridge marker + bounded forwarded records
print("Investigation sink: opt-out, handshake, validation, timestamps and cap passed")
