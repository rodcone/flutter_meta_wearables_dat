import Flutter
import UIKit
import MWDATCore
import MWDATCamera
import AVFoundation
import CoreMedia
import VideoToolbox

public class MetaWearablesDatPlugin: NSObject, FlutterPlugin {
  // Device session (DAT 0.7.0): created lazily on first startStreamSession
  // call using the shared AutoDeviceSelector. Kept alive across stream
  // start/stop so toggling streaming is fast. Torn down only when the
  // underlying device disappears or when the plugin is disabled.
  private lazy var deviceSelector: AutoDeviceSelector = {
    AutoDeviceSelector(wearables: Wearables.shared)
  }()
  private var deviceSession: DeviceSession?
  private var deviceSessionStateTask: Task<Void, Never>?
  private var deviceSessionErrorTask: Task<Void, Never>?
  private var deviceAvailabilityTask: Task<Void, Never>?

  // Stream session state (single session at a time)
  private var streamSession: MWDATCamera.Stream?
  private var videoListenerToken: (any MWDATCore.AnyListenerToken)?
  private var errorListenerToken: (any MWDATCore.AnyListenerToken)?
  private var frameCounter: Int = 0
  private var currentTargetFPS: Double = 30.0
  private var lastFrameSendTime: Date?
  private var pixelBufferTexture: PixelBufferTexture?
  private var textureId: Int64?
  private var currentVideoCodec: MWDATCamera.VideoCodec = .raw
  private var decompressionSession: VTDecompressionSession?
  // Background/foreground state — gates frame processing and decoder lifecycle
  private var isInBackground: Bool = false
  // Texture registry
  private var textureRegistry: FlutterTextureRegistry?
  // Stream event handlers
  private var streamStateHandler = StreamStateStreamHandler()
  private var streamErrorHandler = StreamErrorStreamHandler()
  private var videoStreamSizeHandler = VideoStreamSizeStreamHandler()

  // Background streaming — opt-in AVAudioSession keep-alive + software
  // decoder mode. When enabled, the plugin keeps the decoder alive across
  // foreground/background transitions and keeps emitting frames to the
  // video_frames event channel regardless of UI visibility.
  private let backgroundController = BackgroundStreamingController()
  private let videoFrameHandler = VideoFrameStreamHandler()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_meta_wearables_dat", binaryMessenger: registrar.messenger())
    let instance = MetaWearablesDatPlugin()
    instance.textureRegistry = registrar.textures()
    registrar.addMethodCallDelegate(instance, channel: channel)
    // Receive applicationDidEnterBackground / applicationWillEnterForeground
    // callbacks so we can safely manage the hvc1 HEVC decoder across app
    // lifecycle transitions (iOS forbids GPU access from backgrounded apps).
    registrar.addApplicationDelegate(instance)
    // Event channel for registration state updates
    let registrationStateChannel = FlutterEventChannel(name: "flutter_meta_wearables_dat/registration_state", binaryMessenger: registrar.messenger())
    registrationStateChannel.setStreamHandler(RegistrationStateStreamHandler())
    // Event channel for active device availability updates
    let activeDeviceChannel = FlutterEventChannel(name: "flutter_meta_wearables_dat/active_device", binaryMessenger: registrar.messenger())
    activeDeviceChannel.setStreamHandler(ActiveDeviceStreamHandler(deviceSelectorProvider: { [weak instance] in
      // Fall back to a fresh selector only if the plugin has been torn down —
      // in normal operation the shared instance is always used so the active
      // device state is seeded without re-discovery.
      instance?.deviceSelector ?? AutoDeviceSelector(wearables: Wearables.shared)
    }))
    // Event channels for stream session state and errors
    let streamStateChannel = FlutterEventChannel(name: "flutter_meta_wearables_dat/stream_session_state", binaryMessenger: registrar.messenger())
    streamStateChannel.setStreamHandler(instance.streamStateHandler)
    let streamErrorChannel = FlutterEventChannel(name: "flutter_meta_wearables_dat/stream_session_errors", binaryMessenger: registrar.messenger())
    streamErrorChannel.setStreamHandler(instance.streamErrorHandler)
    // Event channel for video frame dimensions (used by Dart to drive AspectRatio).
    let videoStreamSizeChannel = FlutterEventChannel(name: "flutter_meta_wearables_dat/video_stream_size", binaryMessenger: registrar.messenger())
    videoStreamSizeChannel.setStreamHandler(instance.videoStreamSizeHandler)
    // Event channel for per-frame video samples. Serialization is skipped
    // entirely when no subscriber is attached, so this is zero-cost for apps
    // that don't opt in to background streaming.
    let videoFramesChannel = FlutterEventChannel(name: "flutter_meta_wearables_dat/video_frames", binaryMessenger: registrar.messenger())
    videoFramesChannel.setStreamHandler(instance.videoFrameHandler)
    // Event channel for per-device state (thermal level). Tracks the active
    // device and switches subscription on device change.
    let deviceStateChannel = FlutterEventChannel(name: "flutter_meta_wearables_dat/device_state", binaryMessenger: registrar.messenger())
    deviceStateChannel.setStreamHandler(DeviceStateStreamHandler(deviceSelectorProvider: { [weak instance] in
      instance?.deviceSelector ?? AutoDeviceSelector(wearables: Wearables.shared)
    }))

