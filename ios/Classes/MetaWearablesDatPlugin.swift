import Flutter
import UIKit
import MWDATCore
import MWDATCamera
import MWDATMockDevice
import AVFoundation
import CoreMedia
import VideoToolbox

public class MetaWearablesDatPlugin: NSObject, FlutterPlugin {
  // Device session (0.6.0): created lazily on first startStreamSession call
  // using the shared AutoDeviceSelector. Kept alive across stream start/stop
  // so toggling streaming is fast. Torn down only when the underlying device
  // disappears or when the plugin is disabled.
  private lazy var deviceSelector: AutoDeviceSelector = {
    AutoDeviceSelector(wearables: Wearables.shared)
  }()
  private var deviceSession: DeviceSession?
  private var deviceSessionStateTask: Task<Void, Never>?
  private var deviceSessionErrorTask: Task<Void, Never>?
  private var deviceAvailabilityTask: Task<Void, Never>?

  // Stream session state (single session at a time)
  private var streamSession: StreamSession?
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
  // Stream session event handlers
  private var streamStateHandler = StreamSessionStateStreamHandler()
  private var streamErrorHandler = StreamSessionErrorStreamHandler()
  private var videoStreamSizeHandler = VideoStreamSizeStreamHandler()

  // Current mock device config. Applied whenever MockDeviceKit is enabled.
  private var mockDeviceConfig: MockDeviceKitConfig = MockDeviceKitConfig()

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

    Task { @MainActor in
      try? Wearables.configure()
      instance.startDeviceAvailabilityMonitoring()
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
      case "pairMockRayBanMeta":
        pairMockRayBanMeta(result: result)
      case "unpairMockRayBanMeta":
        unpairMockRayBanMeta(call: call, result: result)
      case "mockDevicePowerOn":
        mockDeviceAction(call: call, result: result) { device in
          device.powerOn()
        }
      case "mockDevicePowerOff":
        mockDeviceAction(call: call, result: result) { device in
          device.powerOff()
        }
      case "mockDeviceDon":
        mockDeviceAction(call: call, result: result) { device in
          device.don()
        }
      case "mockDeviceDoff":
        mockDeviceAction(call: call, result: result) { device in
          device.doff()
        }
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
      case "setMockCameraFeed":
        setMockCameraFeed(call: call, result: result)
      case "setMockCameraFacing":
        setMockCameraFacing(call: call, result: result)
      case "setMockCapturedImage":
        setMockCapturedImage(call: call, result: result)
      case "startStreamSession":
        startStreamSession(call: call, result: result)
      case "stopStreamSession":
        stopStreamSession(call: call, result: result)
      case "capturePhoto":
        capturePhoto(call: call, result: result)
      case "getRegistrationState":
        getRegistrationState(result: result)
      case "configureMockDevices":
        configureMockDevices(call: call, result: result)
      case "disableMockDevices":
        disableMockDevices(result: result)
      case "setMockPermission":
        setMockPermission(call: call, result: result)
      case "setMockPermissionRequestResult":
        setMockPermissionRequestResult(call: call, result: result)
      default:
        result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - MockDeviceKit lifecycle (0.6.0)

  private func ensureMockKitEnabled() {
    if !MockDeviceKit.shared.isEnabled {
      MockDeviceKit.shared.enable(config: mockDeviceConfig)
    }
  }

  func configureMockDevices(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    let initiallyRegistered = (args?["initiallyRegistered"] as? Bool) ?? true
    let initialPermissionsGranted = (args?["initialPermissionsGranted"] as? Bool) ?? true
    mockDeviceConfig = MockDeviceKitConfig(
      initiallyRegistered: initiallyRegistered,
      initialPermissionsGranted: initialPermissionsGranted
    )

    Task { @MainActor in
      // Re-enable to apply the new config (disable is a no-op when off).
      await teardownDeviceSession()
      if MockDeviceKit.shared.isEnabled {
        MockDeviceKit.shared.disable()
      }
      MockDeviceKit.shared.enable(config: mockDeviceConfig)
      result(true)
    }
  }

  func disableMockDevices(result: @escaping FlutterResult) {
    Task { @MainActor in
      await teardownDeviceSession()
      if MockDeviceKit.shared.isEnabled {
        MockDeviceKit.shared.disable()
      }
      result(true)
    }
  }

  func pairMockRayBanMeta(result: @escaping FlutterResult) {
    Task { @MainActor in
      ensureMockKitEnabled()
      let mockDevice = MockDeviceKit.shared.pairRaybanMeta()
      result(mockDevice.deviceIdentifier)
    }
  }

  func unpairMockRayBanMeta(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String : Any], let uuidString = args["deviceUUID"] as? String else {
      result(FlutterError(code: "INVALID_ARGS", message: "deviceUUID missing", details: nil))
      return
    }
    Task { @MainActor in
      let devices = MockDeviceKit.shared.pairedDevices
      guard let device = devices.first(where: { $0.deviceIdentifier == uuidString }) else {
        result(FlutterError(code: "DEVICE_NOT_FOUND", message: "No mock device with uuid \(uuidString)", details: nil))
        return
      }

      // Clean up active session — unpairing the device invalidates it.
      await teardownDeviceSession()

      MockDeviceKit.shared.unpairDevice(device)
      result(true)
    }
  }

