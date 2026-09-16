import Foundation
import QuartzCore

/// An immutable read of the frame pipeline's timing, taken under the lock so
/// every field describes the same instant.
struct FrameLiveness {
  /// Seconds since the last frame arrived from the SDK, or nil if none ever has.
  let sinceArrival: CFTimeInterval?
  /// Seconds since the last frame was pushed to the Flutter texture, or nil if
  /// none ever has.
  let sincePush: CFTimeInterval?
  /// Seconds since the *first* frame arrived. The baseline for "frames are
  /// arriving but none has ever reached the texture" — without it a pipeline
  /// that never pushed a single frame looks healthy forever, because the
  /// arrival clock keeps resetting and there is no push clock to compare to.
  let sinceFirstArrival: CFTimeInterval?
  let framesArrived: Int
  let framesPushed: Int
  /// Frames handed to us by the SDK that `frameQueue` has not started yet.
  /// Non-zero means we are the bottleneck, not the transport — each one pins a
  /// `CMSampleBuffer` and, with it, a buffer from the SDK's pool.
  let inFlight: Int
  /// High-water mark of [inFlight] since the stream started.
  let peakInFlight: Int
  /// The gap between the two most recent pushes, or nil before the second one.
  /// This is the instantaneous frame rate's denominator — deliberately not an
  /// average, so a stream that holds and then collapses reads as a collapse.
  let lastPushInterval: CFTimeInterval?

  /// Whether the SDK has delivered at least one frame on this stream. A stream
  /// that has never produced a frame is starting up, not stalled.
  var hasArrived: Bool { sinceArrival != nil }
}

/// Owns the timing of the video frame pipeline: the FPS throttle, and the
/// arrival/push timestamps the stall watchdog reads.
///
/// Two clocks' worth of history is kept, deliberately:
///
/// * **arrival** is stamped before every gate in `processAndSendFrame`, so it
///   tracks what the SDK hands us regardless of what the plugin then does with
///   it.
/// * **push** is stamped after `textureFrameAvailable`, so it tracks what
///   actually reaches Flutter.
///
/// A freeze with both flat is the stream going quiet; a freeze with arrivals
/// climbing and pushes flat is a plugin fault. Nothing else in the plugin can
/// tell those two apart, which is the whole reason this type exists.
///
/// Timing uses `CACurrentMediaTime()` — monotonic. `Date()` is wall-clock and a
/// backward NTP step makes the throttle's delta negative, at which point every
/// frame is dropped and the pipeline cannot recover on its own, because the
/// timestamp is only refreshed on frames that pass the throttle. That it also
/// pauses while the device sleeps is correct here: a sleeping device is not
/// streaming, and the gap should not read as a stall on resume.
///
/// State is written on the SDK's frame queue and read from the main actor, so
/// access is guarded by an unfair lock — the same pattern as
/// `PixelBufferTexture`.
final class FrameLivenessTracker {
  private var lock = os_unfair_lock()

  private var firstArrival: CFTimeInterval?
  private var lastArrival: CFTimeInterval?
  private var lastPush: CFTimeInterval?
  private var framesArrived = 0
  private var framesPushed = 0
  private var inFlight = 0
  private var peakInFlight = 0
  private var lastPushInterval: CFTimeInterval?
  private var targetFPS: Double = 30.0

  /// Clears per-stream history and sets the throttle's target.
  ///
  /// `fps` is clamped to at least 1. An unclamped 0 yields an infinite minimum
  /// interval, which silently freezes the texture after a single frame while
  /// `videoFramesStream()` keeps delivering — a failure with no symptom other
  /// than a frozen preview. The SDK's own `StreamConfiguration` is clamped the
  /// same way at the call site.
  func reset(targetFPS fps: Double) {
    os_unfair_lock_lock(&lock)
    firstArrival = nil
    lastArrival = nil
    lastPush = nil
    framesArrived = 0
    framesPushed = 0
    inFlight = 0
    peakInFlight = 0
    lastPushInterval = nil
    targetFPS = max(1.0, fps)
    os_unfair_lock_unlock(&lock)
  }

  /// Records that the SDK delivered a frame.
  ///
  /// Called from the publisher callback, **not** from the frame queue. Those
  /// are different instants: the callback is when the SDK hands the frame over,
  /// while the queue is our own backlog. Stamping this on the queue made the
  /// watchdog report "nothing arrived from the SDK" whenever we simply had not
  /// got round to the frames yet — blaming the transport for our own backlog.
  func noteArrival() {
    let now = CACurrentMediaTime()
    os_unfair_lock_lock(&lock)
    if firstArrival == nil { firstArrival = now }
    lastArrival = now
    framesArrived += 1
    inFlight += 1
    if inFlight > peakInFlight { peakInFlight = inFlight }
    os_unfair_lock_unlock(&lock)
  }

  /// Records that the frame queue has started processing a delivered frame.
  func noteDequeue() {
    os_unfair_lock_lock(&lock)
    if inFlight > 0 { inFlight -= 1 }
    os_unfair_lock_unlock(&lock)
  }

  /// Whether this frame should be pushed to the texture, per the FPS throttle.
  ///
  /// A pure decision — it stamps nothing. The clock advances in `notePush()`,
  /// once the frame has actually reached the texture, so a pipeline that passes
  /// the throttle and then fails to push still reads as stalled. Stamping here
  /// would record pushes that never happened and hide the one fault the
  /// watchdog exists to catch.
  ///
  /// A non-positive delta — which a monotonic clock should never produce, but
  /// which would wedge the pipeline permanently if it did — passes rather than
  /// throttles.
  func shouldPush() -> Bool {
    let now = CACurrentMediaTime()
    os_unfair_lock_lock(&lock)
    defer { os_unfair_lock_unlock(&lock) }

    guard let last = lastPush else { return true }
    let elapsed = now - last
    return !(elapsed > 0 && elapsed < 1.0 / targetFPS)
  }

  /// Records that a frame reached the Flutter texture.
  func notePush() {
    let now = CACurrentMediaTime()
    os_unfair_lock_lock(&lock)
    lastPushInterval = lastPush.map { now - $0 }
    lastPush = now
    framesPushed += 1
    os_unfair_lock_unlock(&lock)
  }

  /// Restarts the push clock without counting a push.
  ///
  /// Called when the texture is legitimately expected to have gone unwritten
  /// for a while — returning to the foreground after background streaming,
  /// where frames kept arriving but iOS forbade the GPU writes. Without this
  /// the first watchdog tick after foregrounding measures the whole background
  /// window and reports a stall that never happened.
  func resyncPushClock() {
    let now = CACurrentMediaTime()
    os_unfair_lock_lock(&lock)
    lastPush = now
    os_unfair_lock_unlock(&lock)
  }

  /// A consistent read of both clocks, relative to now.
  func snapshot() -> FrameLiveness {
    let now = CACurrentMediaTime()
    os_unfair_lock_lock(&lock)
    defer { os_unfair_lock_unlock(&lock) }
    return FrameLiveness(
      sinceArrival: lastArrival.map { now - $0 },
      sincePush: lastPush.map { now - $0 },
      sinceFirstArrival: firstArrival.map { now - $0 },
      framesArrived: framesArrived,
      framesPushed: framesPushed,
      inFlight: inFlight,
      peakInFlight: peakInFlight,
      lastPushInterval: lastPushInterval
    )
  }

  /// The configured throttle target, for logging.
  var currentTargetFPS: Double {
    os_unfair_lock_lock(&lock)
    defer { os_unfair_lock_unlock(&lock) }
    return targetFPS
  }
}
