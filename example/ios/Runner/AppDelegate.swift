import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    registerDiagnosticsChannel()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
  private func registerDiagnosticsChannel() {
    guard let controller = window?.rootViewController as? FlutterViewController else {
      NSLog("[AppDelegate] No FlutterViewController — diagnostics channel not registered")
      return
    }
    let channel = FlutterMethodChannel(
      name: "mwdat_example/diagnostics",
      binaryMessenger: controller.binaryMessenger
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

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    // Check if Flutter is ready
    guard let controller = window?.rootViewController as? FlutterViewController else {
      // Flutter not ready yet, try to handle URL natively
      NSLog("[AppDelegate] Flutter not ready, handling URL natively: \(url.absoluteString)")
      return super.application(app, open: url, options: options)
    }
    
    let channel = FlutterMethodChannel(name: "flutter_meta_wearables_dat", binaryMessenger: controller.binaryMessenger)
    channel.invokeMethod("handleUrl", arguments: ["url": url.absoluteString]) { result in
      if let error = result as? FlutterError {
        NSLog("[AppDelegate] Failed to handle route information in Flutter: \(error.message ?? "Unknown error"), code: \(error.code)")
      } else if let handled = result as? Bool {
        if handled {
          NSLog("[AppDelegate] Successfully handled URL: \(url.absoluteString)")
        } else {
          NSLog("[AppDelegate] URL was not handled: \(url.absoluteString)")
        }
      }
    }
    return super.application(app, open: url, options: options)
  }
}
