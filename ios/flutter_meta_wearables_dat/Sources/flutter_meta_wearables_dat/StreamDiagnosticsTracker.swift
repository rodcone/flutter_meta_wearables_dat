import Foundation

// Independent of Flutter/DAT so the production timing policy can run in host tests.
// One instance per camera session. Old callbacks can only update their old instance.
final class StreamDiagnosticsTracker {
  // No submission deadline while backgrounded: the OS prevents texture work.
  static func deliveryStall(sinceArrival: Double, sinceSubmission: Double, background: Bool) -> String? {
    if sinceArrival > 1.5 { return "sdkFramesStopped" }
    if !background && sinceSubmission > 6 { return "textureSubmissionsStopped" }
    return nil
  }

  private let lock = NSLock()
  private let clock: () -> Double
  let sessionId = UUID().uuidString
  private let created: Double
  private var first: Double?
  private var last: Double?
  private var submitted: Double?
  private var receivedCount = 0
  private var submittedCount = 0
  private var stallReason: String?
  private var streaming = false
  private var elapsed = 0.0
  private var graceUntil = 0.0
  private var checkpoint: Double
  private var reportedFirst = false
  private var epochs = [Int](repeating: -1, count: 20)
  private var arrivals = [Int](repeating: 0, count: 20)
  private var pushes = [Int](repeating: 0, count: 20)

  init(clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }) {
    self.clock = clock
    created = clock()
    checkpoint = created
  }

  private func eligibleDelta(_ now: Double) -> Double {
    guard now - checkpoint <= 2 else { return 0 }
    return max(0, now - max(checkpoint, graceUntil))
  }

  private func advance(_ now: Double) {
    // A watchdog tick is normally 1s. Do not charge long process-suspension gaps.
    if streaming && first == nil { elapsed += eligibleDelta(now) }
    checkpoint = now
  }

  func stateChanged(streaming next: Bool) {
    lock.lock(); defer { lock.unlock() }
    advance(clock())
    streaming = next
  }

  func resumeGrace() {
    lock.lock(); defer { lock.unlock() }
    checkpoint = clock()
    graceUntil = checkpoint + 1.5
  }

  private func record(_ now: Double, arrival: Bool) {
    let epoch = Int(floor(now * 10))
    let index = epoch % 20
    if epochs[index] != epoch {
      epochs[index] = epoch; arrivals[index] = 0; pushes[index] = 0
    }
    if arrival { arrivals[index] += 1 } else { pushes[index] += 1 }
  }

  func setStallReason(_ reason: String) {
    lock.lock(); defer { lock.unlock() }; stallReason = reason
  }

  func noteArrival() {
    lock.lock(); defer { lock.unlock() }
    let now = clock()
    if first == nil { advance(now); first = now }
    if stallReason != "textureSubmissionsStopped" { stallReason = nil }
    last = now; receivedCount += 1
    record(now, arrival: true)
  }

  func noteSubmission() {
    lock.lock(); defer { lock.unlock() }
    let now = clock()
    if stallReason == "textureSubmissionsStopped" { stallReason = nil }
    submitted = now; submittedCount += 1
    record(now, arrival: false)
  }

  // Returns true exactly once, and only while an unfulfilled first-frame wait is eligible.
  func pollFirstFrame() -> Bool {
    lock.lock(); defer { lock.unlock() }
    advance(clock())
    guard streaming, first == nil, elapsed >= 10, !reportedFirst else { return false }
    reportedFirst = true
    return true
  }

  func snapshot() -> [String: Any] {
    lock.lock(); defer { lock.unlock() }
    let now = clock()
    let window = min(2, max(0, now - created))
    let epoch = Int(floor(now * 10))
    var received = 0, pushed = 0
    for i in 0..<20 where epochs[i] > epoch - 20 && epochs[i] <= epoch {
      received += arrivals[i]; pushed += pushes[i]
    }
    // Only committed eligible time: speculative time could move backwards
    // when the next watchdog tick reveals a process-suspension gap.
    let wait = elapsed
    var result: [String: Any] = [
      "sessionId": sessionId, "framesReceived": receivedCount, "framesSubmitted": submittedCount,
      "waitingForFirstFrame": first == nil, "firstFrameWaitUs": Int(wait * 1_000_000),
      "measurementWindowUs": Int(window * 1_000_000)
    ]
    if window >= 0.1 {
      result["receivedFps"] = Double(received) / window
      result["submittedFps"] = Double(pushed) / window
    }
    if let last { result["timeSinceLastFrameUs"] = Int(max(0, now - last) * 1_000_000) }
    if let submitted { result["timeSinceLastSubmissionUs"] = Int(max(0, now - submitted) * 1_000_000) }
    if let stallReason { result["stallReason"] = stallReason }
    if first == nil && reportedFirst { result["stallReason"] = "firstFrameTimeout" }
    return result
  }
}
