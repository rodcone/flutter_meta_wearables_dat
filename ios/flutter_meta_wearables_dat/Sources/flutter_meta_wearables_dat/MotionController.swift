import Foundation
import MWDATCore
import MWDATMotion

/// Owns Motion listeners independently of the camera. All lifecycle operations
/// and Flutter delivery run on the main actor; the SDK sample buffer is bounded.
@MainActor
final class MotionController {
  nonisolated init() {}

  let samples = MotionStreamHandler()
  let states = MotionStreamHandler(initialValue: "stopped", replayLatest: true)
  let errors = MotionStreamHandler()
  var onSampleSubscriptionRefresh: ((MWDATMotion.Motion, UInt64) async -> Void)?
  private(set) var motion: MWDATMotion.Motion?
  private(set) var keepsSessionAlive = false
  private var sampleTask: Task<Void, Never>?
  private var stateToken: (any AnyListenerToken)?
  private var errorToken: (any AnyListenerToken)?
  private var generation: UInt64 = 0
  private var sampleSubscriptionGeneration: UInt64 = 0

  var isAttached: Bool { motion != nil }

  var needsSampleSubscriptionRefresh: Bool {
    guard let motion, motion.state == .started || motion.state == .starting else { return false }
    return keepsSessionAlive && samples.hasListener &&
      sampleSubscriptionGeneration != samples.subscriptionGeneration
  }

  /// DAT owns one persistent buffered stream per capability. A listener that
  /// replaces the original must wait for a new capability, not drain that buffer.
  func requestSampleSubscriptionRefresh() {
    guard needsSampleSubscriptionRefresh, let motion else { return }
    let epoch = generation
    let subscription = samples.subscriptionGeneration
    Task { [weak self] in
      guard let self, self.generation == epoch,
            self.samples.subscriptionGeneration == subscription,
            self.needsSampleSubscriptionRefresh else { return }
      await self.onSampleSubscriptionRefresh?(motion, subscription)
    }
  }

  func attach(_ motion: MWDATMotion.Motion) {
    precondition(self.motion == nil)
    self.motion = motion
    keepsSessionAlive = true
    generation &+= 1
    let epoch = generation
    sampleSubscriptionGeneration = samples.subscriptionGeneration
    let subscription = sampleSubscriptionGeneration
    samples.didStartListening = { [weak self] in
      Task { @MainActor in
        guard let self, self.generation == epoch else { return }
        self.requestSampleSubscriptionRefresh()
      }
    }
    stateToken = motion.statePublisher.listen { [weak self] state in
      Task { @MainActor in
        guard let self, self.generation == epoch else { return }
        if state == .stopped { self.keepsSessionAlive = false }
        self.states.send(Self.stateCode(state))
      }
    }
    errorToken = motion.errorPublisher.listen { [weak self] error in
      Task { @MainActor in
        guard let self, self.generation == epoch else { return }
        self.keepsSessionAlive = false
        self.sendError(code: Self.errorCode(error), message: error.description)
      }
    }
    // Obtain the buffered AsyncStream before start. One main-actor consumer
    // forwards each sample directly; it never schedules one task per sample.
    let stream = motion.samples
    sampleTask = Task { [weak self] in
      for await sample in stream {
        guard let self, !Task.isCancelled, self.generation == epoch else { return }
        guard self.samples.hasListener,
              self.samples.subscriptionGeneration == subscription else { continue }
        self.samples.send(Self.sampleMap(sample))
      }
    }
    states.send(Self.stateCode(motion.state))
    motion.start()
    states.send(Self.stateCode(motion.state))
  }

  /// Invalidates queued callbacks before cancellation can suspend. The strong
  /// capability reference is retained until the caller removes it or ends its
  /// device session, including when SDK removal fails.
  func stopDelivery() async {
    keepsSessionAlive = false
    generation &+= 1
    sampleTask?.cancel()
    sampleTask = nil
    let oldStateToken = stateToken
    let oldErrorToken = errorToken
    stateToken = nil
    errorToken = nil
    if let oldStateToken { await oldStateToken.cancel() }
    if let oldErrorToken { await oldErrorToken.cancel() }
    motion?.stop()
    states.send("stopped")
  }

  func release() {
    motion = nil
    keepsSessionAlive = false
    samples.didStartListening = nil
  }

  func sendError(code: String, message: String) {
    errors.send(["code": code, "message": message])
  }

  static func samplingRate(_ value: Int) -> MotionSamplingRate? {
    switch value {
    case 5: return .hz5
    case 10: return .hz10
    case 15: return .hz15
    case 24: return .hz24
    case 30: return .hz30
    case 60: return .hz60
    default: return nil
    }
  }

  static func stateCode(_ state: MotionState) -> String {
    switch state {
    case .stopped: return "stopped"
    case .starting: return "starting"
    case .started: return "started"
    case .stopping: return "stopping"
    @unknown default: return "unknown"
    }
  }

  static func errorCode(_ error: MotionError) -> String {
    switch error {
    case .sensorUnavailable: return "sensorUnavailable"
    case .capabilityClosed: return "capabilityClosed"
    case .deviceDisconnected: return "deviceDisconnected"
    @unknown default: return "unknown"
    }
  }

  static func sampleMap(_ sample: MotionSample) -> [String: Any] {
    let source: String
    switch sample.source {
    case .glasses: source = "glasses"
    case .neuralBand: source = "neuralBand"
    case .unknown: source = "unknown"
    }
    var payload: [String: Any] = ["timestampNs": sample.timestampNs, "source": source]
    for (name, vector) in [("accelerometer", sample.accelerometer),
                           ("gyroscope", sample.gyroscope),
                           ("magnetometer", sample.magnetometer)] {
      if let vector {
        payload[name] = ["x": Double(vector.x), "y": Double(vector.y), "z": Double(vector.z)]
      }
    }
    if let q = sample.orientation {
      payload["orientation"] = ["x": Double(q.x), "y": Double(q.y), "z": Double(q.z), "w": Double(q.w)]
    }
    return payload
  }
}