    Task { @MainActor in
      try? Wearables.configure()
      instance.startDeviceAvailabilityMonitoring()
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
      case "requestAndroidPermissions":
        // No-op on iOS — Android-only runtime permissions
        result(true)
      case "restartActiveDeviceMonitoring":
        // No-op on iOS — Android-only workaround for device flow timing
        result(true)
      case "startRegistration":
        startRegistration(result: result)
      case "disconnect":
        disconnect(result: result)
      case "handleUrl":
        handleUrl(call: call, result: result)
      case "getCameraPermissionStatus":
        getCameraPermissionStatus(result: result)
      case "requestCameraPermission":
        requestCameraPermission(result: result)
      case "startStreamSession":
        startStreamSession(call: call, result: result)
      case "stopStreamSession":
        stopStreamSession(call: call, result: result)
      case "capturePhoto":
        capturePhoto(call: call, result: result)
      case "getRegistrationState":
        getRegistrationState(result: result)
      case "enableBackgroundStreaming":
        enableBackgroundStreaming(result: result)
      case "disableBackgroundStreaming":
        disableBackgroundStreaming(result: result)
      case "openDATGlassesAppUpdate":
        openDATGlassesAppUpdate(result: result)
      default:
        result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Navigation APIs (0.7.0)

  /// Opens the Meta AI app to the DAT-app-update screen for the connected
  /// glasses. The companion to the `datAppOnTheGlassesUpdateRequired`
  /// `DeviceSessionError` surfaced on `streamSessionErrorStream()` — apps
  /// receiving that error should call this method to prompt the user to
  /// update the on-device DAT app before retrying.
  private func openDATGlassesAppUpdate(result: @escaping FlutterResult) {
    Task { @MainActor in
      do {
        try await Wearables.shared.openDATGlassesAppUpdate()
        result(true)
      } catch let e as MWDATCore.NavigationError {
        let code: String
        let message: String
        switch e {
        case .metaAINotInstalled:
          code = "metaAINotInstalled"
          message = "Meta AI app is not installed. Please install it to update the glasses app."
        case .notRegistered:
          code = "notRegistered"
          message = "App is not registered with Meta AI glasses. Complete registration first."
        @unknown default:
          code = "unknown"
          message = "Unknown navigation error: \(e)"
        }
        result(FlutterError(code: code, message: message, details: e.rawValue))
      } catch {
        result(FlutterError(code: "NAVIGATION_ERROR", message: error.localizedDescription, details: nil))
      }
    }
  }

  // MARK: - Background streaming

  private func enableBackgroundStreaming(result: @escaping FlutterResult) {
    do {
      try backgroundController.enable()
      result(nil)
    } catch {
      result(FlutterError(
        code: "BACKGROUND_STREAMING_ERROR",
        message: "Failed to enable background streaming: \(error.localizedDescription). Verify the host app's Info.plist declares the 'audio' UIBackgroundMode.",
        details: nil
      ))
    }
  }

  private func disableBackgroundStreaming(result: @escaping FlutterResult) {
    backgroundController.disable()
    result(nil)
  }

  // MARK: - Permissions

  func requestCameraPermission(result: @escaping FlutterResult) {
    Task { @MainActor in
      do {
        let currentStatus = try await Wearables.shared.checkPermissionStatus(.camera)
        if currentStatus == .granted {
          result(true)
          return
        }

        let status = try await Wearables.shared.requestPermission(.camera)
        // Convert PermissionStatus enum to Bool for Flutter
        let granted = status == .granted
        result(granted)
      } catch let e as MWDATCore.PermissionError {
        let code = Self.mapPermissionError(e)
        result(FlutterError(
          code: code,
          message: e.description,
          details: ["errorType": String(describing: e), "rawValue": e.rawValue]
        ))
      } catch {
        result(FlutterError(code: "INTERNAL_ERROR", message: error.localizedDescription, details: nil))
      }
    }
  }

  /// Map an SDK `PermissionError` to one of the typed codes that
  /// `CameraPermissionException` predicates on the Dart side. `PERMISSION_DENIED`
  /// is reserved for the case where a user explicitly declines the request — the
  /// SDK doesn't surface that as an error (it returns `.denied`), so it's never
  /// emitted here.
  private static func mapPermissionError(_ e: MWDATCore.PermissionError) -> String {
    switch e {
    case .noDevice, .noDeviceWithConnection, .connectionError:
      return "DEVICE_DISCONNECTED"
    case .metaAINotInstalled, .requestInProgress, .requestTimeout, .internalError:
      return "INTERNAL_ERROR"
    @unknown default:
      return "INTERNAL_ERROR"
    }
  }

  func getCameraPermissionStatus(result: @escaping FlutterResult) {
    Task { @MainActor in
      do {
        let status = try await Wearables.shared.checkPermissionStatus(.camera)
        result(status == .granted)
      } catch is MWDATCore.PermissionError {
        // Permission not granted yet or denied — return false instead of error
        result(false)
      } catch {
        result(FlutterError(code: "INTERNAL_ERROR", message: error.localizedDescription, details: nil))
      }
    }
  }

  // MARK: - Registration

  func startRegistration(result: @escaping FlutterResult) {
    Task { @MainActor in
      do {
        try await Wearables.shared.startRegistration()
        result(true)
      } catch let e as MWDATCore.RegistrationError {
        let errorMessage: String
        switch e {
        case .alreadyRegistered:
          errorMessage = "User is already registered. Registration is not needed."
        case .configurationInvalid:
          errorMessage = "SDK configuration is invalid or incomplete."
        case .metaAINotInstalled:
          errorMessage = "Meta AI app is not installed. Please install it to proceed with registration."
        case .networkUnavailable:
          errorMessage = "Network connection is unavailable. Please check your internet connection and try again."
        case .unknown:
          errorMessage = "An unknown error occurred during registration."
        @unknown default:
          errorMessage = "Unknown registration error: \(e)"
        }
        result(FlutterError(code: "REGISTRATION_ERROR", message: errorMessage, details: e.rawValue))
      } catch {
        result(FlutterError(code: "REGISTRATION_ERROR", message: error.localizedDescription, details: nil))
      }
    }
  }

  func disconnect(result: @escaping FlutterResult) {
    Task { @MainActor in
      do {
        try await Wearables.shared.startUnregistration()
        result(true)
      } catch let e as MWDATCore.UnregistrationError {
        let errorMessage: String
        switch e {
        case .alreadyUnregistered:
          errorMessage = "User is already unregistered."
        case .configurationInvalid:
          errorMessage = "SDK configuration is invalid or incomplete."
        case .metaAINotInstalled:
          errorMessage = "Meta AI app is not installed. Please install it to proceed with unregistration."
        case .unknown:
          errorMessage = "An unknown error occurred during unregistration."
        @unknown default:
          errorMessage = "Unknown unregistration error: \(e)"
        }
        result(FlutterError(code: "UNREGISTRATION_ERROR", message: errorMessage, details: e.rawValue))
      } catch {
        result(FlutterError(code: "UNREGISTRATION_ERROR", message: error.localizedDescription, details: nil))
      }
    }
  }

  func handleUrl(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String : Any], let urlString = args["url"] as? String else {
      result(FlutterError(code: "INVALID_ARGS", message: "url missing", details: nil))
      return
    }

    guard let url = URL(string: urlString) else {
      result(FlutterError(code: "INVALID_URL", message: "Could not parse URL: \(urlString)", details: nil))
      return
    }

    Task { @MainActor in
      do {
        let handled = try await Wearables.shared.handleUrl(url)
        result(handled)
      } catch let e as MWDATCore.RegistrationError {
        result(FlutterError(code: "REGISTRATION_ERROR", message: "\(e)", details: e.rawValue))
      } catch {
        result(FlutterError(code: "HANDLE_URL_ERROR", message: error.localizedDescription, details: nil))
      }
    }
  }

