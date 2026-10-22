import Foundation
import MWDATMotion

@main
struct MotionTests {
  @MainActor
  static func main() async {
    await pendingListenerReplacement()
    await listenerAfterStart()
    await cancelledRefresh()
    await stoppedMotionDoesNotRefresh()
    let controller = MotionController()
    var refreshed: Motion?
    installRefresh(controller) { refreshed = $0 }
    var samples: [[String: Any]] = []
    var states: [String] = []
    var errors: [[String: String]] = []
    _ = controller.samples.onListen(withArguments: nil) { samples.append($0 as! [String: Any]) }
    _ = controller.states.onListen(withArguments: nil) { states.append($0 as! String) }
    _ = controller.errors.onListen(withArguments: nil) { errors.append($0 as! [String: String]) }
    precondition(states == ["stopped"])

    let first = Motion()
    controller.attach(first)
    precondition(first.starts == 1 && controller.keepsSessionAlive)
    let timestamp: Int64 = 9_007_199_254_740_993
    first.continuation.yield(MotionSample(
      timestampNs: timestamp, orientation: Quaternion(x: 1, y: 2, z: 3, w: 4), source: .neuralBand))
    await drain()
    precondition(samples.count == 1)
    precondition(samples[0]["timestampNs"] as? Int64 == timestamp)
    precondition(samples[0]["accelerometer"] == nil)
    precondition(samples[0]["gyroscope"] == nil)
    precondition(samples[0]["magnetometer"] == nil)
    precondition(samples[0]["source"] as? String == "neuralBand")
    precondition(samples[0]["orientation"] as? [String: Double] == ["x": 1, "y": 2, "z": 3, "w": 4])

    // Callback tasks queued before teardown must not revive the old capability.
    first.statePublisher.send(.starting)
    first.errorPublisher.send(.deviceDisconnected)
    first.continuation.yield(MotionSample(timestampNs: 2))
    await controller.stopDelivery()
    controller.release()
    await drain()
    precondition(samples.count == 1 && errors.isEmpty)
    precondition(states.last == "stopped" && first.stops == 1)
    precondition(!controller.keepsSessionAlive)

    let replacement = Motion()
    controller.attach(replacement)
    first.statePublisher.send(.stopped)
    first.continuation.yield(MotionSample(timestampNs: 3))
    replacement.continuation.yield(MotionSample(
      timestampNs: 4, accelerometer: Vector3(x: 1.5, y: -2, z: 9.81)))
    await drain()
    precondition(samples.count == 2)
    precondition(samples.last?["timestampNs"] as? Int64 == 4)
    precondition(states.last == "started")

    // Unsubscribing does not stop the SDK capability; events are not replayed.
    _ = controller.samples.onCancel(withArguments: nil)
    replacement.continuation.yield(MotionSample(timestampNs: 5))
    await drain()
    var newSamples: [[String: Any]] = []
    _ = controller.samples.onListen(withArguments: nil) { newSamples.append($0 as! [String: Any]) }
    precondition(newSamples.isEmpty && replacement.stops == 0)
    // A sample produced by the old capability even after relisten is withheld
    // until the new SDK capability establishes the subscription boundary.
    replacement.continuation.yield(MotionSample(timestampNs: 6))
    await drain()
    precondition(newSamples.isEmpty && replacement.stops == 1)
    guard let refreshed else { fatalError("Relistening did not refresh Motion") }
    precondition(refreshed.starts == 1)
    refreshed.continuation.yield(MotionSample(timestampNs: 6))
    await drain()
    precondition(samples.count == 2 && newSamples.count == 1)
    precondition(newSamples[0]["timestampNs"] as? Int64 == 6)

    refreshed.errorPublisher.send(.sensorUnavailable)
    await drain()
    precondition(errors.last?["code"] == "sensorUnavailable")
    precondition(!controller.keepsSessionAlive)
    var seeded: [String] = []
    _ = controller.states.onCancel(withArguments: nil)
    _ = controller.states.onListen(withArguments: nil) { seeded.append($0 as! String) }
    precondition(seeded == ["started"])
    precondition(MotionController.samplingRate(60) == .hz60)
    precondition(MotionController.samplingRate(0) == nil)
    precondition(MotionController.samplingRate(7) == nil)
    await controller.stopDelivery()
    controller.release()
    precondition(!controller.isAttached)
    print("Motion controller: payload, timestamp precision, stale callbacks, listener refresh/buffer isolation, cancellation, state replay and rate validation passed")
  }

