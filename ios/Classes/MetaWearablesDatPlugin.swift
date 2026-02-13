import Flutter
import UIKit
import MWDATCore
import MWDATCamera
import MWDATMockDevice
import AVFoundation

public class MetaWearablesDatPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  // Dictionary to store StreamSession instances keyed by device UUID
  private var streamSessions: [String: StreamSession] = [:]
  // Video frame streaming
  private var videoEventSink: FlutterEventSink?
  private var videoListenerTokens: [String: any MWDATCore.AnyListenerToken] = [:]
  private var errorListenerTokens: [String: any MWDATCore.AnyListenerToken] = [:]
  private var frameCounters: [String: Int] = [:]
  // Frame rate throttling
  private var targetFPS: [String: Double] = [:] // FPS per device
  private var lastFrameSendTime: [String: Date] = [:]
  // Device discovery
  private var deviceDiscoveryToken: (any MWDATCore.AnyListenerToken)?
  private var discoveredDevices: [String: String] = [:] // UUID -> identifier mapping
  
  // Initializer
  public override init() {
    super.init()
  }
  
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_meta_wearables_dat", binaryMessenger: registrar.messenger())
    let instance = MetaWearablesDatPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    // Event channel for streaming video frames to Flutter
    let videoFramesChannel = FlutterEventChannel(name: "flutter_meta_wearables_dat/video_frames", binaryMessenger: registrar.messenger())
    videoFramesChannel.setStreamHandler(instance)
    // Event channel for registration state updates
    let registrationStateChannel = FlutterEventChannel(name: "flutter_meta_wearables_dat/registration_state", binaryMessenger: registrar.messenger())
    registrationStateChannel.setStreamHandler(RegistrationStateStreamHandler())
    // Event channel for active device availability updates
    let activeDeviceChannel = FlutterEventChannel(name: "flutter_meta_wearables_dat/active_device", binaryMessenger: registrar.messenger())
    activeDeviceChannel.setStreamHandler(ActiveDeviceStreamHandler())
    
    Task { @MainActor in
      try? Wearables.configure()
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
      case "getPlatformVersion":
        result("iOS " + UIDevice.current.systemVersion)
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
      default:
        result(FlutterMethodNotImplemented)
    }
  }

  func pairMockRayBanMeta(result: @escaping FlutterResult) {
    Task { @MainActor in
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
      
      // Stop and remove any active stream session for this device
      if let streamSession = streamSessions[uuidString] {
        await streamSession.stop()
        if let token = videoListenerTokens[uuidString] {
          await token.cancel()
          videoListenerTokens.removeValue(forKey: uuidString)
        }
        if let token = errorListenerTokens[uuidString] {
          await token.cancel()
          errorListenerTokens.removeValue(forKey: uuidString)
        }
        streamSessions.removeValue(forKey: uuidString)
        frameCounters.removeValue(forKey: uuidString)
        lastFrameSendTime.removeValue(forKey: uuidString)
        targetFPS.removeValue(forKey: uuidString)
      }
      
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
      } catch let e as MWDATCore.PermissionError {
        result(FlutterError(code: "PERMISSION_ERROR", message: e.localizedDescription, details: e.rawValue))
      } catch {
        result(FlutterError(code: "PERMISSION_ERROR", message: error.localizedDescription, details: nil))
      }
    }
  }

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

  // MARK: - Frame Processing Helper
  private func processAndSendFrame(_ videoFrame: VideoFrame, forDevice uuidString: String) {
    let now = Date()
    let fps = targetFPS[uuidString] ?? 30.0 // Default to 30.0 FPS if not set
    let minInterval = 1.0 / fps // Minimum seconds between frames
    
    // Check if enough time has passed since last frame
    let timeSinceLastFrame: TimeInterval
    if let lastSendTime = lastFrameSendTime[uuidString] {
      timeSinceLastFrame = now.timeIntervalSince(lastSendTime)
      if timeSinceLastFrame < minInterval {
        // Skip this frame - not enough time has passed
        return
      }
    } else {
      timeSinceLastFrame = 0
    }
    
    // Convert frame to UIImage
    guard let uiImage = videoFrame.makeUIImage() else {
      NSLog("[MWDAT] makeUIImage() returned nil for a video frame")
      return
    }
    
    // Encode to JPEG with optimized quality for better performance
    // Use slightly lower quality for better framerate, but still maintain visual quality
    var bytes: Data?
    if let jpeg = uiImage.jpegData(compressionQuality: 0.85) {
      bytes = jpeg
    } else if let png = uiImage.pngData() {
      bytes = png
    }
    
    guard let bytes, let eventSink = self.videoEventSink else {
      if bytes == nil {
        NSLog("[MWDAT] Failed to encode UIImage to JPEG/PNG data")
      }
      return
    }
    
    // Send frame to Flutter
    let typed = FlutterStandardTypedData(bytes: bytes)
    eventSink(typed)
    
    // Update last send time and frame counter
    lastFrameSendTime[uuidString] = now
    let count = (self.frameCounters[uuidString] ?? 0) + 1
    self.frameCounters[uuidString] = count
    
    // Log every 30 frames to avoid spam
    if count % 30 == 0 && timeSinceLastFrame > 0 {
      let actualFPS = 1.0 / timeSinceLastFrame
      NSLog("[MWDAT] Emitted \(count) frames for device: \(uuidString), target FPS: \(fps), actual FPS: \(String(format: "%.1f", actualFPS))")
    }
  }

  // MARK: - FlutterStreamHandler (video frames)
  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    // deviceUUID is optional - if not provided, we'll use "auto" for AutoDeviceSelector
    let uuidString = (arguments as? [String : Any])?["deviceUUID"] as? String ?? "auto"
    self.videoEventSink = events
    
    // Subscribe to video frames on the main actor
    // If stream session doesn't exist yet, it will be subscribed when it's created in startStreamSession
    Task { @MainActor in
      // Wait for the stream session to be created and started
      var attempts = 0
      while streamSessions[uuidString] == nil && attempts < 20 {
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        attempts += 1
      }
      
      guard let streamSession = self.streamSessions[uuidString] else {
        NSLog("[MWDAT] Stream session not found for device \(uuidString) after waiting")
        return
      }
      
      // Only subscribe if we don't already have a listener for this device
      if self.videoListenerTokens[uuidString] == nil {
        self.frameCounters[uuidString] = 0
        self.lastFrameSendTime.removeValue(forKey: uuidString) // Reset to allow first frame immediately
        let token = streamSession.videoFramePublisher.listen { [weak self] videoFrame in
          guard let self else { return }
          self.processAndSendFrame(videoFrame, forDevice: uuidString)
        }
        self.videoListenerTokens[uuidString] = token
        NSLog("[MWDAT] Subscribed to video frames for device: \(uuidString)")
      }
    }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    self.videoEventSink = nil
    // Cancel all video listeners
    for (_, token) in videoListenerTokens {
      Task { @MainActor in
        await token.cancel()
      }
    }
    videoListenerTokens.removeAll()
    return nil
  }

  func setMockCameraFeed(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String : Any],
          let uuidString = args["deviceUUID"] as? String else {
      result(FlutterError(code: "INVALID_ARGS", message: "deviceUUID missing", details: nil))
      return
    }
    
    Task { @MainActor in
      let devices = MockDeviceKit.shared.pairedDevices
      guard let device = devices.first(where: { $0.deviceIdentifier == uuidString }) else {
        result(FlutterError(code: "DEVICE_NOT_FOUND", message: "No mock device with uuid \(uuidString)", details: nil))
        return
      }
      
      guard let mockDisplaylessGlasses = device as? any MWDATMockDevice.MockDisplaylessGlasses else {
        result(FlutterError(code: "INVALID_DEVICE_TYPE", message: "Device does not support camera", details: nil))
        return
      }
      
      let cameraKit = mockDisplaylessGlasses.getCameraKit()
      
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
        
        await cameraKit.setCameraFeed(fileURL: fileURL)
        result(true)
      } else {
        result(true)
      }
    }
  }

  func setMockCapturedImage(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String : Any],
          let uuidString = args["deviceUUID"] as? String else {
      result(FlutterError(code: "INVALID_ARGS", message: "deviceUUID missing", details: nil))
      return
    }
    
    Task { @MainActor in
      let devices = MockDeviceKit.shared.pairedDevices
      guard let device = devices.first(where: { $0.deviceIdentifier == uuidString }) else {
        result(FlutterError(code: "DEVICE_NOT_FOUND", message: "No mock device with uuid \(uuidString)", details: nil))
        return
      }
      
      guard let mockDisplaylessGlasses = device as? any MWDATMockDevice.MockDisplaylessGlasses else {
        result(FlutterError(code: "INVALID_DEVICE_TYPE", message: "Device does not support camera", details: nil))
        return
      }
      
      let cameraKit = mockDisplaylessGlasses.getCameraKit()
      
      if let imagePath = args["imagePath"] as? String, !imagePath.isEmpty {
        let fileURL = URL(fileURLWithPath: imagePath)
        await cameraKit.setCapturedImage(fileURL: fileURL)
        result(true)
      } else {
        // If imagePath is nil or empty, we could clear the image or just return success
        result(true)
      }
    }
  }

  func startStreamSession(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String : Any] else {
      result(FlutterError(code: "INVALID_ARGS", message: "arguments missing", details: nil))
      return
    }
    
    // Get FPS parameter (default to 30.0 if not provided)
    let fps = (args["fps"] as? Double) ?? 30.0
    
    // deviceUUID is optional - if not provided, use AutoDeviceSelector
    let uuidString = args["deviceUUID"] as? String
    
    Task { @MainActor in
      // Determine device selector
      let deviceSelector: any DeviceSelector
      let sessionKey: String
      
      if let uuidString = uuidString {
        // Use specific device selector
        deviceSelector = SpecificDeviceSelector(device: uuidString)
        sessionKey = uuidString
      } else {
        // Use auto device selector to discover and connect to available devices
        deviceSelector = AutoDeviceSelector(wearables: Wearables.shared)
        sessionKey = "auto"
        
        // Listen for active device changes from AutoDeviceSelector using async sequence
        Task { [weak self] in
          guard let self else { return }
          for await deviceId in deviceSelector.activeDeviceStream() {
            guard let deviceId = deviceId else { continue }
            let uuid = deviceId // DeviceIdentifier is already a String
            NSLog("[MWDAT] AutoDeviceSelector found active device: \(uuid)")
            // Update discovered devices
            self.discoveredDevices[uuid] = uuid
          }
        }
      }
      
      // Store FPS for this session
      targetFPS[sessionKey] = fps
      
      // Check if a session already exists
      if let existingSession = streamSessions[sessionKey] {
        await existingSession.start()
        result(true)
        return
      }
      
      // Create a new StreamSession
      let streamSession = StreamSession(deviceSelector: deviceSelector)
      
      // Observe errors
      let errorToken = streamSession.errorPublisher.listen { error in
        NSLog("[MWDAT] StreamSession error for \(sessionKey): \(error)")
      }
      errorListenerTokens[sessionKey] = errorToken
      
      // Store the session
      streamSessions[sessionKey] = streamSession
      
      // If videoEventSink already exists (Flutter already listening), subscribe immediately
      if self.videoEventSink != nil {
        self.frameCounters[sessionKey] = 0
        self.lastFrameSendTime.removeValue(forKey: sessionKey) // Reset to allow first frame immediately
        let token = streamSession.videoFramePublisher.listen { [weak self] videoFrame in
          guard let self else { return }
          self.processAndSendFrame(videoFrame, forDevice: sessionKey)
        }
        self.videoListenerTokens[sessionKey] = token
      }
      
      // Start the session
      do {
        await streamSession.start()
        
        // If using AutoDeviceSelector, get the active device UUID
        if uuidString == nil, let activeDevice = deviceSelector.activeDevice {
          let activeUUID = activeDevice // DeviceIdentifier is already a String
          NSLog("[MWDAT] AutoDeviceSelector connected to device: \(activeUUID)")
          // We could notify Flutter here about the discovered device
        }
        
        result(true)
      } catch {
        result(FlutterError(code: "STREAM_SESSION_ERROR", message: error.localizedDescription, details: nil))
      }
    }
  }

  func stopStreamSession(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String : Any] else {
      result(FlutterError(code: "INVALID_ARGS", message: "arguments missing", details: nil))
      return
    }
    
    // deviceUUID is optional - use "auto" if not provided
    let uuidString = args["deviceUUID"] as? String ?? "auto"
    
    Task { @MainActor in
      guard let streamSession = streamSessions[uuidString] else {
        result(FlutterError(code: "SESSION_NOT_FOUND", message: "No stream session found for device \(uuidString)", details: nil))
        return
      }
      
      await streamSession.stop()
      // Cancel any video listener for this device
      if let token = videoListenerTokens[uuidString] {
        await token.cancel()
        videoListenerTokens.removeValue(forKey: uuidString)
      }
      streamSessions.removeValue(forKey: uuidString)
      frameCounters.removeValue(forKey: uuidString)
      lastFrameSendTime.removeValue(forKey: uuidString)
      targetFPS.removeValue(forKey: uuidString)
      result(true)
    }
  }

  func capturePhoto(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String : Any]
    let uuidString = args?["deviceUUID"] as? String ?? "auto"

    Task { @MainActor in
      guard let streamSession = streamSessions[uuidString] else {
        result(FlutterError(code: "SESSION_NOT_FOUND", message: "No stream session found for device \(uuidString)", details: nil))
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

      let accepted = streamSession.capturePhoto(format: .jpeg)
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
}
