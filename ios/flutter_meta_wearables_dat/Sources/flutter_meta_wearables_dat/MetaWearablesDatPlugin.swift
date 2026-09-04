import Flutter
import UIKit
import MWDATCore
import MWDATCamera
import AVFoundation
import CoreMedia
import VideoToolbox

public class MetaWearablesDatPlugin: NSObject, FlutterPlugin {
  // Device session (DAT 0.7.0): created lazily on first startStreamSession
  // call using the shared selector. Kept alive across stream start/stop so
  // toggling streaming is fast. Torn down only when the underlying device
  // disappears or when the plugin is disabled.
  //
  // Identifier of the pinned device, or nil for auto-select. Honored by
  // `makeDeviceSelector()` at every construction site so a blind rebuild
  // can't silently drop the pin.
  private var pinnedDeviceId: DeviceIdentifier?
  // Shared selector. When pinned, an `AutoDeviceSelector` *constrained by a
  // filter* to the chosen device — NOT a `SpecificDeviceSelector`, whose iOS
  // `activeDeviceStream()` emits once then completes (which would stop the
  // availability watchdog from ever observing the pinned device disconnect).
  // A filtered `AutoDeviceSelector` keeps a continuous stream that emits nil
  // when the pinned device drops. Lazy so it isn't built on the init path.
  private lazy var deviceSelector: AutoDeviceSelector = makeDeviceSelector()
  /// Builds the shared selector honoring `pinnedDeviceId`.
  private func makeDeviceSelector() -> AutoDeviceSelector {
    guard let id = pinnedDeviceId else {
      return AutoDeviceSelector(wearables: Wearables.shared)
    }
    return AutoDeviceSelector(
      wearables: Wearables.shared,
      filter: { $0.identifier == id }
    )
  }
  // Guards concurrent startStreamSession calls: a second start that tore down
  // the first's in-flight session would leave the first awaiting `.started`.
  private var isStartingSession = false
  private var deviceSession: DeviceSession?
  private var deviceSessionStateTask: Task<Void, Never>?
  private var deviceSessionErrorTask: Task<Void, Never>?
  private var deviceAvailabilityTask: Task<Void, Never>?
  // Debounces the availability watchdog below. `activeDeviceStream()` yields nil
  // as soon as no device satisfies `AutoDeviceSelector`'s eligibility test, and
  // that test requires `LinkState.connected` — so a momentary `.connecting`
  // blip emits nil even though the device never went away. The SDK's own stream
  // handler is more forgiving than that: it stops the stream only on a genuine
  // `.disconnected`. Tearing the whole DeviceSession down on the first nil made
  // the plugin strictly more trigger-happy than the SDK on the same signal, and
  // nothing re-armed afterwards.
  private var pendingAvailabilityTeardown: Task<Void, Never>?
  private let deviceAvailabilityGrace: TimeInterval = 2.0
  // Last error observed on the DeviceSession's errorStream. Used to surface
  // the genuine failure reason when the session stops before reaching
  // `.started` (instead of a fabricated `noEligibleDevice`). Cleared at the
  // start of every `ensureDeviceSessionStarted` attempt.
  private var lastDeviceSessionError: DeviceSessionError?
  // Upper bound on how long `ensureDeviceSessionStarted` waits for a session to
  // reach `.started`. `stateStream()` has no deadline of its own, so a session
  // the SDK leaves in a non-terminal state forever would otherwise hang the
  // awaiting Dart future indefinitely.
  private let deviceSessionStartTimeout: TimeInterval = 20.0
  // Upper bound on how long `teardownStreamOnly` waits for a stopped stream to
  // actually reach `.stopped` before releasing its references. See the comment
  // there: letting go early cancels the SDK's stop cascade mid-flight.
  private let streamStopTimeout: TimeInterval = 3.0
  private let deviceSessionStopTimeout: TimeInterval = 10.0
  // After a pin change the shared selector is rebuilt and resolves its active
  // device asynchronously; `createSession` against an unresolved selector
  // returns `noEligibleDevice`. Bound how long we wait for the pinned device
  // to resolve before attempting the session.
  private let selectorResolveTimeout: TimeInterval = 8.0
  // Timestamp of the last `AutoDeviceSelector` rebuild (see
  // `rebuildDeviceSelectorIfBlind`). A freshly-rebuilt selector needs a moment
  // to discover devices; this debounces back-to-back rebuilds so we don't
  // discard a still-discovering selector and prolong the no-device window.
  private var lastSelectorRebuild: Date?
  private let selectorRebuildCooldown: TimeInterval = 3.0
  // Serializes `rebuildDeviceSelectorIfBlind` across its now-multiple concurrent
  // callers — see the guard there for why the cooldown alone isn't enough.
  private var isRebuildingSelector = false
  // Most recent device-identifier list observed on
  // `Wearables.shared.devicesStream()`. The SDK surfaces devices reactively and
  // only *after* a camera-permission grant; Meta's CameraAccess sample keeps a
  // `devicesStream()` subscription alive from `configure()` onward so the
  // discovery pipeline stays warm. The plugin used to observe only the
  // selector's `activeDeviceStream()` — never the raw device list — so a device
  // that surfaced post-grant was caught by nothing, leaving `getDevices()` empty
  // and the selector blind. `startDeviceListMonitoring()` fixes that: it feeds
  // this cache and deterministically re-warms the selector when devices appear.
  private var knownDeviceIds: [DeviceIdentifier] = []
  private var devicesStreamTask: Task<Void, Never>?
  // True once the live `devicesStream()` subscription has delivered at least
  // one value. Distinguishes "`knownDeviceIds` is empty because nothing has
  // emitted yet" (cold start) from "the SDK confirmed there are no devices" —
  // only the latter justifies the already-granted fast path returning without
  // waiting. Reset whenever the subscription is (re)launched.
  private var didReceiveDeviceListEmission = false
  // Upper bound on how long `awaitDeviceAfterPermissionGrant` waits for a device
  // to resolve after a camera-permission grant. Comfortably exceeds
  // `selectorRebuildCooldown` so a blind selector can be rebuilt and resolve
  // within the window. Granting permission implies the glasses are connected,
  // so a device should appear well inside this bound.
  private let permissionDeviceResolveTimeout: TimeInterval = 8.0

  // Stream session state (single session at a time)
  //
  // DAT 0.9.0 consolidated stream capability ownership into `Camera`: the
  // session hands out a `Camera`, which owns the `Stream`. We keep both — the
  // `Camera` because it's the handle that detaches the capability, and its
  // non-optional `stream` because that's what every listener and handler binds
  // to. They are set and cleared together (see `teardownStreamOnly`).
  private var camera: MWDATCamera.Camera?
  private var streamSession: MWDATCamera.Stream?
  private var videoListenerToken: (any MWDATCore.AnyListenerToken)?
  // Serializes `teardownStreamOnly` — it is reachable from the method channel,
  // the device-session observer and the start-failure paths, and callers must
  // await an in-flight teardown rather than skip it.
  private var teardownTask: Task<Void, Never>?
  private var teardownSeq = 0
  private var frameCounter: Int = 0
  private var currentTargetFPS: Double = 30.0
  private var lastFrameSendTime: Date?
  private var pixelBufferTexture: PixelBufferTexture?
  private var textureId: Int64?
  private var currentVideoCodec: MWDATCamera.VideoCodec = .raw
  private var decompressionSession: VTDecompressionSession?
  private var lastFormatDescription: CMFormatDescription?
  // Raw parameter-set payloads (VPS/SPS/PPS) the live decompression session
  // was built from, compared against the in-band sets each sync frame carries
  // so a bandwidth-adaptation switch recreates the session. Empty whenever no
  // session exists.
  private var sessionParameterSets: [Data] = []
  // The format description the live session was created from. Samples whose
  // attached description differs are rewrapped with this one before decode.
  private var sessionFormatDescription: CMFormatDescription?
  // The SDK delivers video frames on a thread pool, not a serial queue.
  // Concurrent decode calls can feed the VTDecompressionSession out of
  // order, and one out-of-order P-frame breaks the HEVC reference chain —
  // with no periodic keyframe in the stream, decode never recovers
  // (-12909 on every frame). All frame processing hops onto this serial
  // queue to keep decode order identical to arrival order.
  private let frameQueue = DispatchQueue(
    label: "io.rodcone.mwdat.video-frames",
    qos: .userInteractive
  )
  // Background/foreground state — gates frame processing and decoder lifecycle
  private var isInBackground: Bool = false
  // Texture registry
  private var textureRegistry: FlutterTextureRegistry?
  // Stream event handlers
  private var streamStateHandler = StreamStateStreamHandler()
  private var streamErrorHandler = StreamErrorStreamHandler()
  private var videoStreamSizeHandler = VideoStreamSizeStreamHandler()
  // Active-device + per-device-state handlers. Stored (not throwaway) so the
  // `restartActiveDeviceMonitoring` method channel can relaunch their stream
  // loops after a disconnect/re-register cycle. Assigned in `register(with:)`.
  private var activeDeviceHandler: ActiveDeviceStreamHandler?
  private var deviceStateHandler: DeviceStateStreamHandler?

