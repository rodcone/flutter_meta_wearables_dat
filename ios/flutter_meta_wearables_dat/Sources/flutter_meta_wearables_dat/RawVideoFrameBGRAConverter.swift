import Accelerate
import CoreVideo
import Foundation

/// Converts DAT's raw camera frames into the public iOS frame-stream layout.
///
/// DAT documents `VideoCodec.raw` as 420v bi-planar YUV. The Dart API has
/// always promised BGRA, so copying the source buffer's top-level base address
/// is not valid: a planar buffer has independent plane strides and is not
/// packed BGRA memory. Convert synchronously while the SDK callback owns the
/// source, writing directly into the `Data` that Flutter will own.
///
/// Accelerate's CPU conversion is deliberate. Raw frame events may be consumed
/// while background streaming is enabled, where GPU-backed conversion is not a
/// safe assumption. Calls are serialized by `MetaWearablesDatPlugin.frameQueue`;
/// this type is intentionally not internally synchronized.
final class RawVideoFrameBGRAConverter {
  struct Frame {
    let bytes: Data
    let width: Int
    let height: Int
    let bytesPerRow: Int
  }

  private enum MatrixKind: String, Equatable {
    case itu601 = "ITU-R 601"
    case itu709 = "ITU-R 709"
  }

  private struct ConversionKey: Equatable {
    let fullRange: Bool
    let matrix: MatrixKind
  }

  private var conversionKey: ConversionKey?
  private var conversionInfo: vImage_YpCbCrToARGB?
  private var lastLoggedSignature = ""
  private var failureCount = 0

  func convert(_ source: CVPixelBuffer) -> Frame? {
    let format = CVPixelBufferGetPixelFormatType(source)
    let width = CVPixelBufferGetWidth(source)
    let height = CVPixelBufferGetHeight(source)

    guard CVPixelBufferLockBaseAddress(source, .readOnly) == kCVReturnSuccess else {
      noteFailure("could not lock raw buffer", sourceFormat: format)
      return nil
    }
    defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }

    if format == kCVPixelFormatType_32BGRA {
      return copyPackedBGRA(source, width: width, height: height)
    }

    let fullRange: Bool
    switch format {
    case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
      fullRange = false
    case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
      fullRange = true
    default:
      noteFailure("unsupported raw pixel format", sourceFormat: format)
      return nil
    }

    guard CVPixelBufferIsPlanar(source),
          CVPixelBufferGetPlaneCount(source) == 2,
          let yAddress = CVPixelBufferGetBaseAddressOfPlane(source, 0),
          let cbCrAddress = CVPixelBufferGetBaseAddressOfPlane(source, 1) else {
      noteFailure("invalid bi-planar YUV layout", sourceFormat: format)
      return nil
    }

    let matrix = matrixKind(for: source)
    guard var info = conversionInfo(fullRange: fullRange, matrix: matrix) else {
      noteFailure("could not prepare YUV conversion", sourceFormat: format)
      return nil
    }

    let outputStride = width * 4
    var output = Data(count: outputStride * height)
    var yPlane = vImage_Buffer(
      data: yAddress,
      height: vImagePixelCount(CVPixelBufferGetHeightOfPlane(source, 0)),
      width: vImagePixelCount(CVPixelBufferGetWidthOfPlane(source, 0)),
      rowBytes: CVPixelBufferGetBytesPerRowOfPlane(source, 0)
    )
    var cbCrPlane = vImage_Buffer(
      data: cbCrAddress,
      height: vImagePixelCount(CVPixelBufferGetHeightOfPlane(source, 1)),
      width: vImagePixelCount(CVPixelBufferGetWidthOfPlane(source, 1)),
      rowBytes: CVPixelBufferGetBytesPerRowOfPlane(source, 1)
    )
    let conversionError = output.withUnsafeMutableBytes { outputBytes -> vImage_Error in
      guard let outputAddress = outputBytes.baseAddress else {
        return kvImageMemoryAllocationError
      }
      var destination = vImage_Buffer(
        data: outputAddress,
        height: vImagePixelCount(height),
        width: vImagePixelCount(width),
        rowBytes: outputStride
      )
      // vImage produces ARGB internally; this permutation writes BGRA bytes.
      let permutation: [UInt8] = [3, 2, 1, 0]
      return permutation.withUnsafeBufferPointer { permutationPointer in
        vImageConvert_420Yp8_CbCr8ToARGB8888(
          &yPlane,
          &cbCrPlane,
          &destination,
          &info,
          permutationPointer.baseAddress,
          255,
          vImage_Flags(kvImageNoFlags)
        )
      }
    }
    guard conversionError == kvImageNoError else {
      noteFailure(
        "YUV-to-BGRA conversion failed (status \(conversionError))",
        sourceFormat: format
      )
      return nil
    }

