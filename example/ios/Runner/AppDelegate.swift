import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