  // Background streaming — opt-in AVAudioSession keep-alive. When enabled, the
  // plugin keeps emitting frames to the video_frames event channel regardless
  // of UI visibility. The hardware HEVC decoder is still invalidated on
  // background entry and recreated on foreground (iOS forbids GPU access from
  // backgrounded apps).
  private let backgroundController = BackgroundStreamingController()
  private let videoFrameHandler = VideoFrameStreamHandler()
  /// Single source of truth for background/foreground transitions. See
  /// `AppLifecycleObserver` for why this does not use `addApplicationDelegate`
  /// or `addSceneDelegate`.
  private let lifecycleObserver = AppLifecycleObserver()
  /// Keeps the process scheduled long enough for a background-triggered
  /// teardown to reach the glasses. `.invalid` when none is held.
  private var backgroundStopTaskId: UIBackgroundTaskIdentifier = .invalid
  /// Set when the assertion expires, so the stop-confirmation poll in
  /// `performTeardownStreamOnly` gives up instead of burning the last of our
  /// budget on a wait that cannot finish.
  private var abortStopWait = false

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_meta_wearables_dat", binaryMessenger: registrar.messenger())
    let instance = MetaWearablesDatPlugin()
    instance.textureRegistry = registrar.textures()
    registrar.addMethodCallDelegate(instance, channel: channel)
    // Kept as a secondary input only. Flutter stops forwarding these once the
    // host adopts UISceneDelegate, so `AppLifecycleObserver` — not this — is
    // what actually guarantees delivery. Both funnel into the same latch, so a
    // host that delivers both is deduplicated rather than double-handled.
    registrar.addApplicationDelegate(instance)
    // Event channel for registration state updates
    let registrationStateChannel = FlutterEventChannel(name: "flutter_meta_wearables_dat/registration_state", binaryMessenger: registrar.messenger())
    registrationStateChannel.setStreamHandler(RegistrationStateStreamHandler())
    // Event channel for active device availability updates
    let activeDeviceChannel = FlutterEventChannel(name: "flutter_meta_wearables_dat/active_device", binaryMessenger: registrar.messenger())
    let activeDeviceHandler = ActiveDeviceStreamHandler(deviceSelectorProvider: { [weak instance] in
      // Fall back to a fresh selector only if the plugin has been torn down —
      // in normal operation the shared instance is always used so the active
      // device state is seeded without re-discovery.
      instance?.deviceSelector ?? AutoDeviceSelector(wearables: Wearables.shared)
    })
    instance.activeDeviceHandler = activeDeviceHandler
    activeDeviceChannel.setStreamHandler(activeDeviceHandler)
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
    let deviceStateHandler = DeviceStateStreamHandler(deviceSelectorProvider: { [weak instance] in
      instance?.deviceSelector ?? AutoDeviceSelector(wearables: Wearables.shared)
    })
    instance.deviceStateHandler = deviceStateHandler
    deviceStateChannel.setStreamHandler(deviceStateHandler)

