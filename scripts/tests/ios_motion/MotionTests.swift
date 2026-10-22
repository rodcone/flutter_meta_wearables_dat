import Foundation
import MWDATMotion

@main
struct MotionTests {
  @MainActor
  static func main() async {
    let controller = MotionController()
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
    replacement.continuation.yield(MotionSample(timestampNs: 6))
    await drain()
    precondition(samples.count == 2 && newSamples.count == 1)
    precondition(newSamples[0]["timestampNs"] as? Int64 == 6)

    replacement.errorPublisher.send(.sensorUnavailable)
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
    print("Motion controller: nullable payload, timestamp precision, stale callbacks, replacement, cancellation, state replay and rate validation passed")
  }

  @MainActor
  static func drain() async {
    for _ in 0..<12 { await Task.yield() }
    try? await Task.sleep(for: .milliseconds(10))
  }
}
