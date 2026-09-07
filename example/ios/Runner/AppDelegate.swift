import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    #if DEBUG
    NativeLogForwarder.install()
    #endif
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

#if DEBUG
/// Makes the plugin's `[MWDAT]` NSLog lines visible in `flutter run`.
///
/// flutter_tools reads the app's stdout and stderr through `devicectl --console`
/// and then drops every line that carries NSLog's `<date> <time> Runner[pid:tid]`
/// prefix unless it is whitelisted (`flutter_tools/lib/src/ios/core_devices.dart`).
/// Plain stdout lines have no such prefix and survive. This tee moves stderr onto
/// a pipe, passes everything through to the original stderr, and re-emits any
/// `[MWDAT` line on stdout with the prefix stripped. The unified-log copy that
/// NSLog also writes is unaffected, so Console.app and `log collect` still work.
///
/// Debug builds only, and only the example app: consumers see nothing of this.
private enum NativeLogForwarder {
  static func install() {
    var fds: [Int32] = [0, 0]
    guard pipe(&fds) == 0 else { return }
    let originalStderr = dup(STDERR_FILENO)
    dup2(fds[1], STDERR_FILENO)
    close(fds[1])
    let readEnd = fds[0]
    Thread.detachNewThread {
      var pending = Data()
      var buffer = [UInt8](repeating: 0, count: 4096)
      while true {
        let count = read(readEnd, &buffer, buffer.count)
        if count <= 0 { return }
        pending.append(buffer, count: count)
        while let newline = pending.firstIndex(of: 0x0A) {
          let line = pending.subdata(in: pending.startIndex...newline)
          pending.removeSubrange(pending.startIndex...newline)
          emit(line, to: originalStderr)
          guard let text = String(data: line, encoding: .utf8),
                let tag = text.range(of: "[MWDAT") else { continue }
          emit(Data(text[tag.lowerBound...].utf8), to: STDOUT_FILENO)
        }
      }
    }
  }

  /// POSIX `write`, errors ignored: `FileHandle.write` raises an ObjC exception
  /// when the console pipe has gone away, and Swift cannot catch that.
  private static func emit(_ data: Data, to fd: Int32) {
    data.withUnsafeBytes { raw in
      guard let base = raw.baseAddress else { return }
      _ = write(fd, base, raw.count)
    }
  }
}
#endif
