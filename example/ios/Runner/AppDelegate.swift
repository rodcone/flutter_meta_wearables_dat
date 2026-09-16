import AVFoundation
import Flutter
import UIKit

/// Scene-based since iOS 27 requires it. Two things moved as a result:
///
/// * Plugin registration and the diagnostics channel are set up in
///   `didInitializeImplicitFlutterEngine`, not `didFinishLaunchingWithOptions`.
///   The implicit engine does not exist yet when the app delegate launches —
///   it is created when the scene connects — so `window?.rootViewController`
///   is nil there and the old `as? FlutterViewController` cast silently failed.
/// * URL handling moved to `SceneDelegate`. The previous
///   `application(_:open:options:)` override invoked `handleUrl` *into* Dart on
///   the plugin's channel, which nothing has ever handled — the example
///   receives registration callbacks through the `app_links` package instead.
///   All the override really did was call `super`, which the scene delegate now
///   does.
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
    registerDiagnosticsChannel(messenger: engineBridge.applicationRegistrar.messenger())
  }

  /// Exposes the process-wide `AVAudioSession` state to the example's UI.
  ///
  /// The plugin logs its audio route with `[MWDAT-ROUTE]`, but a console is not
  /// always reachable — release builds on a device connected wirelessly, a
  /// tester without Xcode, a Console.app that shows nothing. That diagnostic
  /// exists to be read in exactly those conditions, so the example surfaces it
  /// on screen instead.
  ///
  /// Deliberately implemented here rather than in the plugin: `sharedInstance()`
  /// is process-wide, so the host app can observe whatever the plugin
  /// configured without the plugin growing a public API for it.
  private func registerDiagnosticsChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "mwdat_example/diagnostics",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getAudioRoute":
        result(Self.audioRouteSnapshot())
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func audioRouteSnapshot() -> [String: Any] {
    let session = AVAudioSession.sharedInstance()
    let route = session.currentRoute
    let describe: ([AVAudioSessionPortDescription]) -> [String] = { ports in
      ports.map { "\($0.portType.rawValue):\($0.portName)" }
    }
    // A Bluetooth port on either side means the keep-alive is sharing the radio
    // the camera transport needs — the thing issue #31 is about.
    let all = route.inputs + route.outputs
    let usesBluetooth = all.contains { $0.portType.rawValue.lowercased().contains("bluetooth") }
    return [
      "inputs": describe(route.inputs),
      "outputs": describe(route.outputs),
      "category": session.category.rawValue,
      "mode": session.mode.rawValue,
      "usesBluetooth": usesBluetooth,
      "otherAudioPlaying": session.isOtherAudioPlaying,
    ]
  }
}
