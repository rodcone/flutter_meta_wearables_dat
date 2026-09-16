import CoreVideo

/// Hands out plugin-owned copies of the SDK's video frames.
///
/// The `raw` path used to give Flutter the `CVPixelBuffer` hanging off the
/// SDK's own `CMSampleBuffer`, which is the zero-copy thing to do and was wrong.
/// That buffer belongs to a pool inside the SDK, and the texture holds the
/// latest one until the next frame replaces it — plus one more retained by the
/// engine between `copyPixelBuffer()` and the render. Two of the SDK's buffers,
/// held indefinitely, on a pool we do not own and cannot size. When the capture
/// pipeline asks for a free buffer and finds none, it stops producing: no
/// error, no state change, `Stream.state` still `.streaming`, preview frozen
/// forever. That is the silent freeze.
///
/// Three things corroborate it. `hvc1` never froze, because VideoToolbox
/// decodes into its own buffers and the SDK's are released as soon as the frame
/// is processed. Android never froze either, because `FrameProcessor` converts
/// I420 into its own reusable bitmap and likewise retains nothing. And the
/// plugin's own dispatch queue was measured at a depth of one frame throughout,
/// so the backlog was never the problem — the *retention* was.
///
/// So: copy once, into a buffer we own, and give the SDK's back immediately.
/// That costs a memcpy per rendered frame — about 1.8 MB at 504x896, ~50 MB/s
/// at 28 fps — which is far less than the HEVC decode the `hvc1` path already
/// does happily. The pool means the allocation happens once rather than per
/// frame.
final class FramePixelBufferPool {
  private var pool: CVPixelBufferPool?
  private var width = 0
  private var height = 0
  private var format: OSType = 0

  /// Returns a plugin-owned copy of `source`, or nil if one could not be made.
  ///
  /// The caller must have finished with `source` by the time the returned
  /// buffer is handed on — that is the whole point.
  func copy(_ source: CVPixelBuffer) -> CVPixelBuffer? {
    let srcWidth = CVPixelBufferGetWidth(source)
    let srcHeight = CVPixelBufferGetHeight(source)
    let srcFormat = CVPixelBufferGetPixelFormatType(source)

    if pool == nil || srcWidth != width || srcHeight != height || srcFormat != format {
      guard makePool(width: srcWidth, height: srcHeight, format: srcFormat) else { return nil }
    }
    guard let pool else { return nil }

    var destination: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &destination) == kCVReturnSuccess,
          let destination else {
      // Our own pool is exhausted — the renderer is holding buffers faster than
      // it gives them back. Dropping this frame is correct: the alternative is
      // to start starving the SDK again, which is what this type exists to stop.
      MWDATLog.log("frame pixel-buffer pool exhausted — dropping frame")
      return nil
    }

    CVPixelBufferLockBaseAddress(source, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
    guard CVPixelBufferLockBaseAddress(destination, []) == kCVReturnSuccess else { return nil }
    defer { CVPixelBufferUnlockBaseAddress(destination, []) }

    guard copyPlanes(from: source, to: destination) else { return nil }
    return destination
  }

  /// Drops the pool. Called on teardown and on entering the background, so a
  /// stopped stream does not sit on a pool's worth of IOSurfaces.
  func invalidate() {
    pool = nil
    width = 0
    height = 0
    format = 0
  }

  private func makePool(width: Int, height: Int, format: OSType) -> Bool {
    // IOSurface-backed and Metal-compatible, because Flutter samples these on
    // the GPU. Without the IOSurface attribute the texture renders black.
    let attrs: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: format,
      kCVPixelBufferWidthKey as String: width,
      kCVPixelBufferHeightKey as String: height,
      kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
      kCVPixelBufferMetalCompatibilityKey as String: true,
    ]
    // Enough for the one the texture holds, the one the engine holds between
    // `copyPixelBuffer()` and the render, and one being written — plus slack.
    let poolAttrs: [String: Any] = [
      kCVPixelBufferPoolMinimumBufferCountKey as String: 4,
    ]

    var created: CVPixelBufferPool?
    let status = CVPixelBufferPoolCreate(
      nil,
      poolAttrs as CFDictionary,
      attrs as CFDictionary,
      &created
    )
    guard status == kCVReturnSuccess, let created else {
      MWDATLog.log("could not create frame pixel-buffer pool (status \(status))")
      return false
    }
    pool = created
    self.width = width
    self.height = height
    self.format = format
    return true
  }

  /// Copies plane by plane, honouring each plane's own stride. Handles both the
  /// packed formats (BGRA) and the planar ones (biplanar YUV) so this does not
  /// quietly corrupt a frame if the SDK's output format ever changes.
  private func copyPlanes(from source: CVPixelBuffer, to destination: CVPixelBuffer) -> Bool {
    if CVPixelBufferIsPlanar(source) {
      let planeCount = CVPixelBufferGetPlaneCount(source)
      guard CVPixelBufferGetPlaneCount(destination) == planeCount else { return false }
      for plane in 0..<planeCount {
        guard let src = CVPixelBufferGetBaseAddressOfPlane(source, plane),
              let dst = CVPixelBufferGetBaseAddressOfPlane(destination, plane) else { return false }
        let srcStride = CVPixelBufferGetBytesPerRowOfPlane(source, plane)
        let dstStride = CVPixelBufferGetBytesPerRowOfPlane(destination, plane)
        let rows = CVPixelBufferGetHeightOfPlane(source, plane)
        let bytes = min(srcStride, dstStride)
        copyRows(src: src, srcStride: srcStride, dst: dst, dstStride: dstStride, rows: rows, bytes: bytes)
      }
      return true
    }

    guard let src = CVPixelBufferGetBaseAddress(source),
          let dst = CVPixelBufferGetBaseAddress(destination) else { return false }
    let srcStride = CVPixelBufferGetBytesPerRow(source)
    let dstStride = CVPixelBufferGetBytesPerRow(destination)
    let rows = CVPixelBufferGetHeight(source)
    let bytes = min(srcStride, dstStride)
    copyRows(src: src, srcStride: srcStride, dst: dst, dstStride: dstStride, rows: rows, bytes: bytes)
    return true
  }

  /// A single `memcpy` when the strides match, row by row when they do not —
  /// the pool is free to pad rows differently from the SDK.
  private func copyRows(
    src: UnsafeMutableRawPointer,
    srcStride: Int,
    dst: UnsafeMutableRawPointer,
    dstStride: Int,
    rows: Int,
    bytes: Int
  ) {
    if srcStride == dstStride {
      memcpy(dst, src, srcStride * rows)
      return
    }
    for row in 0..<rows {
      memcpy(dst.advanced(by: row * dstStride), src.advanced(by: row * srcStride), bytes)
    }
  }
}