    Task { @MainActor in
      instance.lifecycleObserver.onDidEnterBackground = { [weak instance] in
        instance?.handleDidEnterBackground()
      }
      instance.lifecycleObserver.onWillEnterForeground = { [weak instance] in
        instance?.handleWillEnterForeground()
      }
      instance.lifecycleObserver.start()

      try? Wearables.configure()
      // Keep a lifetime subscription on the SDK device list (Meta's canonical
      // pattern, started right after `configure()`) so discovery stays warm and
      // devices that surface after a permission grant are actually observed.
      instance.startDeviceListMonitoring()
      instance.startDeviceAvailabilityMonitoring()
    }
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
      case "requestAndroidPermissions":
        // No-op on iOS — Android-only runtime permissions
        result(true)
      case "restartActiveDeviceMonitoring":
        // Relaunch the active-device + device-state stream loops, which the SDK
        // terminates on unregistration. Dart calls this after returning from
        // Meta AI so streaming can resume after a disconnect/re-register cycle
        // without an app restart. Also relaunch the plugin's internal
        // availability watchdog — its `for await` dies with the SDK stream and
        // would otherwise stay dead for the rest of the process. When the
        // shared selector has gone blind (typical right after a first
        // registration — see `rebuildDeviceSelectorIfBlind`), it is recreated
        // and the loops are force-restarted onto the new instance.
        Task { @MainActor in
          // The SDK terminates its device streams on unregistration — including
          // `devicesStream()`, which feeds `knownDeviceIds` and drives the
          // selector re-warm. Relaunch that lifetime subscription here (it's
          // idempotent: `startDeviceListMonitoring` cancels any live task first)
          // so a disconnect/re-register cycle doesn't leave the device-list
          // cache permanently stale — mirroring the sibling availability loop.
          self.startDeviceListMonitoring()
          let rebuilt = await self.rebuildDeviceSelectorIfBlind()
          self.activeDeviceHandler?.restartMonitoring(force: rebuilt)
          self.deviceStateHandler?.restartMonitoring(force: rebuilt)
          if !rebuilt {
            self.startDeviceAvailabilityMonitoring()
          }
          result(true)
        }
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
      case "getDevices":
        getDevices(result: result)
      case "enableBackgroundStreaming":
        enableBackgroundStreaming(result: result)
      case "disableBackgroundStreaming":
        disableBackgroundStreaming(result: result)
      case "isBackgroundStreamingEnabled":
        result(backgroundController.isEnabled)
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
    // The controller does its AVAudioSession work off the main thread, so the
    // result is delivered from its completion — hopped back to main because
    // FlutterResult must be called there.
    backgroundController.enable { error in
      DispatchQueue.main.async {
        guard let error else {
          result(nil)
          return
        }
        result(FlutterError(
          code: "BACKGROUND_STREAMING_ERROR",
          message: "Failed to enable background streaming: \(error.localizedDescription). Verify the host app's Info.plist declares the 'audio' UIBackgroundMode.",
          details: nil
        ))
      }
    }
  }

  private func disableBackgroundStreaming(result: @escaping FlutterResult) {
    // Resolved from the completion rather than immediately: the deactivation
    // runs on the controller's queue, and answering Dart before it lands lets
    // the app background and be suspended with the session still active.
    backgroundController.disable {
      DispatchQueue.main.async { result(nil) }
    }
  }

  // MARK: - Permissions

  func requestCameraPermission(result: @escaping FlutterResult) {
    Task { @MainActor in
      do {
        // Fast path: skip the prompt if permission is already granted. This is
        // best-effort — `checkPermissionStatus` throws `.noDevice` when no
        // glasses are connected (e.g. right after re-registration, since
        // unregistration revokes camera permission). We must NOT bail out in
        // that case: `requestPermission(.camera)` is exactly what re-grants the
        // permission and brings the device back into `devicesStream`, so fall
        // through to it instead of surfacing DEVICE_DISCONNECTED.
        if let currentStatus = try? await Wearables.shared.checkPermissionStatus(.camera),
           currentStatus == .granted {
          // Already granted, but the selector may still be blind (e.g. the app
          // launched already-registered and nothing has resolved a device yet).
          // Re-warm and wait briefly so a subsequent stream start succeeds —
          // but skip the wait when no device is known (nothing to resolve), so
          // a routine re-check doesn't block for the full timeout.
          await awaitDeviceAfterPermissionGrant(returnEarlyIfNoDevices: true)
          result(true)
          return
        }

        let status = try await Wearables.shared.requestPermission(.camera)
        // Convert PermissionStatus enum to Bool for Flutter
        let granted = status == .granted
        if granted {
          // The grant is exactly what brings the glasses (back) into
          // `devicesStream()`. Re-warm the selector and wait (bounded) for a
          // device to resolve so the app's next `startStreamSession` /
          // `getDevices` doesn't race the SDK and hit `noEligibleDevice` / an
          // empty list — the failure this whole change set targets.
          await awaitDeviceAfterPermissionGrant()
        }
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
      } catch let e as MWDATCore.PermissionError {
        // Mirror Android's typed-exception contract: surface no-device / Meta-AI-missing
        // / timeout / etc. as the same FlutterError codes `requestCameraPermission`
        // already emits. Returning `false` here would conflate contract failures with
        // a real "user denied" outcome on the Dart side.
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
        case .timeout:
          errorMessage = "Registration timed out. Please try again."
        case .unknown:
          errorMessage = "An unknown error occurred during registration."
        @unknown default:
          errorMessage = "Unknown registration error: \(e.description)"
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
        case .timeout:
          errorMessage = "Unregistration timed out. Please try again."
        case .unknown:
          errorMessage = "An unknown error occurred during unregistration."
        @unknown default:
          errorMessage = "Unknown unregistration error: \(e.description)"
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

  /// Recreates the shared `AutoDeviceSelector` when it has gone blind — no
  /// active device and no started session. The selector's internal monitoring
  /// task is created in its `init`; an instance created before the app was
  /// registered (the plugin instantiates it at registrar time) can stay blind
  /// to devices that only surface after registration. Meta's CameraAccess
  /// sample only ever creates its selector post-registration; rebuilding on
  /// the post-registration `restartActiveDeviceMonitoring` call mirrors that.
  /// Returns `true` when the selector was rebuilt so callers can
  /// force-restart loops still attached to the old instance.
  @MainActor
  private func rebuildDeviceSelectorIfBlind() async -> Bool {
    // Re-entrancy guard. This method now has two concurrent callers (the
    // devices-stream loop and the post-permission wait) on top of the existing
    // `restartActiveDeviceMonitoring` path. There is an `await` between the
    // cooldown check and the `lastSelectorRebuild` write below, so without this
    // flag two entrants could both pass the guards while one is suspended in
    // `teardownDeviceSession()` and double-rebuild. The check-and-set is atomic
    // on the main actor (no `await` between them).
    if isRebuildingSelector {
      return false
    }
    if let session = deviceSession, session.state == .started {
      return false
    }
    guard deviceSelector.activeDevice == nil else {
      return false
    }
    // Debounce: a just-rebuilt selector hasn't had time to discover the active
    // device yet, so it still reports `activeDevice == nil`. The example app
    // calls `restartActiveDeviceMonitoring` twice in quick succession on a
    // fresh registration (the registration-state transition plus `handleUrl`'s
    // finally), and registration bursts can fire it more. Without this guard
    // each call would discard the previous selector mid-discovery, restarting
    // discovery from scratch and prolonging the very no-device window the
    // rebuild exists to fix. The cooldown still allows a genuine retry later if
    // the new selector is itself slow to discover.
    if let last = lastSelectorRebuild,
       Date().timeIntervalSince(last) < selectorRebuildCooldown {
      return false
    }
    isRebuildingSelector = true
    defer { isRebuildingSelector = false }
    // Any idle/stopped leftover session is bound to the old selector — drop
    // it so the next startStreamSession creates against the fresh one.
    await teardownDeviceSession()
    deviceSelector = makeDeviceSelector()
    lastSelectorRebuild = Date()
    startDeviceAvailabilityMonitoring()
    return true
  }

  /// Monitors `activeDeviceStream` and tears the DeviceSession down whenever
  /// the active device becomes `nil`. Launched once in `register`.
  @MainActor
  private func startDeviceAvailabilityMonitoring() {
    deviceAvailabilityTask?.cancel()
    // A pending teardown belongs to the selector we're replacing; letting it
    // fire would act on the old selector's verdict.
    cancelAvailabilityTeardown()
    deviceAvailabilityTask = Task { [weak self] in
      guard let self else { return }
      for await deviceId in self.deviceSelector.activeDeviceStream() {
        if deviceId == nil {
          self.scheduleAvailabilityTeardown()
        } else {
          self.cancelAvailabilityTeardown()
        }
      }
    }
  }

  /// Arms the grace period before acting on a `nil` active device. A device id
  /// arriving before it elapses cancels the teardown; otherwise we re-check the
  /// selector and only tear down if it is still blind.
  @MainActor
  private func scheduleAvailabilityTeardown() {
    guard pendingAvailabilityTeardown == nil else { return }
    let grace = deviceAvailabilityGrace
    pendingAvailabilityTeardown = Task { [weak self] in
      try? await Task.sleep(for: .milliseconds(grace * 1000))
      guard let self, !Task.isCancelled else { return }
      self.pendingAvailabilityTeardown = nil
      // Re-check rather than trust the emission that armed us: the device may
      // have come back during the grace period without a new emission racing us.
      guard self.deviceSelector.activeDevice == nil else { return }
      await self.teardownDeviceSession()
    }
  }

  @MainActor
  private func cancelAvailabilityTeardown() {
    pendingAvailabilityTeardown?.cancel()
    pendingAvailabilityTeardown = nil
  }

  /// Keeps a lifetime subscription on `Wearables.shared.devicesStream()` so the
  /// SDK's device discovery stays warm and the plugin always holds an
  /// up-to-date device list. This mirrors Meta's CameraAccess sample, which
  /// subscribes immediately after `configure()`. It is the missing observer
  /// that left `getDevices()` empty and the selector blind after a camera
  /// permission grant: glasses only surface on `devicesStream()` *after* a
  /// grant, and nothing in the plugin used to watch that stream. When devices
  /// appear while the shared selector is still blind, re-warm it so the active
  /// device resolves deterministically rather than via a racy retry.
  @MainActor
  private func startDeviceListMonitoring() {
    devicesStreamTask?.cancel()
    // A relaunched subscription hasn't confirmed the current device list yet,
    // so an empty cache is once again "unknown", not "no devices". Drop the
    // previous emission too so callers can't observe stale IDs while the new
    // stream is still waiting for its first value.
    knownDeviceIds = []
    didReceiveDeviceListEmission = false
    devicesStreamTask = Task { [weak self] in
      guard let self else { return }
      for await ids in Wearables.shared.devicesStream() {
        if Task.isCancelled { return }
        self.didReceiveDeviceListEmission = true
        self.knownDeviceIds = ids.filter { !$0.isEmpty }
        if !self.knownDeviceIds.isEmpty {
          await self.rewarmSelectorForNewlyAppearedDevices()
        }
      }
    }
  }

  /// Rebuilds the shared selector (and rebinds its observers) when devices have
  /// appeared but the selector is still blind. Reuses `rebuildDeviceSelectorIfBlind`
  /// — which no-ops when a session is started, the selector already has an
  /// active device, or a rebuild happened within the cooldown — so concurrent
  /// callers (the devices-stream loop and `awaitDeviceAfterPermissionGrant`)
  /// can't thrash the selector.
  @MainActor
  private func rewarmSelectorForNewlyAppearedDevices() async {
    let rebuilt = await rebuildDeviceSelectorIfBlind()
    if rebuilt {
      activeDeviceHandler?.restartMonitoring(force: true)
      deviceStateHandler?.restartMonitoring(force: true)
    }
  }

  /// After a camera-permission grant the glasses (re)surface on
  /// `devicesStream()`. Give the SDK a bounded window to discover a device and
  /// the shared selector to resolve one — re-warming the selector if it's blind
  /// — so the app's next `startStreamSession` / `getDevices` doesn't race the
  /// SDK. Returns as soon as a device resolves; otherwise after the timeout.
  ///
  /// Pass `returnEarlyIfNoDevices: true` on the already-granted fast path: a
  /// grant that already happened would have surfaced the glasses on
  /// `devicesStream()`, so a *confirmed* empty device list there means there is
  /// genuinely nothing to wait for (glasses off / out of range) and we return
  /// immediately rather than burning the full timeout on a routine re-check.
  /// "Confirmed" is load-bearing: the early return is gated on
  /// `didReceiveDeviceListEmission`, so a cache that is empty only because the
  /// subscription hasn't delivered its first value yet still waits — otherwise
  /// the fast path could return before the list arrives and the selector warms.
  /// On a *fresh* grant we always keep waiting: the device is expected
  /// imminently.
  @MainActor
  private func awaitDeviceAfterPermissionGrant(returnEarlyIfNoDevices: Bool = false) async {
    let deadline = Date().addingTimeInterval(permissionDeviceResolveTimeout)
    while Date() < deadline {
      if deviceSelector.activeDevice != nil { return }
      if knownDeviceIds.isEmpty {
        // Only bail when an emission has actually confirmed the empty list; a
        // pre-first-emission empty cache is "unknown", so fall through and wait.
        if returnEarlyIfNoDevices, didReceiveDeviceListEmission { return }
      } else {
        // Devices are known but the (pre-registration) selector hasn't resolved
        // one — rebuild it deterministically. The cooldown inside
        // `rebuildDeviceSelectorIfBlind` is shorter than this timeout, so even
        // if a rebuild was just debounced it will go through on a later pass.
        await rewarmSelectorForNewlyAppearedDevices()
        if deviceSelector.activeDevice != nil { return }
      }
      // The rewarm above can run a teardown + selector rebuild; re-check the
      // deadline before sleeping so a late iteration doesn't overshoot it.
      if Date() >= deadline { return }
      try? await Task.sleep(for: .milliseconds(200))
    }
  }

  /// Returns a DeviceSession in `.started` state, creating one if needed.
  /// Mirrors the pattern in Meta's CameraAccess sample (DeviceSessionManager).
  @MainActor
  private func ensureDeviceSessionStarted() async throws -> DeviceSession {
    if let existing = deviceSession, existing.state == .started {
      return existing
    }

    // Each attempt starts with a clean error slate so a stale error from a
    // previous attempt can't masquerade as this one's failure reason.
    lastDeviceSessionError = nil

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
      return try await awaitSessionStarted(session, stateStream: stateStream)
    }

    // Session exists but not yet `.started`.
    guard let session = deviceSession else {
      throw DeviceSessionError.noEligibleDevice
    }
    // Capture the state stream BEFORE start() so we don't miss transitions.
    let stateStream = session.stateStream()
    if session.state == .idle {
      // A previous start() threw (e.g. noEligibleDevice while the device was
      // still connecting) and left the session `.idle`. The SDK documents
      // start() as retryable from `.idle` — without this, the wait below would
      // hang forever on a session nothing ever starts, wedging every
      // subsequent startStreamSession call.
      try session.start()
    }
    return try await awaitSessionStarted(session, stateStream: stateStream)
  }

  /// Waits for `session` to reach `.started`, racing the device session's
  /// `stateStream` against `deviceSessionStartTimeout`.
  ///
  /// The `.idle` retry in `ensureDeviceSessionStarted` re-kicks only one of the
  /// non-terminal states the SDK can leave a session in (`.starting`,
  /// `.paused`, `.stopping` also exist). `stateStream()` carries no deadline, so
  /// without this timeout a session wedged in any of those states would hang
  /// the awaiting Dart future forever — the exact failure class this changeset
  /// set out to kill. On timeout the wedged session is torn down so the next
  /// attempt starts from a clean slate rather than re-entering the same wait.
  @MainActor
  private func awaitSessionStarted(
    _ session: DeviceSession,
    stateStream: AsyncStream<DeviceSessionState>
  ) async throws -> DeviceSession {
    let timeout = deviceSessionStartTimeout
    let outcome = await withTaskGroup(of: SessionWaitOutcome.self) { group in
      group.addTask {
        for await state in stateStream {
          if state == .started { return .started }
          if state == .stopped { return .stopped }
        }
        return .streamEnded
      }
      group.addTask {
        try? await Task.sleep(for: .milliseconds(timeout * 1000))
        return .timedOut
      }
      let first = await group.next() ?? .streamEnded
      group.cancelAll()
      return first
    }

    switch outcome {
    case .started:
      return session
    case .stopped:
      // `observeDeviceSession` also reacts to `.stopped` and clears state; just
      // drop our reference and surface the genuine error if one was seen.
      deviceSession = nil
      throw lastDeviceSessionError ?? DeviceSessionError.noEligibleDevice
    case .timedOut:
      // Nothing will advance a wedged session — stop it and cancel its
      // observers so the next startStreamSession creates a fresh one.
      await teardownDeviceSession()
      throw lastDeviceSessionError ?? DeviceSessionError.unexpectedError(
        description: "Device session did not reach .started within \(Int(timeout))s")
    case .streamEnded:
      // DAT 0.9.0: `stateStream()` delivers the terminal `.stopped` and then
      // *finishes* (a stream created after stop finishes immediately), so an
      // ended stream means the session died — surface the genuine error the
      // error stream reported, like the `.stopped` and `.timedOut` branches.
      deviceSession = nil
      throw lastDeviceSessionError ?? DeviceSessionError.unexpectedError(
        description: "Device session state stream ended before reaching .started")
    }
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
        self?.lastDeviceSessionError = error
        self?.streamErrorHandler.send(deviceSessionError: error)
      }
    }
  }

  /// Tears down the active stream but leaves the DeviceSession alive, so the
  /// next `startStreamSession` is a fast `addCamera` on the existing session.
  ///
  /// Callers are serialized against any teardown already in flight, then run
  /// their own. Skipping instead — the previous behaviour — let
  /// `stopStreamSession` report success without having stopped anything: a stop
  /// arriving while an earlier teardown was still waiting returned immediately,
  /// leaving a stream that had been started in the meantime running.
  @MainActor
  private func teardownStreamOnly() async {
    if let inFlight = teardownTask {
      await inFlight.value
    }
    teardownSeq += 1
    let mySeq = teardownSeq
    let task = Task { @MainActor in await self.performTeardownStreamOnly() }
    teardownTask = task
    await task.value
    // Only the most recent starter clears the slot, so a caller that queued
    // behind us isn't dropped from the chain.
    if teardownSeq == mySeq { teardownTask = nil }
  }

  @MainActor
  private func performTeardownStreamOnly() async {
    MWDATLog.log("teardownStreamOnly — stopping camera, awaiting stop cascade")

    // Capture identities and stop BEFORE the first suspension below. While this
    // method is suspended the stream must already be `.stopping`: otherwise a
    // concurrent `startStreamSession` takes the "a stream is already active"
    // branch and hands Dart back a texture id this teardown is about to
    // unregister.
    let stoppingCamera = camera
    let stoppingStream = streamSession
    let stoppingTextureId = textureId

    // Detach *and* tell Dart. This teardown is reachable from paths the SDK
    // never reports on (the device-availability watchdog, a DeviceSession that
    // stopped underneath us), and a silent detach left the app holding a live
    // texture id with no terminal event — a `Texture` frozen on its last frame.
    streamStateHandler.detachEmittingStopped()
    streamErrorHandler.session = nil

    // `Camera.stop()` synchronously calls `Stream.stop()` and detaches the
    // capability from the DeviceSession.
    //
    // The subtle part is what happens next. `Stream.stop()` only *posts* a
    // state-transition request; the work that actually tells the glasses to end
    // the stream — and removes the DWA capability — runs afterwards on a Task,
    // and the SDK's state machine holds the `Stream` only **weakly**. Once
    // `Camera.stop()` has detached from the session, our two ivars are the last
    // strong owners of the whole graph, so releasing them in the same turn
    // deallocates the `Stream` before that Task runs: the weak load yields nil,
    // the transition is cancelled, and nothing ever reaches the device. The
    // glasses are left holding a live capability — no stream-ended tone, and a
    // later start is rejected during `starting` with `videoStreamingError`.
    //
    // DAT 0.8.0 was immune by accident: the capability registered on the session
    // *was* the `Stream` and there was no removal API, so the DeviceSession
    // retained it for its whole life and our nil was never the last release.
    // Under 0.9.0 it is — hence the bounded wait below before letting go.
    camera?.stop()

    if let token = videoListenerToken {
      await token.cancel()
      videoListenerToken = nil
    }

    // Everything below is scoped to the resources this call started with. The
    // wait suspends for up to `streamStopTimeout`, and the capability is
    // already detached by then — so a concurrent `startStreamSession` can
    // legitimately succeed during the wait and install a *new* camera, stream
    // and texture. That's fine and worth allowing (it's a fast restart), but
    // this teardown must not then clear the newcomer's state: doing so would
    // unregister a live texture and orphan a running stream with no reference
    // left to stop it.
    if let stoppingStream {
      await awaitStreamStopped(stoppingStream)
    }

    if camera === stoppingCamera { camera = nil }
    if streamSession === stoppingStream { streamSession = nil }

    // Always unregister the texture we captured — it belongs to the stream that
    // just stopped — but only clear the *current* texture bookkeeping if nobody
    // replaced it while we waited.
    if let texId = stoppingTextureId {
      textureRegistry?.unregisterTexture(texId)
      MWDATLog.log("Unregistered texture \(texId)")
      if textureId == stoppingTextureId {
        textureId = nil
        pixelBufferTexture = nil
      }
    }

    // Frame-pipeline state is shared, so only reset it when no new stream has
    // taken over; the newcomer has already initialised it for itself.
    guard textureId == nil else { return }
    if let session = decompressionSession {
      VTDecompressionSessionInvalidate(session)
      decompressionSession = nil
      sessionParameterSets = []
    }
    frameCounter = 0
    lastFrameSendTime = nil
    videoStreamSizeHandler.reset()
  }

  /// Suspends until `stream` reaches `.stopped`, with `streamStopTimeout` as a
  /// backstop and `abortStopWait` as an early out when the background stop
  /// assertion expires. Event-driven on `statePublisher`, mirroring Meta's
  /// CameraAccess sample, which releases its stream references only on the
  /// observed `.stopped` — the SDK's stop cascade holds the `Stream` weakly,
  /// so the caller's strong reference must outlive the whole handshake or the
  /// glasses never receive the capability removal. The listener is attached
  /// before the state is checked so a transition can't slip between the two.
  @MainActor
  private func awaitStreamStopped(_ stream: MWDATCamera.Stream) async {
    var listenerToken: (any MWDATCore.AnyListenerToken)?
    let states = AsyncStream<StreamState> { continuation in
      listenerToken = stream.statePublisher.listen { state in
        continuation.yield(state)
      }
    }

    if stream.state != .stopped {
      let stopped = await withTaskGroup(of: Bool.self) { group in
        group.addTask {
          for await state in states where state == .stopped {
            return true
          }
          return false
        }
        group.addTask { [timeout = streamStopTimeout] in
          try? await Task.sleep(for: .milliseconds(timeout * 1000))
          return false
        }
        // `abortStopWait` lets an expiring background assertion cut the wait
        // short: once the OS says the budget is gone, a wait that cannot
        // complete only burns what little remains.
        group.addTask { @MainActor [weak self] in
          while !Task.isCancelled {
            guard let self, !self.abortStopWait else { return false }
            try? await Task.sleep(for: .milliseconds(100))
          }
          return false
        }
        let first = await group.next() ?? false
        group.cancelAll()
        return first
      }
      if !stopped, stream.state != .stopped {
        MWDATLog.log(
          "stream did not reach .stopped within \(streamStopTimeout)s (state: \(stream.state), aborted: \(abortStopWait)) — releasing anyway; the glasses may keep a stale capability")
      }
    }

    if let listenerToken {
      await listenerToken.cancel()
    }
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
      // Capture the state stream BEFORE stop() so the transition can't be
      // missed, then hold the strong reference until the session actually
      // reaches `.stopped` — same weak-executor hazard as the stream's stop
      // cascade: releasing early can cancel the SDK's session-end handshake
      // before the glasses hear about it, which also mutes the stream-ended
      // tone the glasses play on session end.
      let stateStream = session.stateStream()
      deviceSession = nil
      session.stop()
      await awaitDeviceSessionStopped(session, stateStream: stateStream)
    }
  }

  /// Suspends until `session` reaches `.stopped`, with
  /// `deviceSessionStopTimeout` as a backstop for a dead device or wedged SDK
  /// and `abortStopWait` as an early out when the background stop assertion
  /// expires.
  @MainActor
  private func awaitDeviceSessionStopped(
    _ session: DeviceSession,
    stateStream: AsyncStream<DeviceSessionState>
  ) async {
    if session.state == .stopped { return }
    let stopped = await withTaskGroup(of: Bool.self) { group in
      group.addTask {
        for await state in stateStream where state == .stopped { return true }
        return false
      }
      group.addTask { [timeout = deviceSessionStopTimeout] in
        try? await Task.sleep(for: .milliseconds(timeout * 1000))
        return false
      }
      group.addTask { @MainActor [weak self] in
        while !Task.isCancelled {
          guard let self, !self.abortStopWait else { return false }
          try? await Task.sleep(for: .milliseconds(100))
        }
        return false
      }
      let first = await group.next() ?? false
      group.cancelAll()
      return first
    }
    if !stopped, session.state != .stopped {
      MWDATLog.log(
        "device session did not reach .stopped within \(deviceSessionStopTimeout)s (state: \(session.state), aborted: \(abortStopWait)) — releasing anyway")
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

  // MARK: - App lifecycle
  //
  // These two are thin forwarders. Flutter stops calling them once the host
  // adopts UISceneDelegate, so they are a secondary input to
  // `AppLifecycleObserver`, never the primary one. The observer's latch
  // deduplicates, so a host that delivers both paths still transitions once.

  public func applicationDidEnterBackground(_ application: UIApplication) {
    Task { @MainActor in lifecycleObserver.noteDidEnterBackground() }
  }

  public func applicationWillEnterForeground(_ application: UIApplication) {
    Task { @MainActor in lifecycleObserver.noteWillEnterForeground() }
  }

  /// Runs once per genuine background transition, from whichever input saw it
  /// first.
  @MainActor
  private func handleDidEnterBackground() {
    isInBackground = true
    if let session = decompressionSession {
      VTDecompressionSessionInvalidate(session)
      decompressionSession = nil
      sessionParameterSets = []
      MWDATLog.log("VTDecompressionSession invalidated (app entered background)")
    }

    // Background streaming ON is the whole point of the opt-in: keep everything
    // alive and let the preview resume on foreground.
    guard !backgroundController.isEnabled else { return }
    // Nothing streaming means nothing to stop. Without this guard every
    // backgrounding would emit a terminal `stopped` at idle apps that merely
    // subscribed to the state channel.
    guard streamSession != nil || deviceSession != nil else { return }

    MWDATLog.log("lifecycle: stopping session (background streaming off)")
    // Tell Dart *why* before the terminal `stopped` lands, so consumers can
    // tell a deliberate stop from a fault and skip their retry logic. Emitted
    // first because `teardownStreamOnly()` detaches the error handler.
    streamErrorHandler.sendError(
      code: "stoppedForBackground",
      message: "The app was backgrounded and background streaming is not enabled.",
      bypassSuppression: true
    )
    // Everything after this point is teardown noise. The SDK emits
    // `videoStreamingError` as the pipeline comes down, which is true when the
    // stream died on its own and false when we stopped it on purpose — the app
    // asked for this by backgrounding. Bounded so a stalled teardown cannot
    // hide unrelated later errors.
    streamErrorHandler.beginBackgroundStopSuppression()

    beginBackgroundStopAssertion()
    Task { @MainActor in
      defer {
        endBackgroundStopAssertion()
        streamErrorHandler.endBackgroundStopSuppression()
      }
      // The whole DeviceSession, not just the stream — matching Meta's
      // CameraAccess sample. Stopping only the stream leaves the plugin as the
      // last strong owner of the `Stream`, which is why that path holds it
      // through `awaitStreamStopped` before releasing. Suspension
      // mid-wait would then strand a live capability on the glasses and break
      // the *next* start. Stopping the session makes that unreachable: the SDK
      // owns it, and the capability goes away with it either way.
      await teardownDeviceSession()
      MWDATLog.log("lifecycle: session stopped for background")
    }
  }

  // MARK: - Background stop assertion
  //
  // iOS suspends the process shortly after `didEnterBackground` returns. The
  // teardown below can take up to `streamStopTimeout`, so without an assertion
  // it would be frozen mid-cascade. Taken synchronously, before the `Task`, or
  // the process can be suspended before the Task's first hop even runs.

  private func beginBackgroundStopAssertion() {
    guard backgroundStopTaskId == .invalid else { return }
    abortStopWait = false
    backgroundStopTaskId = UIApplication.shared.beginBackgroundTask(
      withName: "io.rodcone.mwdat.stopStreamOnBackground"
    ) { [weak self] in
      // UIKit calls this on the main thread when our budget runs out. It must
      // be fast and it MUST end the task, or the watchdog kills the app.
      MainActor.assumeIsolated {
        guard let self else { return }
        self.abortStopWait = true
        MWDATLog.log("background stop assertion expired — abandoning stop confirmation")
        self.endBackgroundStopAssertion()
      }
    }
  }

  private func endBackgroundStopAssertion() {
    guard backgroundStopTaskId != .invalid else { return }
    UIApplication.shared.endBackgroundTask(backgroundStopTaskId)
    // Idempotent: ending an already-ended identifier trips a UIKit assertion.
    backgroundStopTaskId = .invalid
  }

  @MainActor
  private func handleWillEnterForeground() {
    isInBackground = false
    // An expired background assertion sets `abortStopWait` and nothing else
    // clears it, so without this reset one expiry would poison every later
    // stop-wait: the abort poll in `awaitStreamStopped` /
    // `awaitDeviceSessionStopped` would bail on its first check and release
    // the stream or session mid-cascade — the muted-chime / stale-capability
    // failure those waits exist to prevent.
    abortStopWait = false
    MWDATLog.log("App entering foreground — HEVC decoder will be recreated on next frame")
    // Deliberately nothing else. With background streaming off the session is
    // stopped and stays stopped: the plugin never reactivates the glasses
    // camera on its own. Do not add a resume here.
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

    // Forward the frame to Dart BEFORE the background bail-out, the FPS
    // throttle, and any decode. Recording subscribers want every frame in both
    // foreground and background, and neither branch here touches the GPU: hvc1
    // forwards the CMBlockBuffer the sample already carries, and raw reads the
    // CVPixelBuffer already attached to it.
    //
    // `emitRaw` used to live further down, past `if isInBackground { return }`
    // and past the throttle. That made two promises false at once: with
    // `VideoCodec.raw` nothing reached `videoFramesStream()` while backgrounded
    // even with background streaming on, and raw subscribers silently got a
    // throttled subset of frames while hvc1 subscribers got all of them.
    // Android has no such gate; iOS now matches it.
    if videoFrameHandler.hasListener {
      if currentVideoCodec == .hvc1 {
        videoFrameHandler.emitHvc1(sampleBuffer: videoFrame.sampleBuffer, ptsUs: ptsUs)
      } else if let rawBuffer = CMSampleBufferGetImageBuffer(videoFrame.sampleBuffer) {
        videoFrameHandler.emitRaw(pixelBuffer: rawBuffer, ptsUs: ptsUs)
      }
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

    // Decode BEFORE the FPS throttle. hvc1 frames form a reference chain:
    // skipping a single P-frame ahead of the decoder invalidates every later
    // frame until the next keyframe (-12909 kVTVideoDecoderBadDataErr), and
    // with a target FPS at or below the stream's rate the old pre-decode
    // throttle dropped roughly every other frame — the preview froze between
    // keyframes. The throttle below now gates only the texture push.
    let pixelBuffer: CVPixelBuffer?
    if currentVideoCodec == .raw {
      pixelBuffer = CMSampleBufferGetImageBuffer(videoFrame.sampleBuffer)
    } else {
      pixelBuffer = decodeCompressedFrame(videoFrame.sampleBuffer)
    }

    guard let pixelBuffer else {
      MWDATLog.log("Could not obtain pixel buffer from video frame")
      return
    }

    let width = CVPixelBufferGetWidth(pixelBuffer)
    let height = CVPixelBufferGetHeight(pixelBuffer)
    videoStreamSizeHandler.send(width: width, height: height)

    let now = Date()
    let minInterval = 1.0 / currentTargetFPS

    let timeSinceLastFrame: TimeInterval
    if let lastSendTime = lastFrameSendTime {
      timeSinceLastFrame = now.timeIntervalSince(lastSendTime)
      if timeSinceLastFrame < minInterval {
        return
      }
    } else {
      timeSinceLastFrame = 0
    }

    // Update timing + counters regardless of whether we push to the texture.
    lastFrameSendTime = now
    frameCounter += 1

    if frameCounter % 30 == 0 && timeSinceLastFrame > 0 {
      let actualFPS = 1.0 / timeSinceLastFrame
      MWDATLog.log("\(frameCounter) frames, target: \(currentTargetFPS), actual: \(String(format: "%.1f", actualFPS)) FPS")
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
      sessionFormatDescription = formatDescription
      MWDATLog.log("Created VTDecompressionSession for HEVC decoding (hardware)")
    } else {
      sessionFormatDescription = nil
      MWDATLog.log("Failed to create VTDecompressionSession: \(status)")
    }
  }

  /// Rewraps a sample's CMBlockBuffer in a new CMSampleBuffer carrying the
  /// given format description. VTDecompressionSessionDecodeFrame validates
  /// the sample's attached description against the session's — a session
  /// rebuilt from in-band parameter sets would otherwise reject every sample
  /// still carrying the SDK's stale description as bad data.
  private static func rewrap(
    _ sampleBuffer: CMSampleBuffer,
    with formatDescription: CMFormatDescription
  ) -> CMSampleBuffer? {
    guard let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
    var timing = CMSampleTimingInfo()
    CMSampleBufferGetSampleTimingInfo(sampleBuffer, at: 0, timingInfoOut: &timing)
    var sampleSize = CMBlockBufferGetDataLength(dataBuffer)
    var newBuffer: CMSampleBuffer?
    let status = CMSampleBufferCreateReady(
      allocator: kCFAllocatorDefault,
      dataBuffer: dataBuffer,
      formatDescription: formatDescription,
      sampleCount: 1,
      sampleTimingEntryCount: 1,
      sampleTimingArray: &timing,
      sampleSizeEntryCount: 1,
      sampleSizeArray: &sampleSize,
      sampleBufferOut: &newBuffer
    )
    guard status == noErr else {
      MWDATLog.log("Failed to rewrap sample buffer with session format description: \(status)")
      return nil
    }
    return newBuffer
  }

  /// Decodes a compressed CMSampleBuffer (HEVC) to a CVPixelBuffer.
  private func decodeCompressedFrame(_ sampleBuffer: CMSampleBuffer) -> CVPixelBuffer? {
    guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
      return nil
    }

    // The glasses can push a new codec configuration mid-stream (the SDK's
    // `WarpEventCoordinator.handleCodecConfig` rebuilds its CMFormatDescription
    // unconditionally), so a later sample buffer can carry a new format. A
    // session created from the old one then fails on every frame, and because
    // `decompressionSession` stays non-nil the lazy-create below never re-fires:
    // the texture freezes permanently with no error on any channel. Checked
    // only when the instance changes, because a session rebuilt from in-band
    // parameter sets (below) legitimately disagrees with the sample buffers'
    // stale attached description — re-checking every frame would recreate the
    // session from the stale description in a loop.
    if let last = lastFormatDescription, last !== formatDescription {
      if let existing = decompressionSession,
         !VTDecompressionSessionCanAcceptFormatDescription(existing, formatDescription: formatDescription) {
        MWDATLog.log("HEVC format description changed mid-stream — recreating decompression session")
        VTDecompressionSessionInvalidate(existing)
        decompressionSession = nil
        sessionParameterSets = []
      }
    }
    lastFormatDescription = formatDescription

    // The bitstream outranks the SDK's format description. The glasses adapt
    // quality to Bluetooth bandwidth a few seconds into a stream (and again
    // whenever the link degrades), announcing each switch with an in-band
    // VPS/SPS/PPS + IDR sync frame — but the SDK's format description is not
    // reliably rebuilt when that happens, so a session created from it rejects
    // every post-switch frame (kVTVideoDecoderBadDataErr), sync frames
    // included, and the preview freezes until the parameters happen to match
    // again. Verified on hardware 2026-08-25: high/30fps + hvc1 stalled ~3s
    // in, with the switch IDR itself as the first rejected frame. When a frame
    // carries the full parameter-set trio and it differs from what the live
    // session was built with, rebuild the session from the in-band sets — the
    // sync frame then decodes immediately and the switch is seamless.
    let inBandSets = Self.inBandParameterSets(of: sampleBuffer)
    if !inBandSets.isEmpty, inBandSets != sessionParameterSets {
      if let existing = decompressionSession {
        MWDATLog.log("in-band HEVC parameter sets changed — recreating decompression session")
        VTDecompressionSessionInvalidate(existing)
        decompressionSession = nil
      }
      sessionParameterSets = []
      if let inBandDescription = Self.makeFormatDescription(parameterSets: inBandSets) {
        setupDecompressionSession(formatDescription: inBandDescription)
        if decompressionSession != nil {
          sessionParameterSets = inBandSets
        }
      }
    }

    // Lazily create decompression session on first frame.
    if decompressionSession == nil {
      setupDecompressionSession(formatDescription: formatDescription)
      if decompressionSession != nil {
        sessionParameterSets = Self.parameterSets(of: formatDescription)
      }
    }

    guard let session = decompressionSession else { return nil }

    var decodeTarget = sampleBuffer
    if let sessionDescription = sessionFormatDescription,
       sessionDescription !== formatDescription,
       let rewrapped = Self.rewrap(sampleBuffer, with: sessionDescription) {
      decodeTarget = rewrapped
    }

    var outputBuffer: CVPixelBuffer?
    var failedStatus: OSStatus = noErr
    var flagOut: VTDecodeInfoFlags = []

    let status = VTDecompressionSessionDecodeFrame(
      session,
      sampleBuffer: decodeTarget,
      flags: [],  // synchronous decode
      infoFlagsOut: &flagOut,
      outputHandler: { decodeStatus, _, imageBuffer, _, _ in
        if decodeStatus == noErr {
          outputBuffer = imageBuffer
        } else {
          failedStatus = decodeStatus
        }
      }
    )

    if status != noErr {
      logDecodeFailure(sampleBuffer, status: status)
      return nil
    }

    if outputBuffer == nil {
      logDecodeFailure(sampleBuffer, status: failedStatus)
    } else if consecutiveDecodeFailures > 0 {
      MWDATLog.log("decode recovered after \(consecutiveDecodeFailures) failures — nals: \(Self.nalTypes(of: sampleBuffer))")
      consecutiveDecodeFailures = 0
    }

    return outputBuffer
  }

  private var consecutiveDecodeFailures = 0

  /// Rate-limited failure telemetry. The NAL composition of failing frames is
  /// what separates "no sync point has arrived yet" from "the decoder is
  /// rejecting sync frames" — the signature that identified the
  /// bandwidth-adaptation stall this file's in-band parameter-set handling
  /// exists for.
  private func logDecodeFailure(_ sampleBuffer: CMSampleBuffer, status: OSStatus) {
    consecutiveDecodeFailures += 1
    let n = consecutiveDecodeFailures
    let types = Self.nalTypes(of: sampleBuffer)
    let hasParamsOrIrap = types.contains { $0 >= 16 && $0 <= 34 }
    guard n <= 10 || n % 30 == 0 || hasParamsOrIrap else { return }
    MWDATLog.log("decode failure #\(n) — status: \(status), nals: \(types)")
  }

  /// Copies the sample buffer's HVCC-framed payload out of its CMBlockBuffer.
  private static func blockBufferData(of sampleBuffer: CMSampleBuffer) -> Data? {
    guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return nil }
    var totalLength = 0
    var dataPointer: UnsafeMutablePointer<Int8>?
    let status = CMBlockBufferGetDataPointer(
      blockBuffer,
      atOffset: 0,
      lengthAtOffsetOut: nil,
      totalLengthOut: &totalLength,
      dataPointerOut: &dataPointer
    )
    guard status == kCMBlockBufferNoErr, let dataPointer else { return nil }
    return Data(bytes: dataPointer, count: totalLength)
  }

  /// Walks the HVCC length-prefixed NAL units and returns the raw payloads of
  /// the parameter sets (VPS 32, SPS 33, PPS 34) appearing ahead of the first
  /// IRAP picture. Returns an empty array unless all three kinds are present —
  /// encoders repeat the PPS per access unit, and a lone PPS is not enough to
  /// build a format description from.
  private static func inBandParameterSets(of sampleBuffer: CMSampleBuffer) -> [Data] {
    guard let data = blockBufferData(of: sampleBuffer) else { return [] }
    var sets: [Data] = []
    var sawVps = false
    var sawSps = false
    var sawPps = false
    var pos = data.startIndex
    scan: while pos + 4 < data.endIndex {
      var length = 0
      for offset in 0 ..< 4 {
        length = (length << 8) | Int(data[pos + offset])
      }
      let payloadStart = pos + 4
      guard length > 0, payloadStart + length <= data.endIndex else { return [] }
      let type = (data[payloadStart] >> 1) & 0x3F
      switch type {
      case 32:
        sawVps = true
        sets.append(Data(data[payloadStart ..< payloadStart + length]))
      case 33:
        sawSps = true
        sets.append(Data(data[payloadStart ..< payloadStart + length]))
      case 34:
        sawPps = true
        sets.append(Data(data[payloadStart ..< payloadStart + length]))
      case 16 ... 23:
        break scan
      default:
        break
      }
      pos = payloadStart + length
    }
    guard sawVps, sawSps, sawPps else { return [] }
    return sets
  }

  /// Extracts the parameter-set payloads a CMFormatDescription was built from,
  /// in index order, for comparison against in-band sets.
  private static func parameterSets(of formatDescription: CMFormatDescription) -> [Data] {
    var count: size_t = 0
    var nalHeaderLength: Int32 = 0
    let countStatus = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
      formatDescription,
      parameterSetIndex: 0,
      parameterSetPointerOut: nil,
      parameterSetSizeOut: nil,
      parameterSetCountOut: &count,
      nalUnitHeaderLengthOut: &nalHeaderLength
    )
    guard countStatus == noErr, count > 0 else { return [] }
    var sets: [Data] = []
    for index in 0 ..< count {
      var pointer: UnsafePointer<UInt8>?
      var size: size_t = 0
      let status = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
        formatDescription,
        parameterSetIndex: index,
        parameterSetPointerOut: &pointer,
        parameterSetSizeOut: &size,
        parameterSetCountOut: nil,
        nalUnitHeaderLengthOut: nil
      )
      guard status == noErr, let pointer else { return [] }
      sets.append(Data(bytes: pointer, count: size))
    }
    return sets
  }

  /// Builds an hvc1 CMFormatDescription from raw in-band parameter-set
  /// payloads, with the 4-byte NAL length prefix the stream's samples use.
  private static func makeFormatDescription(parameterSets: [Data]) -> CMFormatDescription? {
    let flattened = [UInt8](parameterSets.joined())
    let sizes = parameterSets.map(\.count)
    var formatDescription: CMFormatDescription?
    let status = flattened.withUnsafeBufferPointer { buffer -> OSStatus in
      guard let base = buffer.baseAddress else { return -1 }
      var pointers: [UnsafePointer<UInt8>] = []
      var offset = 0
      for size in sizes {
        pointers.append(base + offset)
        offset += size
      }
      return CMVideoFormatDescriptionCreateFromHEVCParameterSets(
        allocator: kCFAllocatorDefault,
        parameterSetCount: pointers.count,
        parameterSetPointers: pointers,
        parameterSetSizes: sizes,
        nalUnitHeaderLength: 4,
        extensions: nil,
        formatDescriptionOut: &formatDescription
      )
    }
    guard status == noErr, let formatDescription else {
      MWDATLog.log("Failed to build format description from in-band parameter sets: \(status)")
      return nil
    }
    return formatDescription
  }

  private static func nalTypes(of sampleBuffer: CMSampleBuffer) -> [UInt8] {
    guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else { return [] }
    var totalLength = 0
    var dataPointer: UnsafeMutablePointer<Int8>?
    let status = CMBlockBufferGetDataPointer(
      blockBuffer,
      atOffset: 0,
      lengthAtOffsetOut: nil,
      totalLengthOut: &totalLength,
      dataPointerOut: &dataPointer
    )
    guard status == kCMBlockBufferNoErr, let dataPointer else { return [] }
    let data = Data(bytes: dataPointer, count: totalLength)
    var types: [UInt8] = []
    var pos = data.startIndex
    while pos + 4 < data.endIndex {
      var length = 0
      for offset in 0 ..< 4 {
        length = (length << 8) | Int(data[pos + offset])
      }
      let payloadStart = pos + 4
      guard length > 0, payloadStart + length <= data.endIndex else { break }
      types.append((data[payloadStart] >> 1) & 0x3F)
      pos = payloadStart + length
    }
    return types
  }

  // MARK: - Stream Session

  /// True when starting a stream would immediately contradict the background
  /// contract. Checked at every commit point in `startStreamSession`, not just
  /// on entry, because a start can be in flight when the app backgrounds.
  @MainActor
  private var mustNotStreamNow: Bool {
    isInBackground && !backgroundController.isEnabled
  }

  func startStreamSession(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String : Any] else {
      result(FlutterError(code: "INVALID_ARGS", message: "arguments missing", details: nil))
      return
    }

    let fps = (args["fps"] as? Double) ?? 30.0
    let streamQuality = Self.parseStreamQuality(args["streamQuality"] as? String)
    let videoCodecStr = args["videoCodec"] as? String ?? "raw"
    let videoCodec: MWDATCamera.VideoCodec = (videoCodecStr == "hvc1") ? .hvc1 : .raw

    // `deviceId` (a `WearableDevice.id` from getDevices) pins streaming to a
    // specific pair; nil auto-selects. Applied below by rebuilding the shared
    // selector.
    let requestedDeviceId = args["deviceId"] as? String

    Task { @MainActor in
      // Reject a concurrent start: a second start that tears down the first's
      // in-flight session (on a pin change) would leave the first awaiting
      // `.started` forever.
      if isStartingSession {
        result(FlutterError(code: "STREAM_ACTIVE", message: "A stream start is already in progress.", details: nil))
        return
      }
      // Refuse outright while backgrounded. This is the belt to the contract's
      // braces: even a consumer whose retry logic ignores `stoppedForBackground`
      // physically cannot reactivate the glasses camera from the background.
      if mustNotStreamNow {
        result(FlutterError(
          code: "APP_BACKGROUNDED",
          message: "Cannot start a stream while the app is backgrounded. Call enableBackgroundStreaming() first if you need background capture.",
          details: nil))
        return
      }
      isStartingSession = true
      defer { isStartingSession = false }

      // A non-nil `streamSession` only counts as active if it's not terminal:
      // the SDK can stop a stream (hinges, thermal) without clearing our
      // reference, so check the actual state. Same selection → return the
      // existing texture; a *different* device → caller must stop first.
      if let existing = streamSession {
        // `.paused` counts as LIVE, deliberately. `Stream` exposes no
        // `resume()` — but that absence is not an invitation to recreate the
        // session, it is because the SDK drives the stream out of `.paused`
        // itself. Meta's guidance is explicit: "On PAUSED, keep the connection
        // and wait for STARTED or STOPPED", and "your app should not attempt to
        // restart a device session while it is paused". `thermalCritical` pauses
        // exactly this way and resumes once the glasses cool, so tearing down
        // here would destroy the SDK's own thermal recovery. An app that really
        // does want a fresh session calls `stopStreamSession()` first, which
        // never reaches this guard.
        if existing.state != .stopped && existing.state != .stopping {
          if requestedDeviceId == pinnedDeviceId {
            if let texId = textureId {
              result(texId)
            } else {
              result(FlutterError(code: "TEXTURE_ERROR", message: "Session exists but no texture registered", details: nil))
            }
          } else {
            result(FlutterError(code: "STREAM_ACTIVE", message: "A stream is already active on another device. Stop it before switching devices.", details: nil))
          }
          return
        }
        // Stale (stopped/stopping) stream — drop the reference and recreate.
        await teardownStreamOnly()
      }

      // Apply a pin change (or clear) before creating the session: rebuild the
      // shared selector and rebind every observer (internal watchdog + the two
      // event-channel handlers) so none keep watching the old selector.
      let pinChanged = requestedDeviceId != pinnedDeviceId
      if pinChanged {
        pinnedDeviceId = requestedDeviceId
        await teardownDeviceSession()
        deviceSelector = makeDeviceSelector()
        lastSelectorRebuild = Date()
        startDeviceAvailabilityMonitoring()
        activeDeviceHandler?.restartMonitoring(force: true)
        deviceStateHandler?.restartMonitoring(force: true)
      }

      // The just-rebuilt selector resolves its active device asynchronously;
      // creating the session before it resolves returns `noEligibleDevice`.
      // When a specific device is pinned, wait briefly for it to resolve.
      if pinChanged, requestedDeviceId != nil {
        let deadline = Date().addingTimeInterval(selectorResolveTimeout)
        while deviceSelector.activeDevice == nil, Date() < deadline {
          try? await Task.sleep(for: .milliseconds(150))
        }
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
      MWDATLog.log("Registered texture \(texId)")

      // 3. Add a Camera capability. DAT 0.9.0 replaced `addStream` with
      // `addCamera`; the returned `Camera` owns the stream.
      let fpsValue = UInt(max(1, Int(fps.rounded())))
      let streamConfig = StreamConfiguration(
        videoCodec: videoCodec,
        resolution: Self.resolution(for: streamQuality),
        frameRate: fpsValue
      )

      let newCamera: MWDATCamera.Camera?
      do {
        newCamera = try deviceSession.addCamera(config: streamConfig)
      } catch let e as DeviceSessionError {
        streamErrorHandler.send(deviceSessionError: e)
        await teardownStreamOnly()
        result(FlutterError(code: "ADD_CAMERA_ERROR", message: "Could not add camera capability: \(e)", details: nil))
        return
      } catch {
        await teardownStreamOnly()
        result(FlutterError(code: "ADD_CAMERA_ERROR", message: error.localizedDescription, details: nil))
        return
      }

      guard let addedCamera = newCamera else {
        await teardownStreamOnly()
        result(FlutterError(code: "ADD_CAMERA_ERROR", message: "addCamera returned nil — device session not in started state", details: nil))
        return
      }
      let session = addedCamera.stream

      // 4. Wire listeners. Stream errors are forwarded to Dart by
      // `streamErrorHandler` once its `session` is set below. The frame
      // handler outlives the session, so drop any parameter sets cached from
      // a previous stream before the first frame of this one arrives.
      videoFrameHandler.resetParameterSetCache()
      videoListenerToken = session.videoFramePublisher.listen { [weak self] videoFrame in
        guard let self else { return }
        self.frameQueue.async {
          self.processAndSendFrame(videoFrame)
        }
      }

      // Last commit point. A device session can take up to
      // `deviceSessionStartTimeout` to come up, which is ample time for the
      // user to background the app mid-start. Committing here anyway would
      // install a live stream in a backgrounded app that nothing is going to
      // stop — the one outcome worse than the freeze this all replaces.
      if mustNotStreamNow {
        MWDATLog.log("app backgrounded during start — abandoning")
        await teardownStreamOnly()
        result(FlutterError(
          code: "APP_BACKGROUNDED",
          message: "The app was backgrounded before the stream could start.",
          details: nil))
        return
      }

      camera = addedCamera
      streamSession = session
      streamStateHandler.session = session
      streamErrorHandler.session = session

      // 5. Start streaming. DAT 0.8.0: Stream.start() is synchronous.
      session.start()
      result(texId)
    }
  }

  func stopStreamSession(call: FlutterMethodCall, result: @escaping FlutterResult) {
    Task { @MainActor in
      guard streamSession != nil else {
        // No stream, but a failed start can leave a started DeviceSession
        // cached — end it anyway so the glasses aren't left mid-session
        // (which would also mute the next start's tone).
        if deviceSession != nil {
          await teardownDeviceSession()
        }
        result(FlutterError(code: "SESSION_NOT_FOUND", message: "No active stream session", details: nil))
        return
      }

      // End the DeviceSession too, not just the stream. The glasses'
      // stream-ended tone hangs off the session lifecycle — Meta's
      // CameraAccess sample ends its session as the user-visible stop and
      // chimes; keeping the session cached here (the old behaviour, for fast
      // restarts) meant the glasses only chimed when the app was backgrounded
      // or killed. Trade-off: the next startStreamSession is a full session
      // reconnect rather than a fast addCamera.
      await teardownDeviceSession()
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
      var photoToken: AnyListenerToken?
      var errorToken: AnyListenerToken?

      // Resolves the Dart call exactly once and releases *both* listeners.
      // Every terminal path below goes through here, so neither listener
      // outlives the capture it was created for.
      //
      // `@MainActor` is load-bearing, not decoration. There are now three
      // racing producers — the photo publisher, the error publisher, and the
      // timeout — and the first two are `@Sendable` callbacks that fire on
      // whatever thread the SDK chooses. An unsynchronised check-and-set on
      // `didRespond` would let two of them both pass the guard and reply twice
      // to the same Flutter call. Funnelling through the main actor serialises
      // the guard, and has the bonus of invoking `result` on the platform
      // thread, which is where Flutter requires it.
      @MainActor func respond(_ value: Any?) {
        guard !didRespond else { return }
        didRespond = true
        let (photo, error) = (photoToken, errorToken)
        photoToken = nil
        errorToken = nil
        Task {
          await photo?.cancel()
          await error?.cancel()
        }
        result(value)
      }

      photoToken = streamSession.photoDataPublisher.listen { photoData in
        let formatString: String = (photoData.format == .heic) ? "heic" : "jpeg"
        let payload: [String: Any] = [
          "bytes": FlutterStandardTypedData(bytes: photoData.data),
          "format": formatString,
        ]
        Task { @MainActor in respond(payload) }
      }

      // DAT 0.9.0 removed the never-delivered `CaptureError` and routes capture
      // failure through `StreamError.photoCaptureFailed` instead, so an accepted
      // capture that fails now resolves in milliseconds rather than waiting out
      // the timeout below. `Announcer.listen` hands out a fresh token per call,
      // so this listener coexists with `streamErrorHandler`'s own subscription
      // on the same publisher (which deliberately drops this case — capture
      // failure is request-scoped and belongs here, not on the error channel).
      errorToken = streamSession.errorPublisher.listen { error in
        guard error == .photoCaptureFailed else { return }
        Task { @MainActor in
          respond(FlutterError(
            code: "CAPTURE_PHOTO_FAILED",
            message: "Photo capture did not complete — check device storage.",
            details: "photoCaptureFailed"))
        }
      }

      let accepted = streamSession.capturePhoto(format: captureFormat)
      if !accepted {
        // Request rejected synchronously: no session, no high-bandwidth
        // (BTC/WiFi) lease, or a capture already in progress.
        respond(FlutterError(
          code: "CAPTURE_NOT_READY",
          message: "Capture request was not accepted.",
          details: "captureNotReady"))
        return
      }

      // Backstop for the case the SDK reports neither a photo nor an error: an
      // accepted capture that goes silent would otherwise leave the Dart Future
      // unresolved forever.
      let timeoutSeconds = 15.0
      Task { @MainActor in
        try? await Task.sleep(for: .milliseconds(timeoutSeconds * 1000))
        respond(FlutterError(
          code: "CAPTURE_PHOTO_FAILED",
          message: "Photo capture timed out.",
          details: "photoCaptureTimeout"))
      }
    }
  }

  func getRegistrationState(result: @escaping FlutterResult) {
    Task { @MainActor in
      let state = Wearables.shared.registrationState
      result(state.rawValue)
    }
  }

  /// Returns a snapshot of all paired devices as an array of maps, decoded by
  /// `WearableDevice.fromMap` on the Dart side. `isActive` reflects the shared
  /// auto-selector's current pick (what a new stream would bind to);
  /// `isStreamingDevice` reflects what the *live* stream is using, gated on the
  /// stream's actual `.streaming` state (not just a non-nil reference, which
  /// can be stale after an SDK-driven stop).
  func getDevices(result: @escaping FlutterResult) {
    Task { @MainActor in
      let active = deviceSelector.activeDevice
      let sessionId = deviceSession?.deviceId
      let streaming = streamSession?.state == .streaming
      var devices: [[String: Any]] = []
      // Prefer the warm cache fed by `startDeviceListMonitoring()`: the raw
      // `Wearables.shared.devices` snapshot can read empty when nothing is
      // actively observing the device stream (the original bug), whereas the
      // cache reflects the most recent `devicesStream()` emission. Fall back to
      // the snapshot only before the stream has emitted its first value.
      let ids = didReceiveDeviceListEmission ? knownDeviceIds : Wearables.shared.devices
      for id in ids {
        guard !id.isEmpty else { continue }
        let isActive = (id == active)
        let isStreamingDevice = streaming && (id == sessionId)
        if let device = Wearables.shared.deviceForIdentifier(id) {
          devices.append([
            "id": id,
            "name": device.name,
            "deviceType": Self.deviceTypeCode(device.deviceType()),
            "linkState": Self.linkStateCode(device.linkState),
            "compatibility": Self.compatibilityCode(device.compatibility()),
            "supportsDisplay": device.supportsDisplay(),
            "isActive": isActive,
            "isStreamingDevice": isStreamingDevice,
            "firmwareInfo": NSNull(),
          ])
        } else {
          // Metadata unavailable — emit a complete fallback so the device
          // count still matches `Wearables.shared.devices`.
          devices.append([
            "id": id,
            "name": id,
            "deviceType": "unknown",
            "linkState": "unknown",
            "compatibility": "undefined",
            "supportsDisplay": false,
            "isActive": isActive,
            "isStreamingDevice": isStreamingDevice,
            "firmwareInfo": NSNull(),
          ])
        }
      }
      result(devices)
    }
  }

  /// Canonical device-type code, kept identical to the Android side.
  private static func deviceTypeCode(_ type: MWDATCore.DeviceType) -> String {
    switch type {
      case .rayBanMeta:         return "rayBanMeta"
      case .oakleyMetaHSTN:     return "oakleyMetaHSTN"
      case .oakleyMetaVanguard: return "oakleyMetaVanguard"
      case .metaRayBanDisplay:  return "metaRayBanDisplay"
      case .rayBanMetaOptics:   return "rayBanMetaOptics"
      case .metaGlasses:        return "metaGlasses"
      case .unknown:            return "unknown"
      @unknown default:         return "unknown"
    }
  }

  /// Canonical link-state code, kept identical to the Android side.
  private static func linkStateCode(_ state: MWDATCore.LinkState) -> String {
    switch state {
      case .disconnected: return "disconnected"
      case .connecting:   return "connecting"
      case .connected:    return "connected"
    }
  }

  /// Canonical compatibility code, kept identical to the Android side.
  private static func compatibilityCode(
    _ compatibility: MWDATCore.Compatibility
  ) -> String {
    switch compatibility {
      case .undefined:            return "undefined"
      case .compatible:           return "compatible"
      case .deviceUpdateRequired: return "deviceUpdateRequired"
      case .sdkUpdateRequired:    return "sdkUpdateRequired"
      @unknown default:           return "undefined"
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

/// Result of racing a device session's state stream against the start timeout
/// in `awaitSessionStarted`. Plain (no associated values) so it crosses the
/// task-group boundary as a `Sendable` value without capturing the plugin.
private enum SessionWaitOutcome: Sendable {
  case started
  case stopped
  case timedOut
  case streamEnded
}