    logLayoutIfNeeded(
      source: source,
      sourceFormat: format,
      width: width,
      height: height,
      matrix: matrix,
      fullRange: fullRange,
      outputStride: outputStride,
      outputBytes: output.count
    )
    return Frame(
      bytes: output,
      width: width,
      height: height,
      bytesPerRow: outputStride
    )
  }

  func reset() {
    conversionKey = nil
    conversionInfo = nil
    lastLoggedSignature = ""
    failureCount = 0
  }

  private func copyPackedBGRA(
    _ source: CVPixelBuffer,
    width: Int,
    height: Int
  ) -> Frame? {
    let stride = CVPixelBufferGetBytesPerRow(source)
    guard stride >= width * 4,
          let address = CVPixelBufferGetBaseAddress(source) else {
      noteFailure(
        "invalid packed BGRA layout",
        sourceFormat: CVPixelBufferGetPixelFormatType(source)
      )
      return nil
    }
    let byteCount = stride * height
    logLayoutIfNeeded(
      source: source,
      sourceFormat: kCVPixelFormatType_32BGRA,
      width: width,
      height: height,
      matrix: .itu709,
      fullRange: true,
      outputStride: stride,
      outputBytes: byteCount
    )
    return Frame(
      bytes: Data(bytes: address, count: byteCount),
      width: width,
      height: height,
      bytesPerRow: stride
    )
  }

  private func conversionInfo(
    fullRange: Bool,
    matrix: MatrixKind
  ) -> vImage_YpCbCrToARGB? {
    let key = ConversionKey(fullRange: fullRange, matrix: matrix)
    if key == conversionKey, let conversionInfo {
      return conversionInfo
    }

    var pixelRange = fullRange
      ? vImage_YpCbCrPixelRange(
          Yp_bias: 0,
          CbCr_bias: 128,
          YpRangeMax: 255,
          CbCrRangeMax: 255,
          YpMax: 255,
          YpMin: 1,
          CbCrMax: 255,
          CbCrMin: 0
        )
      : vImage_YpCbCrPixelRange(
          Yp_bias: 16,
          CbCr_bias: 128,
          YpRangeMax: 235,
          CbCrRangeMax: 240,
          YpMax: 255,
          YpMin: 0,
          CbCrMax: 255,
          CbCrMin: 1
        )
    guard let conversionMatrix = matrix == .itu601
      ? kvImage_YpCbCrToARGBMatrix_ITU_R_601_4
      : kvImage_YpCbCrToARGBMatrix_ITU_R_709_2 else {
      return nil
    }
    var info = vImage_YpCbCrToARGB()
    let error = vImageConvert_YpCbCrToARGB_GenerateConversion(
      conversionMatrix,
      &pixelRange,
      &info,
      kvImage420Yp8_CbCr8,
      kvImageARGB8888,
      vImage_Flags(kvImageNoFlags)
    )
    guard error == kvImageNoError else { return nil }
    conversionKey = key
    conversionInfo = info
    return info
  }

  private func matrixKind(for source: CVPixelBuffer) -> MatrixKind {
    guard let attachments = CVBufferCopyAttachments(source, .shouldPropagate)
            as? [CFString: Any],
          let value = attachments[kCVImageBufferYCbCrMatrixKey] as? String else {
      return .itu709
    }
    if value == kCVImageBufferYCbCrMatrix_ITU_R_601_4 as String {
      return .itu601
    }
    return .itu709
  }

  private func logLayoutIfNeeded(
    source: CVPixelBuffer,
    sourceFormat: OSType,
    width: Int,
    height: Int,
    matrix: MatrixKind,
    fullRange: Bool,
    outputStride: Int,
    outputBytes: Int
  ) {
    let planeCount = CVPixelBufferIsPlanar(source)
      ? CVPixelBufferGetPlaneCount(source)
      : 0
    let signature = "\(sourceFormat)-\(width)x\(height)-\(planeCount)-\(outputStride)"
    guard signature != lastLoggedSignature else { return }
    lastLoggedSignature = signature

    let planes: String
    if planeCount == 0 {
      planes = "packed stride \(CVPixelBufferGetBytesPerRow(source))"
    } else {
      planes = (0..<planeCount).map { plane in
        "p\(plane)=\(CVPixelBufferGetBytesPerRowOfPlane(source, plane))x"
          + "\(CVPixelBufferGetHeightOfPlane(source, plane))"
      }.joined(separator: ", ")
    }

    NSLog(
      "[MWDAT] video_frames raw layout: source \(Self.fourCC(sourceFormat)) "
        + "\(width)x\(height), \(planes), \(matrix.rawValue), "
        + "\(fullRange ? "full" : "video") range; output BGRA stride "
        + "\(outputStride), bytes \(outputBytes)")
  }

  private func noteFailure(_ reason: String, sourceFormat: OSType) {
    failureCount += 1
    if failureCount == 1 || failureCount % 30 == 0 {
      NSLog(
        "[MWDAT] video_frames: \(reason), source \(Self.fourCC(sourceFormat)); "
          + "dropped \(failureCount) raw frame(s)")
    }
  }

  private static func fourCC(_ value: OSType) -> String {
    let bytes: [UInt8] = [
      UInt8((value >> 24) & 0xff),
      UInt8((value >> 16) & 0xff),
      UInt8((value >> 8) & 0xff),
      UInt8(value & 0xff),
    ]
    if bytes.allSatisfy({ $0 >= 32 && $0 <= 126 }) {
      return String(bytes: bytes, encoding: .ascii) ?? String(format: "0x%08X", value)
    }
    return String(format: "0x%08X", value)
  }
}
