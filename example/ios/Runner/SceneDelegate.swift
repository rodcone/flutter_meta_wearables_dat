import Flutter
import UIKit

/// Required from iOS 27, which no longer launches an app that has not adopted
/// the `UIScene` lifecycle.
///
/// `FlutterSceneDelegate` does the work: it owns the window, forwards scene
/// lifecycle events to the engine, and — through `super` below — hands scene
/// URL events to registered plugins, which is how `app_links` receives the DAT
/// registration callback on `myexampleapp://`.
///
/// Worth knowing for anyone porting an app that uses this plugin: the plugin
/// itself needed no change. It already observes background/foreground through
/// `NotificationCenter` rather than the application delegate, precisely because
/// Flutter stops forwarding application lifecycle events once a host adopts
/// scenes.
class SceneDelegate: FlutterSceneDelegate {
  override func scene(
    _ scene: UIScene,
    openURLContexts URLContexts: Set<UIOpenURLContext>
  ) {
    for context in URLContexts {
      NSLog("[SceneDelegate] Opened URL: \(context.url.absoluteString)")
    }
    super.scene(scene, openURLContexts: URLContexts)
  }
}
