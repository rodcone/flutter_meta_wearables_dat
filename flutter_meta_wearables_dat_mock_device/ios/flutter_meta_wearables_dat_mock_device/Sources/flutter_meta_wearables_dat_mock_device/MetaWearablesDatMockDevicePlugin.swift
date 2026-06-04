import Flutter
import UIKit
import MWDATCore
import MWDATMockDevice
import AVFoundation
import CoreMedia

/// Optional MockDeviceKit add-on for `flutter_meta_wearables_dat`.
///
/// Hosts a dedicated `flutter_meta_wearables_dat_mock_device` method channel
/// so the core plugin has zero awareness of MockDeviceKit and production
/// builds that don't depend on this package never link `MWDATMockDevice`.
///
/// Stream-session teardown coordination: when this plugin disables the kit or
/// unpairs a device, the core plugin's `startDeviceAvailabilityMonitoring`
/// observes the resulting active-device change and tears its `DeviceSession`
/// down asynchronously — no direct cross-plugin call is needed.
public class MetaWearablesDatMockDevicePlugin: NSObject, FlutterPlugin {
  /// Current mock device config. Applied whenever MockDeviceKit is enabled.
  private var mockDeviceConfig: MockDeviceKitConfig = MockDeviceKitConfig()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "flutter_meta_wearables_dat_mock_device",
      binaryMessenger: registrar.messenger()
    )
    let instance = MetaWearablesDatMockDevicePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "configure":
      configure(call: call, result: result)
    case "disable":
      disable(result: result)
    case "pairRayBanMeta":
      pairRayBanMeta(result: result)
    case "unpairRayBanMeta":
      unpairRayBanMeta(call: call, result: result)
    case "setPermission":
      setPermission(call: call, result: result)
    case "setPermissionRequestResult":
      setPermissionRequestResult(call: call, result: result)
    case "powerOn":
      mockDeviceAction(call: call, result: result) { device in
        device.powerOn()
      }
    case "powerOff":
      mockDeviceAction(call: call, result: result) { device in
        device.powerOff()
      }
    case "don":
      mockDeviceAction(call: call, result: result) { device in
        device.don()
      }
    case "doff":
      mockDeviceAction(call: call, result: result) { device in
        device.doff()
      }
    case "setCameraFeed":
      setCameraFeed(call: call, result: result)
    case "setCameraFacing":
      setCameraFacing(call: call, result: result)
    case "setCapturedImage":
      setCapturedImage(call: call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - MockDeviceKit lifecycle

  private func ensureMockKitEnabled() {
    if !MockDeviceKit.shared.isEnabled {
      MockDeviceKit.shared.enable(config: mockDeviceConfig)
    }
  }

  private func configure(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any]
    let initiallyRegistered = (args?["initiallyRegistered"] as? Bool) ?? true
    let initialPermissionsGranted = (args?["initialPermissionsGranted"] as? Bool) ?? true
    mockDeviceConfig = MockDeviceKitConfig(
      initiallyRegistered: initiallyRegistered,
      initialPermissionsGranted: initialPermissionsGranted
    )

    Task { @MainActor in
      // Re-enable to apply the new config (disable is a no-op when off).
      // The core plugin's activeDeviceStream observer will tear down any
      // running stream session when the underlying mock device disappears.
      if MockDeviceKit.shared.isEnabled {
        MockDeviceKit.shared.disable()
      }
      MockDeviceKit.shared.enable(config: mockDeviceConfig)
      result(true)
    }
  }

  private func disable(result: @escaping FlutterResult) {
    Task { @MainActor in
      if MockDeviceKit.shared.isEnabled {
        MockDeviceKit.shared.disable()
      }
      result(true)
    }
  }

  private func pairRayBanMeta(result: @escaping FlutterResult) {
    Task { @MainActor in
      ensureMockKitEnabled()
      let mockDevice = MockDeviceKit.shared.pairRaybanMeta()
      result(mockDevice.deviceIdentifier)
    }
  }

  private func unpairRayBanMeta(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any], let uuidString = args["deviceUUID"] as? String else {
      result(FlutterError(code: "INVALID_ARGS", message: "deviceUUID missing", details: nil))
      return
    }
    Task { @MainActor in
      let devices = MockDeviceKit.shared.pairedDevices
      guard let device = devices.first(where: { $0.deviceIdentifier == uuidString }) else {
        result(FlutterError(code: "DEVICE_NOT_FOUND", message: "No mock device with uuid \(uuidString)", details: nil))
        return
      }
      MockDeviceKit.shared.unpairDevice(device)
      result(true)
    }
  }

  private func mockDeviceAction(
    call: FlutterMethodCall,
    result: @escaping FlutterResult,
    perform: @escaping @MainActor (any MWDATMockDevice.MockDevice) -> Void
  ) {
    guard let args = call.arguments as? [String: Any], let uuidString = args["deviceUUID"] as? String else {
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

  // MARK: - Mock permissions

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

  private func setPermission(call: FlutterMethodCall, result: @escaping FlutterResult) {
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

  private func setPermissionRequestResult(call: FlutterMethodCall, result: @escaping FlutterResult) {
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

  // MARK: - Mock camera feed

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

  private func setCameraFeed(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
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

        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: videoPath) {
          result(FlutterError(code: "FILE_NOT_FOUND", message: "Video file not found at path: \(videoPath)", details: nil))
          return
        }

        // Validate video codec — must be HEVC/H.265.
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

  private func setCameraFacing(call: FlutterMethodCall, result: @escaping FlutterResult) {
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

  private func setCapturedImage(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any],
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
        result(true)
      }
    }
  }
}