  private func mockDeviceAction(call: FlutterMethodCall, result: @escaping FlutterResult, perform: @escaping @MainActor (any MWDATMockDevice.MockDevice) -> Void) {
    guard let args = call.arguments as? [String : Any], let uuidString = args["deviceUUID"] as? String else {
      result(FlutterError(code: "INVALID_ARGS", message: "deviceUUID missing", details: nil))
      return
    }

    Task { @MainActor in
      let devices = MockDeviceKit.shared.pairedDevices
      guard let device = devices.first(where: { $0.deviceIdentifier == uuidString }) else {
        result(FlutterError(code: "DEVICE_NOT_FOUND", message: "No mock device with uuid \(uuidString)", details: nil))
        return
      }
      perform(device)
      result(true)
    }
  }

  // MARK: - Mock permissions (0.6.0)

  private func parsePermission(_ raw: String?) -> MWDATCore.Permission? {
    switch raw {
    case "camera": return .camera
    default: return nil
    }
  }

  private func parsePermissionStatus(_ raw: String?) -> MWDATCore.PermissionStatus? {
    switch raw {
    case "granted": return .granted
    case "denied": return .denied
    default: return nil
    }
  }

  func setMockPermission(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let permission = parsePermission(args["permission"] as? String),
          let status = parsePermissionStatus(args["status"] as? String) else {
      result(FlutterError(code: "INVALID_ARGS", message: "permission/status missing or invalid", details: nil))
      return
    }
    Task { @MainActor in
      ensureMockKitEnabled()
      MockDeviceKit.shared.permissions.set(permission, status)
      result(true)
    }
  }

