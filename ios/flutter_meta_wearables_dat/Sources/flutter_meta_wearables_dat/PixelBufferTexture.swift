import Flutter

/// A FlutterTexture backed by a CVPixelBuffer. When Flutter's rasteriser needs
/// a new frame it calls `copyPixelBuffer()` which returns the latest buffer
/// pushed from the native video-frame listener.
class PixelBufferTexture: NSObject, FlutterTexture {
  /// The latest pixel buffer to be rendered. Access is guarded by an
  /// unfair lock so the video-frame callback (main actor) and the raster
  /// thread (which calls `copyPixelBuffer`) never race.
  private var _latestPixelBuffer: CVPixelBuffer?
  private var lock = os_unfair_lock()

  var latestPixelBuffer: CVPixelBuffer? {
    get {
      os_unfair_lock_lock(&lock)
      let buf = _latestPixelBuffer
      os_unfair_lock_unlock(&lock)
      return buf
    }
    set {
      os_unfair_lock_lock(&lock)
      _latestPixelBuffer = newValue
      os_unfair_lock_unlock(&lock)
    }
  }

  func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
    os_unfair_lock_lock(&lock)
    let buf = _latestPixelBuffer
    os_unfair_lock_unlock(&lock)
    guard let buf else { return nil }
    return Unmanaged.passRetained(buf)
  }
}