  @MainActor
  static func pendingListenerReplacement() async {
    let controller = MotionController()
    let motion = Motion()
    var refreshed: Motion?
    var refreshes = 0
    installRefresh(controller) { refreshed = $0; refreshes += 1 }
    _ = controller.samples.onListen(withArguments: nil) { _ in }
    controller.attach(motion)
    await drain()
    // None of this burst may cross into a new subscription, even when the
    // main actor has not resumed the SDK consumer before cancel/relisten.
    for timestamp in 777...1032 {
      motion.continuation.yield(MotionSample(timestampNs: Int64(timestamp)))
    }
    _ = controller.samples.onCancel(withArguments: nil)
    // Rapid replacements must coalesce around the latest listener.
    _ = controller.samples.onListen(withArguments: nil) { _ in
      fatalError("An intermediate listener received an old sample")
    }
    _ = controller.samples.onCancel(withArguments: nil)
    var received: [Int64] = []
    _ = controller.samples.onListen(withArguments: nil) {
      received.append(($0 as! [String: Any])["timestampNs"] as! Int64)
    }
    await drain()
    precondition(received.isEmpty, "Previous subscription leaked buffered timestamps: \(received)")
    precondition(refreshes == 1 && motion.stops == 1)
    refreshed!.continuation.yield(MotionSample(timestampNs: 2000))
    await drain()
    precondition(received == [2000])
    await controller.stopDelivery()
    controller.release()
  }

  @MainActor
  static func listenerAfterStart() async {
    let controller = MotionController()
    let motion = Motion()
    var refreshed: Motion?
    installRefresh(controller) { refreshed = $0 }
    controller.attach(motion)
    motion.continuation.yield(MotionSample(timestampNs: 1))
    var received: [Int64] = []
    _ = controller.samples.onListen(withArguments: nil) {
      received.append(($0 as! [String: Any])["timestampNs"] as! Int64)
    }
    await drain()
    precondition(received.isEmpty && motion.stops == 1 && refreshed != nil)
    refreshed!.continuation.yield(MotionSample(timestampNs: 2))
    await drain()
    precondition(received == [2])
    await controller.stopDelivery()
    controller.release()
  }

  @MainActor
  static func cancelledRefresh() async {
    for stopCapability in [false, true] {
      let controller = MotionController()
      let motion = Motion()
      var refreshes = 0
      installRefresh(controller) { _ in refreshes += 1 }
      _ = controller.samples.onListen(withArguments: nil) { _ in }
      controller.attach(motion)
      await drain()
      _ = controller.samples.onCancel(withArguments: nil)
      _ = controller.samples.onListen(withArguments: nil) { _ in }
      if stopCapability {
        await controller.stopDelivery()
        controller.release()
      } else {
        _ = controller.samples.onCancel(withArguments: nil)
      }
      await drain()
      precondition(refreshes == 0 && motion.starts == 1)
      precondition(motion.stops == (stopCapability ? 1 : 0))
      if !stopCapability {
        await controller.stopDelivery()
        controller.release()
      }
    }
  }

  @MainActor
  static func stoppedMotionDoesNotRefresh() async {
    let controller = MotionController()
    let motion = Motion()
    var refreshes = 0
    installRefresh(controller) { _ in refreshes += 1 }
    _ = controller.samples.onListen(withArguments: nil) { _ in }
    controller.attach(motion)
    motion.stop()
    await drain()
    _ = controller.samples.onCancel(withArguments: nil)
    _ = controller.samples.onListen(withArguments: nil) { _ in }
    await drain()
    precondition(refreshes == 0 && motion.starts == 1)
    await controller.stopDelivery()
    controller.release()
  }

  /// The real plugin serializes this work with camera/device operations and
  /// removes/adds Motion on the same parent. This double tests controller routing
  /// and fresh-buffer isolation, not the full plugin or physical device lifetime.
  @MainActor
  static func installRefresh(_ controller: MotionController, created: @escaping (Motion) -> Void) {
    controller.onSampleSubscriptionRefresh = { [weak controller] previous, subscription in
      guard let controller, controller.motion === previous,
            controller.samples.subscriptionGeneration == subscription,
            controller.needsSampleSubscriptionRefresh else { return }
      await controller.stopDelivery()
      controller.release()
      let replacement = Motion()
      controller.attach(replacement)
      created(replacement)
    }
  }

  @MainActor
  static func drain() async {
    for _ in 0..<12 { await Task.yield() }
    try? await Task.sleep(for: .milliseconds(10))
  }
}