  func setMockPermissionRequestResult(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let permission = parsePermission(args["permission"] as? String),
          let status = parsePermissionStatus(args["status"] as? String) else {
      result(FlutterError(code: "INVALID_ARGS", message: "permission/status missing or invalid", details: nil))
      return
    }
    Task { @MainActor in
      ensureMockKitEnabled()
      MockDeviceKit.shared.permissions.setRequestResult(permission, result: status)
      result(true)
    }
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
        result(FlutterError(code: "PERMISSION_ERROR", message: e.localizedDescription, details: e.rawValue))
      } catch {
        result(FlutterError(code: "PERMISSION_ERROR", message: error.localizedDescription, details: nil))
      }
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
        result(FlutterError(code: "PERMISSION_ERROR", message: error.localizedDescription, details: nil))
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
  // delivering hvc1 CMSampleBuffers in background (CPU-only CMBlockBuffer),
  // but decoding them via VTDecompressionSession produces GPU-backed
  // CVPixelBuffers — which is unsafe while backgrounded.
  //
  // Strategy: invalidate the decoder on background, skip frame processing
  // while backgrounded, let the lazy-init path in decodeCompressedFrame()
  // recreate the decoder on the first frame after foregrounding. The
  // underlying StreamSession stays alive throughout.

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
    NSLog("[MWDAT] App entering foreground — HEVC decoding will resume on next frame")
  }

  // MARK: - Frame Processing (zero-copy via Texture API)
  /// Pushes a CVPixelBuffer extracted from the VideoFrame's CMSampleBuffer
  /// directly to the Flutter texture — no JPEG encode/decode, no byte copy.
  private func processAndSendFrame(_ videoFrame: VideoFrame) {
    // Skip frame processing while backgrounded. iOS forbids GPU access in
    // background and the Flutter raster thread is suspended — decoding and
    // texture updates are both pointless. The underlying StreamSession stays
    // alive; frames are silently dropped. Applies to both raw and hvc1.
    guard !isInBackground else { return }

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

    guard let texture = pixelBufferTexture,
          let texId = textureId else {
      return
    }

    // Surface the frame dimensions to Dart so it can set an AspectRatio.
    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    videoStreamSizeHandler.send(width: width, height: height)

    // Swap the pixel buffer (lock-protected) and notify Flutter's rasteriser
    texture.latestPixelBuffer = pixelBuffer
    textureRegistry?.textureFrameAvailable(texId)

    // Update timing + counters
    lastFrameSendTime = now
    frameCounter += 1

    if frameCounter % 30 == 0 && timeSinceLastFrame > 0 {
      let actualFPS = 1.0 / timeSinceLastFrame
      NSLog("[MWDAT] \(frameCounter) frames, target: \(currentTargetFPS), actual: \(String(format: "%.1f", actualFPS)) FPS")
    }
  }

  // MARK: - HEVC Decompression (for hvc1 codec)

  /// Creates a VTDecompressionSession for decoding HEVC frames to BGRA pixel buffers.
  private func setupDecompressionSession(formatDescription: CMFormatDescription) {
    let attrs: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
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
      NSLog("[MWDAT] Created VTDecompressionSession for HEVC decoding")
    } else {
      NSLog("[MWDAT] Failed to create VTDecompressionSession: \(status)")
    }
  }

  /// Decodes a compressed CMSampleBuffer (HEVC) to a CVPixelBuffer.
  private func decodeCompressedFrame(_ sampleBuffer: CMSampleBuffer) -> CVPixelBuffer? {
    guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
      return nil
    }

    // Lazily create decompression session on first frame
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

  // MARK: - Mock Camera Feed

  private func mockCameraKit(for deviceUUID: String) -> (any MWDATMockDevice.MockCameraKit)? {
    let devices = MockDeviceKit.shared.pairedDevices
    guard let device = devices.first(where: { $0.deviceIdentifier == deviceUUID }) else {
      return nil
    }
    guard let displayless = device as? any MWDATMockDevice.MockDisplaylessGlasses else {
      return nil
    }
    return displayless.services.camera
  }

  func setMockCameraFeed(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String : Any],
          let uuidString = args["deviceUUID"] as? String else {
      result(FlutterError(code: "INVALID_ARGS", message: "deviceUUID missing", details: nil))
      return
    }

    Task { @MainActor in
      guard let cameraKit = mockCameraKit(for: uuidString) else {
        result(FlutterError(code: "DEVICE_NOT_FOUND", message: "No mock camera device with uuid \(uuidString)", details: nil))
        return
      }

      if let videoPath = args["videoPath"] as? String, !videoPath.isEmpty {
        let fileURL = URL(fileURLWithPath: videoPath)

        // Validate file exists
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: videoPath) {
          result(FlutterError(code: "FILE_NOT_FOUND", message: "Video file not found at path: \(videoPath)", details: nil))
          return
        }

        // Validate video codec - must be HEVC/H.265
        let asset = AVAsset(url: fileURL)
        let tracks = try? await asset.loadTracks(withMediaType: .video)
        var foundHEVC = false

        if let videoTracks = tracks {
          for videoTrack in videoTracks {
            if let formatDescriptions = try? await videoTrack.load(.formatDescriptions) as? [CMFormatDescription],
               let formatDescription = formatDescriptions.first {
              let codecType = CMFormatDescriptionGetMediaSubType(formatDescription)
              let codecString = String(format: "%c%c%c%c",
                                      (codecType >> 24) & 0xFF,
                                      (codecType >> 16) & 0xFF,
                                      (codecType >> 8) & 0xFF,
                                      codecType & 0xFF)

              if codecType == kCMVideoCodecType_HEVC ||
                 codecString == "hvc1" ||
                 codecString == "hev1" {
                foundHEVC = true
                break
              }
            }
          }
        }

        if !foundHEVC {
          result(FlutterError(code: "INVALID_CODEC", message: "Video must be HEVC/H.265 format. Use file_picker (not image_picker) to preserve original format.", details: nil))
          return
        }

        cameraKit.setCameraFeed(fileURL: fileURL)
        result(true)
      } else {
        result(true)
      }
    }
  }

  func setMockCameraFacing(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
          let uuidString = args["deviceUUID"] as? String,
          let facingRaw = args["cameraFacing"] as? String else {
      result(FlutterError(code: "INVALID_ARGS", message: "deviceUUID/cameraFacing missing", details: nil))
      return
    }

    let facing: MWDATMockDevice.CameraFacing
    switch facingRaw {
    case "front": facing = .front
    case "back":  facing = .back
    default:
      result(FlutterError(code: "INVALID_ARGS", message: "cameraFacing must be 'front' or 'back'", details: nil))
      return
    }

    Task { @MainActor in
      guard let cameraKit = mockCameraKit(for: uuidString) else {
        result(FlutterError(code: "DEVICE_NOT_FOUND", message: "No mock camera device with uuid \(uuidString)", details: nil))
        return
      }
      // MockDeviceKit opens the phone's camera to simulate the wearable feed.
      // Prompt proactively so a denial surfaces as a clear error instead of a
      // silent black feed when the stream starts.
      let granted = await Self.ensureCameraAuthorization()
      guard granted else {
        result(FlutterError(code: "PERMISSION_DENIED", message: "Camera permission is required for the mock device feed.", details: nil))
        return
      }
      await cameraKit.setCameraFeed(cameraFacing: facing)
      result(true)
    }
  }

  private static func ensureCameraAuthorization() async -> Bool {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .authorized: return true
    case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
    case .denied, .restricted: return false
    @unknown default: return false
    }
  }

  func setMockCapturedImage(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String : Any],
          let uuidString = args["deviceUUID"] as? String else {
      result(FlutterError(code: "INVALID_ARGS", message: "deviceUUID missing", details: nil))
      return
    }

    Task { @MainActor in
      guard let cameraKit = mockCameraKit(for: uuidString) else {
        result(FlutterError(code: "DEVICE_NOT_FOUND", message: "No mock camera device with uuid \(uuidString)", details: nil))
        return
      }

      if let imagePath = args["imagePath"] as? String, !imagePath.isEmpty {
        let fileURL = URL(fileURLWithPath: imagePath)
        cameraKit.setCapturedImage(fileURL: fileURL)
        result(true)
      } else {
        // If imagePath is nil or empty, we could clear the image or just return success
        result(true)
      }
    }
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

      // 3. Add a StreamSession capability.
      let fpsValue = UInt(max(1, Int(fps.rounded())))
      let streamConfig = StreamSessionConfig(
        videoCodec: videoCodec,
        resolution: Self.resolution(for: streamQuality),
        frameRate: fpsValue
      )

      let stream: StreamSession?
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
        NSLog("[MWDAT] StreamSession error: \(error)")
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