  // MARK: - Session Lifecycle

  /// Monitors `activeDeviceStream` and tears the DeviceSession down whenever
  /// the active device becomes `nil`. Launched once in `register`.
  @MainActor
  private func startDeviceAvailabilityMonitoring() {
    deviceAvailabilityTask?.cancel()
    deviceAvailabilityTask = Task { [weak self] in
      guard let self else { return }
      for await deviceId in self.deviceSelector.activeDeviceStream() {
        if deviceId == nil {
          await self.teardownDeviceSession()
        }
      }
    }
  }

  /// Returns a DeviceSession in `.started` state, creating one if needed.
  /// Mirrors the pattern in Meta's CameraAccess sample (DeviceSessionManager).
  @MainActor
  private func ensureDeviceSessionStarted() async throws -> DeviceSession {
    if let existing = deviceSession, existing.state == .started {
      return existing
    }

    // Drop stale/stopped sessions — `.stopped` is terminal.
    if let existing = deviceSession, existing.state == .stopped {
      await teardownDeviceSession()
    }

    if deviceSession == nil {
      let session = try Wearables.shared.createSession(deviceSelector: deviceSelector)
      deviceSession = session
      observeDeviceSession(session)
      // Capture the state stream BEFORE start() so we don't miss transitions.
      let stateStream = session.stateStream()
      try session.start()

      for await state in stateStream {
        if state == .started {
          return session
        }
        if state == .stopped {
          // Terminal failure before ever reaching .started
          deviceSession = nil
          throw DeviceSessionError.noEligibleDevice
        }
      }
      // Stream ended without reaching .started
      deviceSession = nil
      throw DeviceSessionError.unexpectedError(description: "Device session state stream ended before reaching .started")
    }

    // Session exists but not yet .started — wait for it.
    guard let session = deviceSession else {
      throw DeviceSessionError.noEligibleDevice
    }
    for await state in session.stateStream() {
      if state == .started { return session }
      if state == .stopped {
        deviceSession = nil
        throw DeviceSessionError.noEligibleDevice
      }
    }
    throw DeviceSessionError.unexpectedError(description: "Device session state stream ended")
  }

