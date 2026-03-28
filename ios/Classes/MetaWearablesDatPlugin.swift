import AVFoundation
import CoreMedia
import Flutter
import MWDATCamera
import MWDATCore
import MWDATMockDevice
import UIKit
import VideoToolbox

public class MetaWearablesDatPlugin: NSObject, FlutterPlugin {
    // Single stream session state (only one session at a time)
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
    // Texture registry
    private var textureRegistry: FlutterTextureRegistry?
    // Stream session event handlers
    private var streamStateHandler = StreamSessionStateStreamHandler()
    private var streamErrorHandler = StreamSessionErrorStreamHandler()

    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "flutter_meta_wearables_dat", binaryMessenger: registrar.messenger())
        let instance = MetaWearablesDatPlugin()
        instance.textureRegistry = registrar.textures()
        registrar.addMethodCallDelegate(instance, channel: channel)
        // Event channel for registration state updates
        let registrationStateChannel = FlutterEventChannel(name: "flutter_meta_wearables_dat/registration_state", binaryMessenger: registrar.messenger())
        registrationStateChannel.setStreamHandler(RegistrationStateStreamHandler())
        // Event channel for active device availability updates
        let activeDeviceChannel = FlutterEventChannel(name: "flutter_meta_wearables_dat/active_device", binaryMessenger: registrar.messenger())
        activeDeviceChannel.setStreamHandler(ActiveDeviceStreamHandler())
        // Event channels for stream session state and errors
        let streamStateChannel = FlutterEventChannel(name: "flutter_meta_wearables_dat/stream_session_state", binaryMessenger: registrar.messenger())
        streamStateChannel.setStreamHandler(instance.streamStateHandler)
        let streamErrorChannel = FlutterEventChannel(name: "flutter_meta_wearables_dat/stream_session_errors", binaryMessenger: registrar.messenger())
        streamErrorChannel.setStreamHandler(instance.streamErrorHandler)

        Task { @MainActor in
            try? Wearables.configure()
        }
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "pairMockRayBanMeta":
            pairMockRayBanMeta(result: result)
        case "unpairMockRayBanMeta":
            unpairMockRayBanMeta(call: call, result: result)
        case "mockDevicePowerOn":
            mockDeviceAction(call: call, result: result) {
                device in
                device.powerOn()
            }
        case "mockDevicePowerOff":
            mockDeviceAction(call: call, result: result) {
                device in
                device.powerOff()
            }
        case "mockDeviceDon":
            mockDeviceAction(call: call, result: result) {
                device in
                device.don()
            }
        case "mockDeviceDoff":
            mockDeviceAction(call: call, result: result) {
                device in
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
        case "captureStreamFrame":
            captureStreamFrame(call: call, result: result)
        case "getRegistrationState":
            getRegistrationState(result: result)
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    func pairMockRayBanMeta(result: @escaping FlutterResult) {
        Task {
            @MainActor in
            let mockDevice = MockDeviceKit.shared.pairRaybanMeta()
            result(mockDevice.deviceIdentifier)
        }
    }

    func unpairMockRayBanMeta(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any], let uuidString = args["deviceUUID"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "deviceUUID missing", details: nil))
            return
        }
        Task {
            @MainActor in
            let devices = MockDeviceKit.shared.pairedDevices
            guard let device = devices.first(where: {
                $0.deviceIdentifier == uuidString
            }) else {
                result(FlutterError(code: "DEVICE_NOT_FOUND", message: "No mock device with uuid \(uuidString)", details: nil))
                return
            }

            // Clean up active stream session if any
            await cleanupSession()

            MockDeviceKit.shared.unpairDevice(device)
            result(true)
        }
    }

    private func mockDeviceAction(call: FlutterMethodCall, result: @escaping FlutterResult, perform: @escaping @MainActor (any MWDATMockDevice.MockDevice) -> Void) {
        guard let args = call.arguments as? [String: Any], let uuidString = args["deviceUUID"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "deviceUUID missing", details: nil))
            return
        }

        Task {
            @MainActor in
            let devices = MockDeviceKit.shared.pairedDevices
            guard let device = devices.first(where: {
                $0.deviceIdentifier == uuidString
            }) else {
                result(FlutterError(code: "DEVICE_NOT_FOUND", message: "No mock device with uuid \(uuidString)", details: nil))
                return
            }
            perform(device)
            result(true)
        }
    }

    func requestCameraPermission(result: @escaping FlutterResult) {
        Task {
            @MainActor in
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
        Task {
            @MainActor in
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

    func startRegistration(result: @escaping FlutterResult) {
        Task {
            @MainActor in
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
        Task {
            @MainActor in
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
        guard let args = call.arguments as? [String: Any], let urlString = args["url"] as? String else {
            result(FlutterError(code: "INVALID_ARGS", message: "url missing", details: nil))
            return
        }

        guard let url = URL(string: urlString) else {
            result(FlutterError(code: "INVALID_URL", message: "Could not parse URL: \(urlString)", details: nil))
            return
        }

        Task {
            @MainActor in
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

    // MARK: - Session Cleanup

    /// Single source of truth for tearing down the current stream session.
    /// Safe to call even when no session is active.
    private func cleanupSession() async {
        if let token = videoListenerToken {
            await token.cancel()
            videoListenerToken = nil
        }
        if let token = errorListenerToken {
            await token.cancel()
            errorListenerToken = nil
        }
        // Disconnect event handlers
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
    }

    // MARK: - Frame Processing (zero-copy via Texture API)

    /// Pushes a CVPixelBuffer extracted from the VideoFrame's CMSampleBuffer
    /// directly to the Flutter texture — no JPEG encode/decode, no byte copy.
    private func processAndSendFrame(_ videoFrame: VideoFrame) {
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
              let texId = textureId
        else {
            return
        }

        // Swap the pixel buffer (lock-protected) and notify Flutter's rasteriser
        texture.latestPixelBuffer = pixelBuffer
        textureRegistry?.textureFrameAvailable(texId)

        // Update timing + counters
        lastFrameSendTime = now
        frameCounter += 1

        if frameCounter % 30 == 0, timeSinceLastFrame > 0 {
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

        guard let session = decompressionSession else {
            return nil
        }

        var outputBuffer: CVPixelBuffer?
        var flagOut: VTDecodeInfoFlags = []

        let status = VTDecompressionSessionDecodeFrame(
            session,
            sampleBuffer: sampleBuffer,
            flags: [], // synchronous decode
            infoFlagsOut: &flagOut,
            outputHandler: {
                decodeStatus, _, imageBuffer, _, _ in
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

    func setMockCameraFeed(call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard let args = call.arguments as? [String: Any],
              let uuidString = args["deviceUUID"] as? String
        else {
            result(FlutterError(code: "INVALID_ARGS", message: "deviceUUID missing", details: nil))
            return
        }

        Task {
            @MainActor in
            let devices = MockDeviceKit.shared.pairedDevices
            guard let device = devices.first(where: {
                $0.deviceIdentifier == uuidString
            }) else {
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
                           let formatDescription = formatDescriptions.first
                        {
                            let codecType = CMFormatDescriptionGetMediaSubType(formatDescription)
                            let codecString = String(format: "%c%c%c%c",
                                                     (codecType >> 24) & 0xFF,
                                                     (codecType >> 16) & 0xFF,
                                                     (codecType >> 8) & 0xFF,
                                                     codecType & 0xFF)

                            if codecType == kCMVideoCodecType_HEVC || codecString == "hvc1" || codecString == "hev1" {
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
        guard let args = call.arguments as? [String: Any],
              let uuidString = args["deviceUUID"] as? String
        else {
            result(FlutterError(code: "INVALID_ARGS", message: "deviceUUID missing", details: nil))
            return
        }

        Task {
            @MainActor in
            let devices = MockDeviceKit.shared.pairedDevices
            guard let device = devices.first(where: {
                $0.deviceIdentifier == uuidString
            }) else {
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
        guard let args = call.arguments as? [String: Any] else {
            result(FlutterError(code: "INVALID_ARGS", message: "arguments missing", details: nil))
            return
        }

        // Get FPS parameter (default to 30.0 if not provided)
        let fps = (args["fps"] as? Double) ?? 30.0
        let streamQuality = Self.parseStreamQuality(args["streamQuality"] as? String)
        let videoCodecStr = args["videoCodec"] as? String ?? "raw"
        let videoCodec: MWDATCamera.VideoCodec = (videoCodecStr == "hvc1") ? .hvc1 : .raw

        // deviceUUID is optional - if not provided, use AutoDeviceSelector
        let uuidString = args["deviceUUID"] as? String

        Task {
            @MainActor in
            // Determine device selector
            let deviceSelector: any DeviceSelector
            if let uuidString = uuidString {
                deviceSelector = SpecificDeviceSelector(device: uuidString)
            } else {
                deviceSelector = AutoDeviceSelector(wearables: Wearables.shared)
            }

            // Return existing texture if session is already active
            if streamSession != nil {
                if let texId = textureId {
                    result(texId)
                } else {
                    result(FlutterError(code: "TEXTURE_ERROR", message: "Session exists but no texture registered", details: nil))
                }
                return
            }

            // Register a Flutter texture
            guard let registry = textureRegistry else {
                result(FlutterError(code: "TEXTURE_ERROR", message: "Texture registry not available", details: nil))
                return
            }
            let texture = PixelBufferTexture()
            let texId = registry.register(texture)
            pixelBufferTexture = texture
            textureId = texId
            currentTargetFPS = fps
            currentVideoCodec = videoCodec
            frameCounter = 0
            lastFrameSendTime = nil
            NSLog("[MWDAT] Registered texture \(texId)")

            // Create a new StreamSession
            let fpsValue = UInt(max(1, Int(fps.rounded())))
            let streamConfig = StreamSessionConfig(
                videoCodec: videoCodec,
                resolution: Self.resolution(for: streamQuality),
                frameRate: fpsValue
            )
            let session = StreamSession(
                streamSessionConfig: streamConfig,
                deviceSelector: deviceSelector
            )

            // Observe errors
            errorListenerToken = session.errorPublisher.listen {
                error in
                NSLog("[MWDAT] StreamSession error: \(error)")
            }

            // Store the session and connect event handlers
            streamSession = session
            streamStateHandler.session = session
            streamErrorHandler.session = session

            // Subscribe to video frames — push CVPixelBuffer directly, no encoding
            videoListenerToken = session.videoFramePublisher.listen {
                [weak self] videoFrame in
                guard let self else {
                    return
                }
                self.processAndSendFrame(videoFrame)
            }

            // Start the session
            do {
                await session.start()

                if uuidString == nil, let activeDevice = deviceSelector.activeDevice {
                    NSLog("[MWDAT] AutoDeviceSelector connected to device: \(activeDevice)")
                }

                result(texId)
            } catch {
                // Clean up on failure
                await cleanupSession()
                result(FlutterError(code: "STREAM_SESSION_ERROR", message: error.localizedDescription, details: nil))
            }
        }
    }

    func stopStreamSession(call _: FlutterMethodCall, result: @escaping FlutterResult) {
        Task {
            @MainActor in
            guard streamSession != nil else {
                result(FlutterError(code: "SESSION_NOT_FOUND", message: "No active stream session", details: nil))
                return
            }

            await cleanupSession()
            result(true)
        }
    }

    func capturePhoto(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        let formatStr = args?["format"] as? String ?? "jpeg"
        let captureFormat: MWDATCamera.PhotoCaptureFormat = (formatStr == "heic") ? .heic : .jpeg

        Task {
            @MainActor in
            guard let streamSession else {
                result(FlutterError(code: "SESSION_NOT_FOUND", message: "No active stream session", details: nil))
                return
            }

            var didRespond = false
            var listenerToken: AnyListenerToken?

            listenerToken = streamSession.photoDataPublisher.listen {
                photoData in
                guard !didRespond else {
                    return
                }
                didRespond = true
                Task {
                    await listenerToken?.cancel()
                }

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
                Task {
                    await listenerToken?.cancel()
                }
                result(FlutterError(code: "CAPTURE_NOT_READY", message: "Capture request was not accepted.", details: nil))
            }
        }
    }

    func captureStreamFrame(call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? [String: Any]
        let quality = (args?["quality"] as? Int) ?? 70

        guard let texture = pixelBufferTexture,
              let jpegData = texture.copyAsJpegData(quality: quality)
        else {
            result(nil)
            return
        }
        result(FlutterStandardTypedData(bytes: jpegData))
    }

    func getRegistrationState(result: @escaping FlutterResult) {
        Task {
            @MainActor in
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

    private static func resolution(forquality _: StreamQuality) -> StreamingResolution {
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
