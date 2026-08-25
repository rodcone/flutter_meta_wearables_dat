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
  /// Guards `_isEnabled`, which is read from the main thread
  /// (`handleDidEnterBackground`, `mustNotStreamNow`, the method channel),
  /// from the SDK's frame-delivery thread (`processAndSendFrame`), and from
  /// whichever thread AVAudioSession posts its notifications on.
  private let stateLock = NSLock()

  /// True once the AVAudioSession keep-alive has been established, until it is
  /// torn down or an attempt to restore it fails.
  ///
  /// `sessionQueue` owns this: every write happens there, and every decision
  /// that depends on it is made there too, so the queue's serial order is the
  /// state machine. That is why no separate record of "what was last
  /// requested" is needed — an `enable` and a `disable` run in call order and
  /// each sees what the previous one left.
  ///
  /// A transient OS interruption (phone call, Siri) deactivates the session
  /// underneath us without clearing this, which is deliberate: it is what lets
  /// the `.ended` handler know the keep-alive is ours to restore. So this is
  /// "the keep-alive is established", not "audio is flowing this instant".
  ///
  /// Deliberately *not* set optimistically ahead of activation. The plugin
  /// reads it as authority to skip the background teardown
  /// (`handleDidEnterBackground`) and to allow a stream start while
  /// backgrounded (`mustNotStreamNow`); claiming a keep-alive that has not
  /// been established yet would let the app suspend with a live
  /// `DeviceSession` and a texture nothing will release. While activation is
  /// in flight this reads `false`, so both call sites take the safe branch.
  private var _isEnabled = false

  /// Whether the AVAudioSession keep-alive is currently active. Reads from
  /// off the queue are a snapshot; the authoritative checks are the ones
  /// inside the queued blocks.
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
    sessionQueue.async { [weak self] in
      // Nothing to do, and nothing to report: the controller is gone, or the
      // session is already active.
      guard let self, !self.isEnabled else {
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
    sessionQueue.async { [weak self] in
      // Same as `enable`, inverted: the controller is gone, or the session is
      // already inactive.
      guard let self, self.isEnabled else {
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

  private func setEnabled(_ value: Bool) {
    stateLock.lock()
    _isEnabled = value
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
    guard isEnabled,
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
        guard let self, self.isEnabled else { return }
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
    guard isEnabled else { return }
    NSLog("[MWDAT] AVAudioSession media services were reset — re-activating")
    sessionQueue.async { [weak self] in
      guard let self, self.isEnabled else { return }
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