  /// Observes the DeviceSession's state and error streams so we can react to
  /// terminal failures and forward errors to Dart.
  @MainActor
  private func observeDeviceSession(_ session: DeviceSession) {
    deviceSessionStateTask?.cancel()
    deviceSessionStateTask = Task { [weak self] in
      for await state in session.stateStream() {
        guard let self else { return }
        if state == .stopped {
          // DeviceSession stopped externally — tear down associated stream
          // and drop our reference. A fresh session is created on demand.
          await self.teardownStreamOnly()
          self.deviceSession = nil
          self.deviceSessionStateTask?.cancel()
          self.deviceSessionStateTask = nil
          self.deviceSessionErrorTask?.cancel()
          self.deviceSessionErrorTask = nil
          return
        }
      }
    }

    deviceSessionErrorTask?.cancel()
    deviceSessionErrorTask = Task { [weak self] in
      for await error in session.errorStream() {
        self?.streamErrorHandler.send(deviceSessionError: error)
      }
    }
  }

  /// Tears down the active stream but leaves the DeviceSession alive, so the
  /// next `startStreamSession` is a fast `addStream` on the existing session.
  @MainActor
  private func teardownStreamOnly() async {
    if let token = videoListenerToken {
      await token.cancel()
      videoListenerToken = nil
    }
    if let token = errorListenerToken {
      await token.cancel()
      errorListenerToken = nil
    }
    streamStateHandler.session = nil
    streamErrorHandler.session = nil
    if let session = streamSession {
      await session.stop()
      streamSession = nil
    }
    if let texId = textureId {
      textureRegistry?.unregisterTexture(texId)
      NSLog("[MWDAT] Unregistered texture \(texId)")
      textureId = nil
      pixelBufferTexture = nil
    }
    if let session = decompressionSession {
      VTDecompressionSessionInvalidate(session)
      decompressionSession = nil
    }
    frameCounter = 0
    lastFrameSendTime = nil
    videoStreamSizeHandler.reset()
  }

