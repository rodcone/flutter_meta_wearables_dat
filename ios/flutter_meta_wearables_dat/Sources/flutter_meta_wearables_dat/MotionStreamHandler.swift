import Flutter
import Foundation

/// Motion events are delivered synchronously on the platform thread. Keeping
/// the current sink here avoids retaining a cancelled listener in queued work.
final class MotionStreamHandler: NSObject, FlutterStreamHandler {
  private var sink: FlutterEventSink?
  private let replayLatest: Bool
  private var latest: Any?
  private(set) var subscriptionGeneration: UInt64 = 0

  init(initialValue: Any? = nil, replayLatest: Bool = false) {
    self.latest = initialValue
    self.replayLatest = replayLatest
  }

  var hasListener: Bool { sink != nil }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    assert(Thread.isMainThread)
    subscriptionGeneration &+= 1
    sink = events
    if replayLatest, let latest { events(latest) }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    assert(Thread.isMainThread)
    subscriptionGeneration &+= 1
    sink = nil
    return nil
  }

  func send(_ value: Any) {
    assert(Thread.isMainThread)
    if replayLatest { latest = value }
    sink?(value)
  }
}
