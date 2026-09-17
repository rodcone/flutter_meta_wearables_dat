import Flutter
import UIKit

/// Scene-based, which iOS 27 requires to launch at all.
///
/// Plugin registration moved to `didInitializeImplicitFlutterEngine`: the
/// implicit engine does not exist when the app delegate launches — it is
/// created when the scene connects — so `window?.rootViewController` is nil in
/// `didFinishLaunchingWithOptions`, and anything that reached for a
/// `FlutterViewController` there silently got nothing.
///
/// URL handling moved to `SceneDelegate`. The previous
/// `application(_:open:options:)` override invoked `handleUrl` *into* Dart on
/// the plugin's channel, which nothing has ever handled — the example receives
/// registration callbacks through the `app_links` package. All the override
/// really did was call `super`, which the scene delegate now does.
@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