  /// Tears down both stream and DeviceSession. Used when the device
  /// disconnects, when mock devices are disabled, or when a new mock
  /// config is applied.
  @MainActor
  private func teardownDeviceSession() async {
    await teardownStreamOnly()
    deviceSessionStateTask?.cancel()
    deviceSessionStateTask = nil
    deviceSessionErrorTask?.cancel()
    deviceSessionErrorTask = nil
    if let session = deviceSession {
      session.stop()
      deviceSession = nil
    }
  }

  // MARK: - App Lifecycle (background safety for hvc1 codec)
  //
  // iOS forbids GPU access from backgrounded apps. The Meta DAT SDK keeps
  // delivering hvc1 CMSampleBuffers in background (CPU-only CMBlockBuffer)
  // when background streaming is enabled, but decoding them via
  // VTDecompressionSession produces GPU-backed CVPixelBuffers which iOS
  // can't render anyway (no Flutter raster thread, no Metal access).
  //
  // Strategy: invalidate the decoder unconditionally on background. While
  // backgrounded with background streaming on, we still forward the raw
  // hvc1 NAL bytes to `videoFramesStream()` (useful for recording to disk)
  // but skip decode + texture. The decoder is lazily recreated on the
  // first frame after foreground.
  //
  // An earlier design forced *software* HEVC decoding while bg streaming
  // was on, with the aim of keeping the decoder alive across the
  // background→foreground transition. In practice the software decoder
  // produced grey / corrupted output even in foreground, so the design
  // was reverted: hardware decoder only, always invalidated on background.

  public func applicationDidEnterBackground(_ application: UIApplication) {
    isInBackground = true
    if let session = decompressionSession {
      VTDecompressionSessionInvalidate(session)
      decompressionSession = nil
      NSLog("[MWDAT] VTDecompressionSession invalidated (app entered background)")
    }
  }

  public func applicationWillEnterForeground(_ application: UIApplication) {
    isInBackground = false
    NSLog("[MWDAT] App entering foreground — HEVC decoder will be recreated on next frame")
  }

