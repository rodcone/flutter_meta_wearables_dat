import Foundation

/// The plugin's logging sink.
///
/// Exists because of a specific, verified interaction with `flutter run` rather
/// than as general tidiness.
///
/// `flutter_tools` launches iOS apps through `devicectl --console` and passes
/// `OS_ACTIVITY_DT_MODE=enable` expressly so that `NSLog` and `os_log` output is
/// mirrored into the stream it reads. It then discards most of it again with an
/// ignore filter (`flutter_tools/lib/src/ios/core_devices.dart`):
///
///     ^\S* \S* \S*\[[0-9:]*] ((?!(\[INFO|\[WARNING|\[ERROR|\[IMPORTANT|\[FATAL):))(?!(flutter:))…
///
/// `NSLog` emits `<date> <time> Runner[pid:tid] <message>`, which matches that
/// timestamp/process prefix, and `[MWDAT]` is on none of the whitelists — so
/// every plugin log line is dropped before it reaches the console. The comment
/// above that regex asserts `NSLog` arrives *without* a prefix; it does not, and
/// that is the whole bug. Swift's `print` writes to stdout with no prefix at all,
/// so it survives.
///
/// Verified on hardware: a `print` and an `NSLog` emitted back to back from
/// `AppLifecycleObserver.noteDidEnterBackground()` produced one console line and
/// zero, respectively.
///
/// Debug builds therefore use `print`, so logs appear in `flutter run` and Xcode.
/// Release builds use `NSLog`, so they reach the unified log where `log collect`
/// and Console.app can retrieve them for a field bug report. Deliberately *not*
/// both: Xcode's console shows stdout and the unified log, so emitting to both
/// double-prints every line.
enum MWDATLog {
  /// General plugin diagnostics. Tagged `[MWDAT]`.
  static func log(_ message: String) {
    emit("[MWDAT] \(message)")
  }

  /// Audio-route diagnostics. Tagged `[MWDAT-ROUTE]` so it stays greppable on its
  /// own — it is the line the troubleshooting docs tell people to look for, and
  /// it has twice been what identified a Bluetooth contention bug.
  static func route(_ message: String) {
    emit("[MWDAT-ROUTE] \(message)")
  }

  private static func emit(_ line: String) {
    #if DEBUG
    print(line)
    #else
    // `%@` rather than passing `line` as the format string: these messages
    // interpolate device names, error descriptions and SDK state, any of which
    // may contain a `%` that would otherwise be read as a format specifier.
    NSLog("%@", line)
    #endif
  }
}
