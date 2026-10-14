import Foundation

if !StreamInvestigationTrace.enabled {
  func unexpectedFields() -> [String: Any] {
    fatalError("Disabled tracing must not evaluate fields")
  }
  precondition(StreamInvestigationTrace.begin("disabled") == nil)
  StreamInvestigationTrace.record("disabled", unexpectedFields())
  StreamInvestigationTrace.end(nil, unexpectedFields())
} else if CommandLine.arguments.contains("--limit") {
  for _ in 0..<2_050 { StreamInvestigationTrace.record("bounded") }
} else {
  let parent = StreamInvestigationTrace.begin("parent")
  DispatchQueue.concurrentPerform(iterations: 8) { _ in
    let child = StreamInvestigationTrace.begin("child", parent: parent)
    StreamInvestigationTrace.end(child)
  }
  StreamInvestigationTrace.end(parent)
  func slowFields() -> [String: Any] {
    Thread.sleep(forTimeInterval: 0.01)
    return ["fixture": true]
  }
  StreamInvestigationTrace.record("slowFields", slowFields())
}