  // MARK: - Frame Processing (zero-copy via Texture API)
  /// Pushes a CVPixelBuffer extracted from the VideoFrame's CMSampleBuffer
  /// directly to the Flutter texture — no JPEG encode/decode, no byte copy.
  private func processAndSendFrame(_ videoFrame: VideoFrame) {
    // When background streaming is NOT enabled, keep the existing behaviour:
    // drop every frame while backgrounded, since iOS forbids GPU access and
    // the Flutter raster thread is suspended.
    if isInBackground && !backgroundController.isEnabled {
      return
    }

    let pts = CMSampleBufferGetPresentationTimeStamp(videoFrame.sampleBuffer)
    let ptsUs: Int64 = pts.isValid ? Int64(CMTimeGetSeconds(pts) * 1_000_000) : 0

    // Forward the hvc1 compressed sample to Dart BEFORE decoding — this lets
    // apps record the raw bitstream even when no decode path is needed (e.g.
    // no texture subscriber, or we're backgrounded with no GPU access).
    if currentVideoCodec == .hvc1, videoFrameHandler.hasListener {
      videoFrameHandler.emitHvc1(sampleBuffer: videoFrame.sampleBuffer, ptsUs: ptsUs)
    }

    // While backgrounded with bg streaming on (the only way we reach here in
    // background — the earlier guard returns otherwise), forward the raw
    // hvc1 NAL bytes above for recording but skip decode + texture. iOS
    // forbids GPU access from backgrounded apps, the decoder was already
    // invalidated on the background transition, and there's no Flutter raster
    // thread to render to. The decoder is lazily recreated on the first
    // frame after foreground (see `decodeCompressedFrame`).
    if isInBackground {
      return
    }

    let now = Date()
    let minInterval = 1.0 / currentTargetFPS

    let timeSinceLastFrame: TimeInterval
    if let lastSendTime = lastFrameSendTime {
      timeSinceLastFrame = now.timeIntervalSince(lastSendTime)
      if timeSinceLastFrame < minInterval {
        return // throttle
      }
    } else {
      timeSinceLastFrame = 0
    }

    // Get pixel buffer: direct extraction for raw, decode for hvc1
    let pixelBuffer: CVPixelBuffer?
    if currentVideoCodec == .raw {
      pixelBuffer = CMSampleBufferGetImageBuffer(videoFrame.sampleBuffer)
    } else {
      pixelBuffer = decodeCompressedFrame(videoFrame.sampleBuffer)
    }

    guard let pixelBuffer else {
      NSLog("[MWDAT] Could not obtain pixel buffer from video frame")
      return
    }

    // Emit the decoded raw BGRA pixels to the video_frames event channel so
    // Dart subscribers (e.g. recorders) can access every frame. Guarded on
    // hasListener so we don't memcpy for apps that don't opt in.
    if currentVideoCodec == .raw, videoFrameHandler.hasListener {
      videoFrameHandler.emitRaw(pixelBuffer: pixelBuffer, ptsUs: ptsUs)
    }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    videoStreamSizeHandler.send(width: width, height: height)

    // Update timing + counters regardless of whether we push to the texture.
    lastFrameSendTime = now
    frameCounter += 1

    if frameCounter % 30 == 0 && timeSinceLastFrame > 0 {
      let actualFPS = 1.0 / timeSinceLastFrame
      NSLog("[MWDAT] \(frameCounter) frames, target: \(currentTargetFPS), actual: \(String(format: "%.1f", actualFPS)) FPS")
    }

    guard let texture = pixelBufferTexture,
          let texId = textureId else {
      return
    }

    texture.latestPixelBuffer = pixelBuffer
    textureRegistry?.textureFrameAvailable(texId)
  }

  // MARK: - HEVC Decompression (for hvc1 codec)

  /// Creates a VTDecompressionSession for decoding HEVC frames to BGRA pixel
  /// buffers. The output attrs explicitly request IOSurface + Metal-compatible
  /// buffers so Flutter's `Texture` widget can sample them on the GPU
  /// (a sanity belt-and-braces — the hardware decoder produces these by
  /// default, but stating it is harmless and future-proof).
  ///
  /// Always hardware decoder. The session is invalidated on
  /// `applicationDidEnterBackground` and lazily recreated on the first
  /// frame after foreground — see the App Lifecycle MARK above for rationale.
  private func setupDecompressionSession(formatDescription: CMFormatDescription) {
    let attrs: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
      kCVPixelBufferMetalCompatibilityKey as String: true,
    ]

