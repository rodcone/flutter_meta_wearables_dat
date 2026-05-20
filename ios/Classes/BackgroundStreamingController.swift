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
  /// When true, the AVAudioSession keep-alive is active so the SDK keeps
  /// delivering frames to the plugin while the app is backgrounded. The
  /// plugin still invalidates the HEVC decoder on background (iOS forbids
  /// GPU access while backgrounded) and forwards raw hvc1 NAL bytes to
  /// `videoFramesStream()` for recording; the texture pauses until
  /// foreground. Flipped from the plugin when enable/disable is called
  /// from Dart.
  private(set) var isEnabled: Bool = false

  private var didRegisterObservers = false

  init() {}

  /// Activates the AVAudioSession and starts listening for interruptions.
  /// Throws the underlying AVAudioSession error if activation fails —
  /// callers should forward this to the Flutter result as a platform error
  /// so developers can diagnose Info.plist misconfiguration.
  func enable() throws {
    if isEnabled { return }

    let session = AVAudioSession.sharedInstance()
    try session.setCategory(
      .playAndRecord,
      mode: .videoRecording,
      options: [.allowBluetoothHFP, .mixWithOthers]
    )
    try session.setActive(true)

    registerObserversIfNeeded()
    isEnabled = true
    NSLog("[MWDAT] Background streaming enabled — AVAudioSession active")
  }

  /// Deactivates the audio session. Safe to call when already disabled.
  func disable() {
    guard isEnabled else { return }
    isEnabled = false
    // Pass `.notifyOthersOnDeactivation` so other apps (e.g. music) can
    // resume immediately instead of waiting for their next routing event.
    try? AVAudioSession.sharedInstance().setActive(
      false,
      options: [.notifyOthersOnDeactivation]
    )
    NSLog("[MWDAT] Background streaming disabled — AVAudioSession released")
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
      selector: #selector(handleRouteChange(_:)),
      name: AVAudioSession.routeChangeNotification,
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
      try? AVAudioSession.sharedInstance().setActive(true)
      NSLog("[MWDAT] Audio interruption ended — session re-activated")
    @unknown default:
      break
    }
  }

  @objc private func handleRouteChange(_ notification: Notification) {
    guard isEnabled,
          let info = notification.userInfo,
          let reasonValue = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue)
    else { return }
    NSLog("[MWDAT] AVAudioSession route change: \(reason.rawValue)")
  }

  @objc private func handleMediaServicesReset() {
    // Rare but documented — whole audio stack reset. Re-activate if we were
    // keeping the session alive.
    guard isEnabled else { return }
    NSLog("[MWDAT] AVAudioSession media services were reset — re-activating")
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(
        .playAndRecord,
        mode: .videoRecording,
        options: [.allowBluetoothHFP, .mixWithOthers]
      )
      try session.setActive(true)
    } catch {
      NSLog("[MWDAT] Failed to re-activate AVAudioSession after reset: \(error)")
    }
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }
}
