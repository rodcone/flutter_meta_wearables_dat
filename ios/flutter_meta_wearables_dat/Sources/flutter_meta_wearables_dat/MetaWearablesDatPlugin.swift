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
  // Watches for the stream terminating on its own so the Camera can be detached
  // even when the app never calls `stopStreamSession`. See `teardownStreamOnly`.
  private var streamStateListenerToken: (any MWDATCore.AnyListenerToken)?
  // Guards `teardownStreamOnly` against re-entry: stopping the camera drives the
  // stream to `.stopped`, which calls straight back in through that listener.
  private var isTearingDownStream = false
  // Whether the current stream has been observed in a non-`.stopped` state. The
  // state publisher replays `.stopped` on subscribe (a new stream hasn't started
  // yet), so without this the watcher would tear down the stream at creation.
  private var streamHasRun = false
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
    deviceAvailabilityTask = Task { [weak self] in
      guard let self else { return }
      for await deviceId in self.deviceSelector.activeDeviceStream() {
        if deviceId == nil {
          await self.teardownDeviceSession()
        }
      }
    }
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
      try? await Task.sleep(nanoseconds: 200_000_000)
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
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
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
  @MainActor
  private func teardownStreamOnly() async {
    if isTearingDownStream { return }
    isTearingDownStream = true
    defer { isTearingDownStream = false }

    // Cancel the self-termination watcher first: `camera.stop()` below drives the
    // stream to `.stopped`, which would otherwise re-enter here.
    if let token = streamStateListenerToken {
      await token.cancel()
      streamStateListenerToken = nil
    }
    streamHasRun = false
    if let token = videoListenerToken {
      await token.cancel()
      videoListenerToken = nil
    }
    streamStateHandler.session = nil
    streamErrorHandler.session = nil
    // DAT 0.9.0: stop the *Camera*, not the Stream. The camera is what holds
    // the capability slot on the DeviceSession — stopping only the stream would
    // leave the camera attached and make the next `addCamera` fail with
    // `capabilityAlreadyActive`, since we deliberately keep the session alive
    // across `stopStreamSession`. `Camera.stop()` releases resources, detaches
    // from the parent session, and cascades to its children (the stream).
    if let camera {
      camera.stop()
    }
    camera = nil
    streamSession = nil
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
      isStartingSession = true
      defer { isStartingSession = false }

      // A non-nil `streamSession` only counts as active if it's not terminal:
      // the SDK can stop a stream (hinges, thermal) without clearing our
      // reference, so check the actual state. Same selection → return the
      // existing texture; a *different* device → caller must stop first.
      if let existing = streamSession {
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
          try? await Task.sleep(nanoseconds: 150_000_000)
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
      NSLog("[MWDAT] Registered texture \(texId)")

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
      // `streamErrorHandler` once its `session` is set below.
      videoListenerToken = session.videoFramePublisher.listen { [weak self] videoFrame in
        guard let self else { return }
        self.processAndSendFrame(videoFrame)
      }

      // Teardown cascades parent -> child but NOT child -> parent, so a stream
      // that stops on its own — a stream-level error such as `hingesClosed`
      // while the DeviceSession stays connected — leaves the Camera attached and
      // holding the hardware. Detach it here instead of waiting for the app to
      // call `stopStreamSession`: an app that merely surfaces the error would
      // otherwise hold the camera until its next start attempt.
      //
      // `statePublisher` replays the stream's *current* state on subscribe, and a
      // freshly added camera's stream is `.stopped` until `start()` below takes
      // effect — so a naive `state == .stopped` check tears down the stream we
      // are in the middle of creating. Only act once the stream has actually
      // been observed running.
      streamHasRun = false
      streamStateListenerToken = session.statePublisher.listen { [weak self] state in
        Task { @MainActor in
          guard let self else { return }
          guard state == .stopped else {
            self.streamHasRun = true
            return
          }
          guard self.streamHasRun else { return }
          await self.teardownStreamOnly()
        }
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
        result(FlutterError(code: "SESSION_NOT_FOUND", message: "No active stream session", details: nil))
        return
      }

      // Tear down the stream only — keep the DeviceSession alive so the next
      // startStreamSession is a fast `addCamera` rather than a full reconnect.
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
        try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
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