    var session: VTDecompressionSession?
    let status = VTDecompressionSessionCreate(
      allocator: kCFAllocatorDefault,
      formatDescription: formatDescription,
      decoderSpecification: nil,
      imageBufferAttributes: attrs as CFDictionary,
      outputCallback: nil,
      decompressionSessionOut: &session
    )
    if status == noErr, let session {
      decompressionSession = session
      NSLog("[MWDAT] Created VTDecompressionSession for HEVC decoding (hardware)")
    } else {
      NSLog("[MWDAT] Failed to create VTDecompressionSession: \(status)")
    }
  }

  /// Decodes a compressed CMSampleBuffer (HEVC) to a CVPixelBuffer.
  private func decodeCompressedFrame(_ sampleBuffer: CMSampleBuffer) -> CVPixelBuffer? {
    guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
      return nil
    }

    // Lazily create decompression session on first frame.
    if decompressionSession == nil {
      setupDecompressionSession(formatDescription: formatDescription)
    }

    guard let session = decompressionSession else { return nil }

    var outputBuffer: CVPixelBuffer?
    var flagOut: VTDecodeInfoFlags = []

    let status = VTDecompressionSessionDecodeFrame(
      session,
      sampleBuffer: sampleBuffer,
      flags: [],  // synchronous decode
      infoFlagsOut: &flagOut,
      outputHandler: { decodeStatus, _, imageBuffer, _, _ in
        if decodeStatus == noErr {
          outputBuffer = imageBuffer
        }
      }
    )

    if status != noErr {
      NSLog("[MWDAT] VTDecompressionSession decode error: \(status)")
      return nil
    }

    return outputBuffer
  }

  // MARK: - Stream Session

  func startStreamSession(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String : Any] else {
      result(FlutterError(code: "INVALID_ARGS", message: "arguments missing", details: nil))
      return
    }

    let fps = (args["fps"] as? Double) ?? 30.0
    let streamQuality = Self.parseStreamQuality(args["streamQuality"] as? String)
    let videoCodecStr = args["videoCodec"] as? String ?? "raw"
    let videoCodec: MWDATCamera.VideoCodec = (videoCodecStr == "hvc1") ? .hvc1 : .raw

    // `deviceUUID` is ignored in 0.6.0 — the plugin uses a single shared
    // AutoDeviceSelector. The argument is kept for backward compatibility.
    _ = args["deviceUUID"] as? String

    Task { @MainActor in
      // Return existing texture if stream is already active.
      if streamSession != nil {
        if let texId = textureId {
          result(texId)
        } else {
          result(FlutterError(code: "TEXTURE_ERROR", message: "Session exists but no texture registered", details: nil))
        }
        return
      }

      guard let registry = textureRegistry else {
        result(FlutterError(code: "TEXTURE_ERROR", message: "Texture registry not available", details: nil))
        return
      }

      // 1. Ensure a started DeviceSession exists.
      let deviceSession: DeviceSession
      do {
        deviceSession = try await ensureDeviceSessionStarted()
      } catch let e as DeviceSessionError {
        streamErrorHandler.send(deviceSessionError: e)
        result(FlutterError(code: "DEVICE_SESSION_ERROR", message: "Could not start device session: \(e)", details: nil))
        return
      } catch {
        result(FlutterError(code: "DEVICE_SESSION_ERROR", message: error.localizedDescription, details: nil))
        return
      }

      // 2. Register the Flutter texture.
      let texture = PixelBufferTexture()
      let texId = registry.register(texture)
      pixelBufferTexture = texture
      textureId = texId
      currentTargetFPS = fps
      currentVideoCodec = videoCodec
      frameCounter = 0
      lastFrameSendTime = nil
      NSLog("[MWDAT] Registered texture \(texId)")

      // 3. Add a Stream capability.
      let fpsValue = UInt(max(1, Int(fps.rounded())))
      let streamConfig = StreamConfiguration(
        videoCodec: videoCodec,
        resolution: Self.resolution(for: streamQuality),
        frameRate: fpsValue
      )

      let stream: MWDATCamera.Stream?
      do {
        stream = try deviceSession.addStream(config: streamConfig)
      } catch let e as DeviceSessionError {
        streamErrorHandler.send(deviceSessionError: e)
        await teardownStreamOnly()
        result(FlutterError(code: "ADD_STREAM_ERROR", message: "Could not add stream capability: \(e)", details: nil))
        return
      } catch {
        await teardownStreamOnly()
        result(FlutterError(code: "ADD_STREAM_ERROR", message: error.localizedDescription, details: nil))
        return
      }

      guard let session = stream else {
        await teardownStreamOnly()
        result(FlutterError(code: "ADD_STREAM_ERROR", message: "addStream returned nil — device session not in started state", details: nil))
        return
      }

      // 4. Wire listeners.
      errorListenerToken = session.errorPublisher.listen { error in
        NSLog("[MWDAT] Stream error: \(error)")
      }
      videoListenerToken = session.videoFramePublisher.listen { [weak self] videoFrame in
        guard let self else { return }
        self.processAndSendFrame(videoFrame)
      }

      streamSession = session
      streamStateHandler.session = session
      streamErrorHandler.session = session

      // 5. Start streaming.
      await session.start()
      result(texId)
    }
  }

  func stopStreamSession(call: FlutterMethodCall, result: @escaping FlutterResult) {
    Task { @MainActor in
      guard streamSession != nil else {
        result(FlutterError(code: "SESSION_NOT_FOUND", message: "No active stream session", details: nil))
        return
      }

      // Tear down the stream only — keep the DeviceSession alive so the next
      // startStreamSession is a fast `addStream` rather than a full reconnect.
      await teardownStreamOnly()
      result(true)
    }
  }

  func capturePhoto(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    let formatStr = args?["format"] as? String ?? "jpeg"
    let captureFormat: MWDATCamera.PhotoCaptureFormat = (formatStr == "heic") ? .heic : .jpeg

    Task { @MainActor in
      guard let streamSession else {
        result(FlutterError(code: "SESSION_NOT_FOUND", message: "No active stream session", details: nil))
        return
      }

      var didRespond = false
      var listenerToken: AnyListenerToken?

      listenerToken = streamSession.photoDataPublisher.listen { photoData in
        guard !didRespond else { return }
        didRespond = true
        Task { await listenerToken?.cancel() }

        let formatString: String = (photoData.format == .heic) ? "heic" : "jpeg"
        let payload: [String: Any] = [
          "bytes": FlutterStandardTypedData(bytes: photoData.data),
          "format": formatString,
        ]
        result(payload)
      }

      let accepted = streamSession.capturePhoto(format: captureFormat)
      if !accepted, !didRespond {
        didRespond = true
        Task { await listenerToken?.cancel() }
        result(FlutterError(code: "CAPTURE_NOT_READY", message: "Capture request was not accepted.", details: nil))
      }
    }
  }

  func getRegistrationState(result: @escaping FlutterResult) {
    Task { @MainActor in
      let state = Wearables.shared.registrationState
      result(state.rawValue)
    }
  }

  private static func parseStreamQuality(_ value: String?) -> StreamQuality {
    switch value?.lowercased() {
      case "high":
        return .high
      case "low":
        return .low
      case "medium":
        return .medium
      default:
        return .high
    }
  }

  private static func resolution(for quality: StreamQuality) -> StreamingResolution {
    switch quality {
      case .high:
        return .high
      case .low:
        return .low
      case .medium:
        return .medium
    }
  }
}

private enum StreamQuality {
  case high
  case medium
  case low
}
