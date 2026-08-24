import AVFoundation
import Foundation
import UIKit

/// Owns the AVAudioSession keep-alive that lets the plugin's stream session
/// survive backgrounding, screen lock, and app switches. Follows Meta's
/// official BackgroundStreamingGuide: an active `.playAndRecord` audio
/// session paired with the `audio` UIBackgroundMode prevents iOS from
/// suspending the process, which in turn keeps the BLE / External Accessory
/// link to the glasses alive.
final class BackgroundStreamingController {
  /// Guards `_isEnabled` and `_desiredEnabled`. Both are read from the main
  /// thread (`handleDidEnterBackground`, `mustNotStreamNow`, the method
  /// channel), from the SDK's frame-delivery thread (`processAndSendFrame`),
  /// and from whichever thread AVAudioSession posts its notifications on.
  private let stateLock = NSLock()

  /// True only once the AVAudioSession keep-alive is genuinely active.
  ///
  /// Written exclusively from `sessionQueue`, so writes land in the same
  /// order as the calls that requested them. This is deliberately *not* set
  /// optimistically ahead of activation: the plugin reads it as authority to
  /// skip the background teardown (`handleDidEnterBackground`) and to allow a
  /// stream start while backgrounded (`mustNotStreamNow`). Claiming a
  /// keep-alive that has not been established yet would let the app suspend
  /// with a live `DeviceSession` and a texture nothing will release. While
  /// activation is in flight this reads `false`, so both call sites take the
  /// safe branch and tear down rather than trust an unfulfilled promise.
  private var _isEnabled = false

  /// The most recently requested state, written on the caller's thread the
  /// moment `enable`/`disable` is called. Queued work re-reads it so a
  /// request that was superseded while it waited becomes a no-op — this is
  /// what stops a failed activation's rollback from clobbering a later
  /// successful one, and stops an interruption re-activation from resurrecting
  /// a session that was disabled while the notification was in flight.
  private var _desiredEnabled = false

  /// Whether the AVAudioSession keep-alive is currently active.
  var isEnabled: Bool {
    stateLock.lock()
    defer { stateLock.unlock() }
    return _isEnabled
  }

  /// AVAudioSession activation and deactivation block for hundreds of
  /// milliseconds while the media server negotiates, and the method channel
  /// delivers calls on the main thread — doing the work inline froze the UI
  /// on every stream start and stop (AVAudioSession_iOS.mm warns about
  /// exactly this). All session work runs on this serial queue instead.
  private let sessionQueue = DispatchQueue(
    label: "com.rodcone.mwdat.audio-session",
    qos: .userInitiated
  )

  private var didRegisterObservers = false

  init() {}

  /// Configures and activates the AVAudioSession on the session queue and
  /// starts listening for interruptions. Reports the underlying
  /// AVAudioSession error if activation fails — callers should forward this
  /// to the Flutter result as a platform error so developers can diagnose
  /// Info.plist misconfiguration. The completion is invoked on the session
  /// queue, and always reflects the real outcome of the work: a second
  /// `enable()` issued while the first is still in flight waits behind it on
  /// the serial queue rather than being told it already succeeded.
  func enable(completion: @escaping (Error?) -> Void) {
    registerObserversIfNeeded()
    setDesiredEnabled(true)
    sessionQueue.async { [weak self] in
      // Nothing to do, and nothing to report: the controller is gone, a
      // `disable()` superseded this request while it waited, or the session is
      // already active.
      guard let self, self.desiredEnabled, !self.isEnabled else {
        completion(nil)
        return
      }
      do {
        try Self.activateSession()
        self.setEnabled(true)
        NSLog("[MWDAT] Background streaming enabled — AVAudioSession active")
        completion(nil)
      } catch {
        self.setEnabled(false)
        completion(error)
      }
    }
  }

  /// Deactivates the audio session on the session queue. Safe to call when
  /// already disabled. The completion is invoked on the session queue once
  /// the deactivation has actually run — the Dart future awaits it, which
  /// keeps the common "stop streaming, then leave the app" sequence from
  /// being suspended with the session still active.
  func disable(completion: @escaping () -> Void = {}) {
    setDesiredEnabled(false)
    sessionQueue.async { [weak self] in
      // Same three cases as `enable`, inverted: gone, superseded by a later
      // `enable()`, or already inactive.
      guard let self, !self.desiredEnabled, self.isEnabled else {
        completion()
        return
      }
      self.setEnabled(false)
      // Pass `.notifyOthersOnDeactivation` so other apps (e.g. music) can
      // resume immediately instead of waiting for their next routing event.
      try? AVAudioSession.sharedInstance().setActive(
        false,
        options: [.notifyOthersOnDeactivation]
      )
      NSLog("[MWDAT] Background streaming disabled — AVAudioSession released")
      completion()
    }
  }

  private static func activateSession() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(
      .playAndRecord,
      mode: .videoRecording,
      options: [.allowBluetoothHFP, .mixWithOthers]
    )
    try session.setActive(true)
  }

  private var desiredEnabled: Bool {
    stateLock.lock()
    defer { stateLock.unlock() }
    return _desiredEnabled
  }

  private func setEnabled(_ value: Bool) {
    stateLock.lock()
    _isEnabled = value
    stateLock.unlock()
  }

  private func setDesiredEnabled(_ value: Bool) {
    stateLock.lock()
    _desiredEnabled = value
    stateLock.unlock()
  }

  private func registerObserversIfNeeded() {
    guard !didRegisterObservers else { return }
    didRegisterObservers = true

    let nc = NotificationCenter.default
    nc.addObserver(
      self,
      selector: #selector(handleInterruption(_:)),
      name: AVAudioSession.interruptionNotification,
      object: nil
    )
    nc.addObserver(
      self,
      selector: #selector(handleMediaServicesReset),
      name: AVAudioSession.mediaServicesWereResetNotification,
      object: nil
    )
  }

  @objc private func handleInterruption(_ notification: Notification) {
    guard desiredEnabled,
          let info = notification.userInfo,
          let typeValue = info[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: typeValue)
    else { return }

    switch type {
    case .began:
      NSLog("[MWDAT] Audio interruption began")
    case .ended:
      // Re-activate so the keep-alive survives a phone call / Siri / etc.
      // Re-checked on the queue: a `disable()` can land between the guard
      // above and this block, and the serial queue would otherwise order the
      // re-activation *after* the deactivation and leave the session live.
      sessionQueue.async { [weak self] in
        guard let self, self.desiredEnabled else { return }
        do {
          try AVAudioSession.sharedInstance().setActive(true)
          self.setEnabled(true)
          NSLog("[MWDAT] Audio interruption ended — session re-activated")
        } catch {
          self.setEnabled(false)
          NSLog("[MWDAT] Failed to re-activate AVAudioSession after interruption: \(error)")
        }
      }
    @unknown default:
      break
    }
  }

  @objc private func handleMediaServicesReset() {
    // Rare but documented — whole audio stack reset. Re-activate if we were
    // keeping the session alive.
    guard desiredEnabled else { return }
    NSLog("[MWDAT] AVAudioSession media services were reset — re-activating")
    sessionQueue.async { [weak self] in
      guard let self, self.desiredEnabled else { return }
      do {
        try Self.activateSession()
        self.setEnabled(true)
      } catch {
        self.setEnabled(false)
        NSLog("[MWDAT] Failed to re-activate AVAudioSession after reset: \(error)")
      }
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }
}
