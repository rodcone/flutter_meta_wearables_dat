import UIKit

/// Observes *true* app background / foreground transitions.
///
/// ## Why NotificationCenter and not the Flutter plugin lifecycle APIs
///
/// `registrar.addApplicationDelegate(_:)` routes through
/// `FlutterPluginAppLifeCycleDelegate`, which deliberately stops forwarding
/// application lifecycle events once the host app adopts `UISceneDelegate`.
/// Flutter's own comment on `-appSupportsSceneLifecycle` says it plainly:
///
/// > When UIScene lifecycle is being used, some application lifecycle events
/// > are not call by UIKit. **However, the notifications are still sent.** When
/// > a Flutter app has been migrated to UIScene, Flutter should not use the
/// > notifications to forward application events to plugins since they are not
/// > expected to be called.
///
/// Apps created with current Flutter templates are scene-based by default, so
/// relying on `addApplicationDelegate` means this plugin silently receives
/// nothing for a growing share of hosts — the worst kind of failure, because it
/// looks like the feature works and it simply never fires.
///
/// `registrar.addSceneDelegate(_:)` is Flutter's intended answer, but it needs
/// Flutter 3.38+ (a floor bump for every consumer) *and* only reaches plugins
/// when the host's scene delegate is, or forwards to, `FlutterSceneDelegate` —
/// a host with its own plain `UISceneDelegate` still gets nothing.
///
/// The notifications themselves are posted by UIKit in every case. Observing
/// them directly is therefore both broader and cheaper than either Flutter API,
/// and requires no version floor.
///
/// ## What counts as backgrounded
///
/// Only a genuine background transition. `willResignActive` /
/// `didBecomeActive` (and their `UIScene` equivalents) are deliberately **not**
/// observed: those fire for Control Center, the notification shade, the app
/// switcher preview, an incoming-call banner, Face ID, and system alerts, none
/// of which should tear down a stream.
///
/// For multi-window hosts, a scene backgrounding is only treated as the app
/// backgrounding when *every* attached scene is in the background — otherwise
/// backgrounding one iPad window would kill a stream the other window is still
/// showing.
@MainActor
final class AppLifecycleObserver {

  /// Fired once per background transition, after the latch flips.
  var onDidEnterBackground: (() -> Void)?
  /// Fired once per foreground transition, after the latch flips.
  var onWillEnterForeground: (() -> Void)?

  /// The latch. Also the deduplication mechanism: a non-scene host delivers
  /// both the `UIApplication` notification and (if the plugin keeps its
  /// `FlutterApplicationLifeCycleDelegate` conformance) the delegate callback,
  /// and a multi-scene host delivers one notification per scene.
  private(set) var isBackgrounded = false

  private var tokens: [NSObjectProtocol] = []
  private var started = false

  /// Nonisolated so the plugin can hold this as a plain stored property.
  /// Constructing it touches nothing isolated; `start()` is where main-actor
  /// work begins.
  nonisolated init() {}

  func start() {
    guard !started else { return }
    started = true

    // `queue: nil` delivers the block synchronously on the posting thread,
    // which for these UIKit notifications is the main thread. This is
    // load-bearing rather than incidental: a background teardown has to take a
    // `beginBackgroundTask` assertion before the handler returns, and hopping
    // to `OperationQueue.main` would defer that past the point iOS may suspend
    // us.
    observe(UIApplication.didEnterBackgroundNotification) { [weak self] in
      self?.reevaluateBackgroundState()
    }
    observe(UIApplication.willEnterForegroundNotification) { [weak self] in
      self?.noteWillEnterForeground()
    }
    observe(UIScene.didEnterBackgroundNotification) { [weak self] in
      self?.reevaluateBackgroundState()
    }
    observe(UIScene.willEnterForegroundNotification) { [weak self] in
      self?.noteWillEnterForeground()
    }
  }

  func stop() {
    tokens.forEach { NotificationCenter.default.removeObserver($0) }
    tokens.removeAll()
    started = false
  }

  private func observe(_ name: Notification.Name, _ body: @escaping @MainActor () -> Void) {
    let token = NotificationCenter.default.addObserver(
      forName: name, object: nil, queue: nil
    ) { _ in
      // Deployment target is 17.2, and UIKit posts these on the main thread.
      MainActor.assumeIsolated { body() }
    }
    tokens.append(token)
  }

  /// Entry point for the `UIApplicationDelegate` callbacks, so a host that
  /// still delivers them funnels into the same latch instead of double-firing.
  func noteDidEnterBackground() {
    guard !isBackgrounded else { return }
    isBackgrounded = true
    NSLog("[MWDAT] lifecycle: app entered background")
    onDidEnterBackground?()
  }

  func noteWillEnterForeground() {
    guard isBackgrounded else { return }
    isBackgrounded = false
    NSLog("[MWDAT] lifecycle: app entering foreground")
    onWillEnterForeground?()
  }

  /// A background notification only counts once nothing is left in front.
  private func reevaluateBackgroundState() {
    guard allScenesBackgrounded() else { return }
    noteDidEnterBackground()
  }

  /// True when the app as a whole is background, not merely one of its windows.
  private func allScenesBackgrounded() -> Bool {
    let app = UIApplication.shared
    if app.applicationState == .background { return true }
    let scenes = app.connectedScenes.filter { $0.activationState != .unattached }
    // No attached scenes at all is ambiguous (pre-attach, or a headless
    // engine). Treat it as "not backgrounded" so we never tear down a stream on
    // a state we cannot actually observe.
    guard !scenes.isEmpty else { return false }
    return scenes.allSatisfy { $0.activationState == .background }
  }
}
