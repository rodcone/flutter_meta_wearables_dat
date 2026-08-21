package io.rodcone.flutter_meta_wearables_dat

import android.app.Activity
import android.app.Application
import android.content.Intent
import android.content.pm.PackageManager
import android.util.Log
import android.view.Surface
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.meta.wearable.dat.camera.Camera
import com.meta.wearable.dat.camera.Stream
import com.meta.wearable.dat.camera.addCamera
import com.meta.wearable.dat.camera.types.CaptureError
import com.meta.wearable.dat.camera.types.PhotoData
import com.meta.wearable.dat.camera.types.StreamConfiguration
import com.meta.wearable.dat.camera.types.VideoQuality
import com.meta.wearable.dat.core.Wearables
import com.meta.wearable.dat.core.selectors.AutoDeviceSelector
import com.meta.wearable.dat.core.selectors.DeviceSelector
import com.meta.wearable.dat.core.session.DeviceSessionState
import com.meta.wearable.dat.core.session.DeviceSession
import com.meta.wearable.dat.core.types.DatResult
import com.meta.wearable.dat.core.types.Permission
import com.meta.wearable.dat.core.types.PermissionError
import com.meta.wearable.dat.core.types.PermissionStatus
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import io.flutter.view.TextureRegistry
import java.io.ByteArrayOutputStream
import kotlin.coroutines.resume
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** MetaWearablesDatPlugin */
class MetaWearablesDatPlugin :
        FlutterPlugin,
        MethodCallHandler,
        ActivityAware,
        PluginRegistry.ActivityResultListener,
        PluginRegistry.RequestPermissionsResultListener {

    companion object {
        private const val TAG = "MetaWearablesDat"
        private const val PERMISSION_REQUEST_CODE = 48291
        private const val BT_PERMISSION_REQUEST_CODE = 48292
        private const val NOTIFICATION_PERMISSION_REQUEST_CODE = 48294
        // Upper bound on how long we wait, after a camera-permission grant, for
        // the shared selector to resolve a device before returning to Dart.
        // Granting permission implies the glasses are connected, so a device
        // should appear well inside this bound.
        private const val PERMISSION_DEVICE_RESOLVE_TIMEOUT_MS = 8_000L
        private val REQUIRED_PERMISSIONS: Array<String> =
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.S) {
                    arrayOf(
                            android.Manifest.permission.BLUETOOTH_CONNECT,
                            android.Manifest.permission.INTERNET,
                    )
                } else {
                    arrayOf(
                            android.Manifest.permission.BLUETOOTH,
                            android.Manifest.permission.INTERNET,
                    )
                }
    }

    private lateinit var channel: MethodChannel
    private lateinit var activeDeviceChannel: EventChannel
    private lateinit var registrationStateChannel: EventChannel
    private lateinit var streamSessionStateChannel: EventChannel
    private lateinit var streamSessionErrorChannel: EventChannel
    private lateinit var videoStreamSizeChannel: EventChannel
    private lateinit var videoFramesChannel: EventChannel
    private lateinit var deviceStateChannel: EventChannel
    private var application: Application? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var activeDeviceStreamHandler: ActiveDeviceStreamHandler? = null
    private var registrationStateStreamHandler: RegistrationStateStreamHandler? = null
    private var streamStateStreamHandler: StreamStateStreamHandler? = null
    private var streamSessionErrorStreamHandler: StreamSessionErrorStreamHandler? = null
    private var videoStreamSizeStreamHandler: VideoStreamSizeStreamHandler? = null
    private val videoFrameStreamHandler = VideoFrameStreamHandler()
    private var deviceStateStreamHandler: DeviceStateStreamHandler? = null
    // Forward DeviceSession.errors (0.7.0 SharedFlow<DeviceSessionError>) onto
    // the same Flutter event channel that Stream.errorStream uses. Cancelled
    // and recreated alongside the session lifecycle.
    private var sessionErrorsJob: Job? = null

    // Background streaming — tracks whether the foreground service has been
    // started so we can idempotently re-start / stop it, and so we can tear
    // it down on plugin detach.
    @Volatile private var backgroundStreamingStarted: Boolean = false

    /**
     * Process-wide foreground tracking. `isAppInBackground` is the single
     * source of truth for "the app is not visible"; Android had no notion of
     * this at all before 0.9.0.
     */
    private var foregroundTracker: AppForegroundTracker? = null
    @Volatile private var isAppInBackground: Boolean = false
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    // Gate SDK initialization until BT permissions are granted (mirrors reference app).
    private var btPermissionsGranted = false

    // Permission request handling
    private var permissionContinuation:
        CancellableContinuation<DatResult<PermissionStatus, PermissionError>>? = null
    private val permissionMutex = Mutex()
    // Lazy so it isn't constructed at plugin load — the 0.6.0 SDK types
    // may touch `Wearables` internals and throw before `Wearables.initialize()`.
    private val permissionContract by lazy { Wearables.RequestPermissionContract() }
    private var btPermissionResult: Result? = null

    // Pending state for the Android 13+ POST_NOTIFICATIONS permission, requested
    // lazily when the host app calls `enableBackgroundStreaming`.
    private var pendingBackgroundCall: MethodCall? = null
    private var pendingBackgroundResult: Result? = null

    // Single shared device selector — mirrors reference app's WearablesViewModel pattern.
    // One instance is shared across device monitoring and stream session creation.
    //
    // Built lazily via [deviceSelector] only AFTER `Wearables.initialize()`:
    // constructing an `AutoDeviceSelector`/`SpecificDeviceSelector` before init
    // crashes the plugin class load, which silently drops method-channel
    // registration. Hence a nullable holder + accessor, not `by lazy` (whose
    // initializer could still run pre-init from a handler provider) or an eager
    // field.
    private var deviceSelectorRef: DeviceSelector? = null

    // Identifier of the pinned device, or null for auto-select. Honored by
    // [makeDeviceSelector] at every construction site so a rebuild can't
    // silently drop the pin.
    private var pinnedDeviceId: String? = null

    /** Shared selector, built on first use (post-init) and cached. */
    private fun deviceSelector(): DeviceSelector =
            deviceSelectorRef ?: makeDeviceSelector().also { deviceSelectorRef = it }

    /** Builds the shared selector honoring [pinnedDeviceId]. Call only post-init. */
    private fun makeDeviceSelector(): DeviceSelector =
            pinnedDeviceId?.let {
                com.meta.wearable.dat.core.selectors.SpecificDeviceSelector(
                        com.meta.wearable.dat.core.types.DeviceIdentifier(it)
                )
            } ?: AutoDeviceSelector()

    // Streaming state — the DAT SDK splits what was historically one
    // `StreamSession` into a `DeviceSession` (device lifecycle) and a `Stream`
    // (a capability added to a started session). The `DeviceSession` is
    // reused across stream start/stop toggles; it's only torn down when the
    // device disappears or the plugin is disposed.
    private var session: DeviceSession? = null
    // DAT 0.9.0 consolidated stream capability ownership into `Camera`: the
    // session hands out a `Camera`, which owns the `Stream`. Both are kept —
    // the `Camera` because it's the handle that detaches the capability, the
    // `Stream` because that's what the jobs and handlers bind to. They are set
    // and cleared together (see `teardownStreamOnly`).
    private var camera: Camera? = null
    private var stream: Stream? = null
    private var sessionKey: String? = null

    // Device the current (reusable) DeviceSession is bound to. Captured at
    // session creation — from the auto-selector's pick *before* createSession,
    // so a later A→B switch can't misattribute it — and cleared on session
    // teardown. Combined with a live STREAMING check in `getDevices`, it tells
    // which device is actually streaming.
    @Volatile private var sessionDeviceId: String? = null

    // Guards concurrent startStreamSession calls: a second start that tore down
    // the first's in-flight session would leave the first awaiting STARTED.
    @Volatile private var startInProgress = false
    private var videoJob: Job? = null
    private var streamErrorJob: Job? = null
    // Guards teardownStreamOnly against re-entry — it is reachable from the
    // method channel, device-loss monitoring and the start-failure paths.
    private var isTearingDownStream = false
    private var deviceAvailabilityJob: Job? = null
    // Texture API — renders I420 frames to a SurfaceTexture
    // instead of encoding to JPEG and copying bytes across the platform channel.
    private var textureRegistry: TextureRegistry? = null
    private var textureEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var textureSurface: Surface? = null
    private val frameProcessor = FrameProcessor()

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, "flutter_meta_wearables_dat")
        channel.setMethodCallHandler(this)

        activeDeviceChannel =
                EventChannel(
                        flutterPluginBinding.binaryMessenger,
                        "flutter_meta_wearables_dat/active_device"
                )
        activeDeviceStreamHandler =
                ActiveDeviceStreamHandler(
                        { deviceSelector() },
                        { btPermissionsGranted },
                        { ensureWearablesInitialized() },
                )
        activeDeviceChannel.setStreamHandler(activeDeviceStreamHandler)

        registrationStateChannel =
                EventChannel(
                        flutterPluginBinding.binaryMessenger,
                        "flutter_meta_wearables_dat/registration_state"
                )
        registrationStateStreamHandler =
                RegistrationStateStreamHandler(
                        { btPermissionsGranted },
                        { ensureWearablesInitialized() },
                        ::mapRegistrationState,
                )
        registrationStateChannel.setStreamHandler(registrationStateStreamHandler)

        streamSessionStateChannel =
                EventChannel(
                        flutterPluginBinding.binaryMessenger,
                        "flutter_meta_wearables_dat/stream_session_state"
                )
        streamStateStreamHandler = StreamStateStreamHandler()
        streamSessionStateChannel.setStreamHandler(streamStateStreamHandler)

        streamSessionErrorChannel =
                EventChannel(
                        flutterPluginBinding.binaryMessenger,
                        "flutter_meta_wearables_dat/stream_session_errors"
                )
        streamSessionErrorStreamHandler = StreamSessionErrorStreamHandler()
        streamSessionErrorChannel.setStreamHandler(streamSessionErrorStreamHandler)

        videoStreamSizeChannel =
                EventChannel(
                        flutterPluginBinding.binaryMessenger,
                        "flutter_meta_wearables_dat/video_stream_size",
                )
        videoStreamSizeStreamHandler = VideoStreamSizeStreamHandler()
        videoStreamSizeChannel.setStreamHandler(videoStreamSizeStreamHandler)

        videoFramesChannel =
                EventChannel(
                        flutterPluginBinding.binaryMessenger,
                        "flutter_meta_wearables_dat/video_frames",
                )
        videoFramesChannel.setStreamHandler(videoFrameStreamHandler)

        deviceStateChannel =
                EventChannel(
                        flutterPluginBinding.binaryMessenger,
                        "flutter_meta_wearables_dat/device_state",
                )
        deviceStateStreamHandler =
                DeviceStateStreamHandler(
                        deviceSelectorProvider = { deviceSelector() },
                        isInitialized = { btPermissionsGranted },
                )
        deviceStateChannel.setStreamHandler(deviceStateStreamHandler)

        textureRegistry = flutterPluginBinding.textureRegistry

        val context = flutterPluginBinding.applicationContext
        application = context as? Application
        registerForegroundTracker()
        // NOTE: Do NOT call ensureWearablesInitialized() here.
        // The reference app initializes the SDK only AFTER Bluetooth permissions
        // are granted. Calling it before permissions breaks device discovery.
        // The SDK will be initialized lazily when first needed (e.g. after
        // requestAndroidPermissions grants BT permissions).
    }

    // region App lifecycle

    /**
     * Registers the process-wide foreground tracker. Idempotent: re-registering
     * after a hot restart (where `onDetachedFromEngine` is NOT called, despite
     * what the comment there used to imply) would otherwise leave one live
     * tracker per restart, each firing against stale plugin state.
     */
    private fun registerForegroundTracker() {
        val app = application ?: return
        unregisterForegroundTracker()
        val tracker =
                AppForegroundTracker(
                        schedule = { delayMs, action ->
                            val job =
                                    scope.launch {
                                        delay(delayMs)
                                        action()
                                    }
                            AppForegroundTracker.Cancellable { job.cancel() }
                        },
                )
        tracker.onEnteredBackground = { handleEnteredBackground() }
        tracker.onEnteredForeground = { handleEnteredForeground() }
        app.registerActivityLifecycleCallbacks(tracker)
        foregroundTracker = tracker
    }

    private fun unregisterForegroundTracker() {
        val tracker = foregroundTracker ?: return
        application?.unregisterActivityLifecycleCallbacks(tracker)
        tracker.dispose()
        foregroundTracker = null
    }

    private fun handleEnteredBackground() {
        isAppInBackground = true
        // Background streaming ON is the opt-in: keep everything alive.
        if (backgroundStreamingStarted) return
        // Nothing live means nothing to stop. Without this, every backgrounding
        // would emit a terminal `stopped` at idle apps that merely subscribed
        // to the state channel.
        if (stream == null && session == null) return

        Log.d(TAG, "lifecycle: stopping session (background streaming off)")
        // Tell Dart why, before the terminal `stopped`, so consumers can tell a
        // deliberate stop from a fault and skip their retry logic.
        streamSessionErrorStreamHandler?.sendError(
                "stoppedForBackground",
                "The app was backgrounded and background streaming is not enabled.",
        )
        // The whole session, matching iOS and Meta's CameraAccess sample.
        //
        // Note there is no equivalent of iOS's beginBackgroundTask assertion
        // here, deliberately: Android does not freeze the process on
        // backgrounding, so the stop cascade completes normally. Do not port
        // that machinery over.
        teardownSession()
    }

    private fun handleEnteredForeground() {
        isAppInBackground = false
        // Deliberately nothing else. With background streaming off the session
        // is stopped and stays stopped; the plugin never restarts the glasses
        // camera on its own. Do not add a resume here.
    }

    // endregion

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "requestAndroidPermissions" -> requestAndroidPermissions(result)
            "startRegistration" -> startRegistration(result)
            "disconnect" -> disconnect(result)
            "getRegistrationState" -> getRegistrationState(result)
            "getDevices" -> getDevices(result)
            "getCameraPermissionStatus" -> getCameraPermissionStatus(result)
            "requestCameraPermission" -> requestCameraPermission(result)
            "handleUrl" -> handleUrl(call, result)
            // Internal cross-plugin bridge — invoked by
            // `flutter_meta_wearables_dat_mock_device` over the shared
            // binaryMessenger when a file-fed mock video carries rotation
            // metadata that the mock SDK strips out. Underscore-prefixed to
            // signal it's not part of the public Dart API.
            "_setVideoFeedRotation" -> {
                val degrees = call.argument<Int>("degrees") ?: 0
                frameProcessor.setRotation(degrees)
                result.success(true)
            }
            "restartActiveDeviceMonitoring" -> {
                Log.d(TAG, "restartActiveDeviceMonitoring invoked from Dart")
                activeDeviceStreamHandler?.restartMonitoring()
                result.success(true)
            }
            "startStreamSession" -> startStreamSession(call, result)
            "stopStreamSession" -> stopStreamSession(call, result)
            "capturePhoto" -> capturePhoto(call, result)
            "enableBackgroundStreaming" -> enableBackgroundStreaming(call, result)
            "disableBackgroundStreaming" -> disableBackgroundStreaming(result)
            "openDATGlassesAppUpdate" -> openDATGlassesAppUpdate(result)
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        activeDeviceChannel.setStreamHandler(null)
        activeDeviceStreamHandler?.dispose()
        activeDeviceStreamHandler = null
        registrationStateChannel.setStreamHandler(null)
        registrationStateStreamHandler?.dispose()
        registrationStateStreamHandler = null
        streamSessionStateChannel.setStreamHandler(null)
        streamStateStreamHandler?.dispose()
        streamStateStreamHandler = null
        streamSessionErrorChannel.setStreamHandler(null)
        streamSessionErrorStreamHandler?.dispose()
        streamSessionErrorStreamHandler = null
        videoStreamSizeChannel.setStreamHandler(null)
        videoStreamSizeStreamHandler?.dispose()
        videoStreamSizeStreamHandler = null
        videoFramesChannel.setStreamHandler(null)
        videoFrameStreamHandler.dispose()
        deviceStateChannel.setStreamHandler(null)
        deviceStateStreamHandler?.dispose()
        deviceStateStreamHandler = null

        unregisterForegroundTracker()

        // Tear down any active session and stream
        teardownSession()

        // Stop the background service if it's running — otherwise the
        // notification would hang around after a hot restart.
        stopBackgroundServiceIfRunning()

        textureRegistry = null
        scope.cancel()
    }

    // region ActivityAware

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addActivityResultListener(this)
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeActivityResultListener(this)
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    // endregion

    // region ActivityResultListener

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        // Carry the full DatResult through so the caller can distinguish a
        // user-initiated denial (PermissionStatus.Denied) from a contract
        // failure (NO_DEVICE, REQUEST_TIMEOUT, …). Collapsing both to
        // PermissionStatus.Denied here would silently lie to the Dart layer,
        // which now treats `false` as "user denied" exclusively.
        val parseResult = permissionContract.parseResult(resultCode, data)
        permissionContinuation?.resume(parseResult)
        permissionContinuation = null
        return true
    }

    // endregion

    // region RequestPermissionsResultListener

    override fun onRequestPermissionsResult(
            requestCode: Int,
            permissions: Array<out String>,
            grantResults: IntArray
    ): Boolean {
        when (requestCode) {
            BT_PERMISSION_REQUEST_CODE -> {
                val pendingResult = btPermissionResult ?: return false
                btPermissionResult = null
                val allGranted =
                        grantResults.isNotEmpty() &&
                                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
                if (allGranted) {
                    // Initialize SDK now that BT permissions are granted (mirrors reference app pattern)
                    Log.d(TAG, "BT permissions just granted by user")
                    btPermissionsGranted = true
                    ensureWearablesInitialized()
                    // Start monitoring now that SDK is properly initialized with permissions
                    registrationStateStreamHandler?.restartMonitoring()
                    activeDeviceStreamHandler?.restartMonitoring()
                    deviceStateStreamHandler?.restartMonitoring()
                } else {
                    Log.d(TAG, "BT permissions denied by user")
                }
                pendingResult.success(allGranted)
                return true
            }
            NOTIFICATION_PERMISSION_REQUEST_CODE -> {
                val pendingCall = pendingBackgroundCall
                val pendingResult = pendingBackgroundResult
                pendingBackgroundCall = null
                pendingBackgroundResult = null
                if (pendingCall == null || pendingResult == null) return false
                val granted =
                        grantResults.isNotEmpty() &&
                                grantResults.all { it == PackageManager.PERMISSION_GRANTED }
                if (!granted) {
                    Log.w(
                            TAG,
                            "POST_NOTIFICATIONS denied — the foreground service will still run, " +
                                    "but its notification will not appear until the user enables it in system settings.",
                    )
                }
                // Start the service regardless: the keep-alive foreground service
                // is the load-bearing part. A missing notification is a UX issue,
                // not a correctness issue.
                startBackgroundStreamingService(pendingCall, pendingResult)
                return true
            }
            else -> return false
        }
    }

    // endregion

    // region Permission Handling

    /**
     * Request the Android runtime permissions required by the DAT SDK (Bluetooth, Internet).
     * Returns true if all permissions are already granted or become granted after the request.
     */
    private fun requestAndroidPermissions(result: Result) {
        val act = activity
        if (act == null) {
            result.error(
                    "PERMISSION_ERROR",
                    "Activity is not available. Ensure the app is in the foreground.",
                    null
            )
            return
        }

        val missingPermissions =
                REQUIRED_PERMISSIONS.filter {
                    ContextCompat.checkSelfPermission(act, it) != PackageManager.PERMISSION_GRANTED
                }

        if (missingPermissions.isEmpty()) {
            // Permissions already granted — initialize SDK and start monitoring
            Log.d(TAG, "requestAndroidPermissions — all permissions already granted")
            btPermissionsGranted = true
            ensureWearablesInitialized()
            registrationStateStreamHandler?.restartMonitoring()
            activeDeviceStreamHandler?.restartMonitoring()
            deviceStateStreamHandler?.restartMonitoring()
            result.success(true)
            return
        }

        btPermissionResult = result
        ActivityCompat.requestPermissions(
                act,
                missingPermissions.toTypedArray(),
                BT_PERMISSION_REQUEST_CODE,
        )
    }

    private fun getCameraPermissionStatus(result: Result) {
        scope.launch {
            try {
                ensureWearablesInitialized()
                val status = checkCameraPermissionStatus(result) ?: return@launch
                result.success(status == PermissionStatus.Granted)
            } catch (e: Exception) {
                result.error(
                        "INTERNAL_ERROR",
                        e.message ?: "Failed to check camera permission status.",
                        null
                )
            }
        }
    }

    private suspend fun checkCameraPermissionStatus(result: Result): PermissionStatus? {
        val checkResult = Wearables.checkPermissionStatus(Permission.CAMERA)
        var failure: PermissionError? = null
        checkResult.onFailure { error, _ -> failure = error }
        val err = failure
        if (err != null) {
            result.error(
                    mapPermissionError(err),
                    err.description,
                    mapOf("errorType" to err.name),
            )
            return null
        }
        return checkResult.getOrNull() ?: PermissionStatus.Denied
    }

    /**
     * Map an SDK [PermissionError] to one of the typed codes that
     * `CameraPermissionException` predicates on the Dart side. `PERMISSION_DENIED`
     * is reserved for the case where a user explicitly declines the request — the
     * SDK doesn't surface that as an error (it returns `PermissionStatus.Denied`),
     * so it's never emitted here.
     */
    private fun mapPermissionError(error: PermissionError): String = when (error) {
        PermissionError.NO_DEVICE,
        PermissionError.NO_DEVICE_WITH_CONNECTION,
        PermissionError.CONNECTION_ERROR -> "DEVICE_DISCONNECTED"
        PermissionError.META_AI_NOT_INSTALLED,
        PermissionError.REQUEST_IN_PROGRESS,
        PermissionError.REQUEST_TIMEOUT,
        PermissionError.INTERNAL_ERROR -> "INTERNAL_ERROR"
    }

    /**
     * Request camera permission from the wearable device. Uses startActivityForResult with the DAT
     * SDK's RequestPermissionContract to show the Meta AI permission bottom sheet.
     */
    private fun requestCameraPermission(result: Result) {
        scope.launch {
            permissionMutex.withLock {
                try {
                    ensureWearablesInitialized()

                    val currentStatus = checkCameraPermissionStatus(result) ?: return@withLock
                    if (currentStatus == PermissionStatus.Granted) {
                        awaitDeviceAfterPermissionGrant(returnEarlyIfNoDevices = true)
                        result.success(true)
                        return@withLock
                    }

                    val act = activity
                    if (act == null) {
                        result.error(
                                "INTERNAL_ERROR",
                                "Activity is not available. Ensure the app is in the foreground.",
                                null
                        )
                        return@withLock
                    }

                    val parseResult =
                            suspendCancellableCoroutine<
                                DatResult<PermissionStatus, PermissionError>
                            > { continuation ->
                                permissionContinuation = continuation
                                continuation.invokeOnCancellation { permissionContinuation = null }
                                val intent = permissionContract.createIntent(act, Permission.CAMERA)
                                act.startActivityForResult(intent, PERMISSION_REQUEST_CODE)
                            }

                    // Mirror checkCameraPermissionStatus: contract failures
                    // (NO_DEVICE, REQUEST_TIMEOUT, …) become typed errors via
                    // mapPermissionError; only an explicit PermissionStatus.Denied
                    // result returns `false` to the Dart layer.
                    var failure: PermissionError? = null
                    parseResult.onFailure { error, _ -> failure = error }
                    val err = failure
                    if (err != null) {
                        result.error(
                                mapPermissionError(err),
                                err.description,
                                mapOf("errorType" to err.name),
                        )
                        return@withLock
                    }
                    val permissionStatus =
                            parseResult.getOrNull() ?: PermissionStatus.Denied
                    if (permissionStatus == PermissionStatus.Granted) {
                        // The grant brings the glasses (back) into the SDK device
                        // flow. Re-kick monitoring and wait (bounded) for the
                        // selector to resolve a device so the app's next
                        // startStreamSession / getDevices doesn't race the SDK.
                        awaitDeviceAfterPermissionGrant()
                    }
                    result.success(permissionStatus == PermissionStatus.Granted)
                } catch (e: Exception) {
                    result.error(
                            "INTERNAL_ERROR",
                            e.message ?: "Failed to request permission.",
                            null
                    )
                }
            }
        }
    }

    /**
     * After a camera-permission grant the glasses (re)surface in the SDK device
     * flow. Re-kick active-device / device-state monitoring and give the shared
     * selector a bounded window to resolve a device, so the app's next
     * startStreamSession / getDevices doesn't race the SDK and hit
     * noEligibleDevice / an empty list.
     *
     * Unlike iOS, Android's `Wearables.devices` is a hot `StateFlow` that stays
     * warm post-init and the `AutoDeviceSelector` tracks it, so there is no
     * cold-snapshot device list or permanently-blind selector to rebuild here —
     * the selector resolves on its own once a device is present. We only need to
     * (re)kick the observers and wait.
     */
    private suspend fun awaitDeviceAfterPermissionGrant(
            returnEarlyIfNoDevices: Boolean = false,
    ) {
        activeDeviceStreamHandler?.restartMonitoring()
        deviceStateStreamHandler?.restartMonitoring()
        // Already resolved — nothing to wait for.
        if (deviceSelector().activeDevice() != null) return
        // On the already-granted fast path, if the SDK currently lists no
        // devices there is nothing to resolve — return rather than holding the
        // permission mutex for the full timeout on a routine re-check.
        // `Wearables.devices` is a hot StateFlow, so its value reflects current
        // reality; on a *fresh* grant we instead keep waiting (default false),
        // since the just-granted device is expected to appear momentarily.
        if (returnEarlyIfNoDevices && Wearables.devices.value.isEmpty()) return
        withTimeoutOrNull(PERMISSION_DEVICE_RESOLVE_TIMEOUT_MS) {
            deviceSelector().activeDeviceFlow().first { it != null }
        }
    }

    // endregion

    // region Registration

    private fun startRegistration(result: Result) {
        val act = activity
        if (act == null) {
            result.error(
                    "REGISTRATION_ERROR",
                    "Activity is not available. Ensure the app is in the foreground.",
                    null
            )
            return
        }
        try {
            ensureWearablesInitialized()
            Wearables.startRegistration(act)
            result.success(true)
        } catch (e: Exception) {
            result.error("REGISTRATION_ERROR", e.message ?: "Failed to start registration.", null)
        }
    }

    private fun disconnect(result: Result) {
        val act = activity
        if (act == null) {
            result.error(
                    "UNREGISTRATION_ERROR",
                    "Activity is not available. Ensure the app is in the foreground.",
                    null
            )
            return
        }
        try {
            ensureWearablesInitialized()
            Wearables.startUnregistration(act)
            result.success(true)
        } catch (e: Exception) {
            result.error(
                    "UNREGISTRATION_ERROR",
                    e.message ?: "Failed to start unregistration.",
                    null
            )
        }
    }

    /**
     * Returns a snapshot of all paired devices as a list of maps, decoded by
     * `WearableDevice.fromMap` on the Dart side. Requires Bluetooth permissions
     * (the SDK can't enumerate devices until initialized) — returns a
     * `NOT_INITIALIZED` error otherwise rather than a misleading empty list.
     *
     * `isActive` = the shared auto-selector's current pick (what a new stream
     * would bind to). `isStreamingDevice` = the device the *live* stream uses,
     * gated on the stream's actual STREAMING state so a stale reference after
     * an SDK-driven stop doesn't report a false positive.
     */
    private fun getDevices(result: Result) {
        if (!btPermissionsGranted || application == null) {
            result.error(
                    "NOT_INITIALIZED",
                    "Bluetooth permissions not granted; call requestAndroidPermissions() first.",
                    null,
            )
            return
        }
        scope.launch {
            try {
                ensureWearablesInitialized()
                val active = deviceSelector().activeDevice()?.identifier
                val streaming =
                        stream?.state?.value ==
                                com.meta.wearable.dat.camera.types.StreamState.STREAMING
                val sessionId = sessionDeviceId
                val devices =
                        Wearables.devices.value.mapNotNull { id ->
                            val idStr = id.identifier
                            if (idStr.isEmpty()) return@mapNotNull null
                            val device = Wearables.devicesMetadata[id]?.value
                            val isActive = idStr == active
                            val isStreamingDevice = streaming && idStr == sessionId
                            if (device != null) {
                                mapOf<String, Any?>(
                                        "id" to idStr,
                                        "name" to device.name,
                                        "deviceType" to deviceTypeCode(device.deviceType),
                                        "linkState" to linkStateCode(device.linkState),
                                        "compatibility" to
                                                compatibilityCode(device.compatibility),
                                        "supportsDisplay" to device.isDisplayCapable(),
                                        "isActive" to isActive,
                                        "isStreamingDevice" to isStreamingDevice,
                                        "firmwareInfo" to device.firmwareInfo,
                                )
                            } else {
                                // Metadata unavailable — complete fallback so the
                                // count still matches Wearables.devices.
                                mapOf<String, Any?>(
                                        "id" to idStr,
                                        "name" to idStr,
                                        "deviceType" to "unknown",
                                        "linkState" to "unknown",
                                        "compatibility" to "undefined",
                                        "supportsDisplay" to false,
                                        "isActive" to isActive,
                                        "isStreamingDevice" to isStreamingDevice,
                                        "firmwareInfo" to null,
                                )
                            }
                        }
                result.success(devices)
            } catch (e: Exception) {
                result.error(
                        "GET_DEVICES_ERROR",
                        e.message ?: "Failed to list devices.",
                        null,
                )
            }
        }
    }

    /** Canonical device-type code, kept identical to the iOS side. */
    private fun deviceTypeCode(type: com.meta.wearable.dat.core.types.DeviceType): String {
        return when (type) {
            com.meta.wearable.dat.core.types.DeviceType.RAYBAN_META -> "rayBanMeta"
            com.meta.wearable.dat.core.types.DeviceType.OAKLEY_META_HSTN -> "oakleyMetaHSTN"
            com.meta.wearable.dat.core.types.DeviceType.OAKLEY_META_VANGUARD ->
                    "oakleyMetaVanguard"
            com.meta.wearable.dat.core.types.DeviceType.META_RAYBAN_DISPLAY ->
                    "metaRayBanDisplay"
            com.meta.wearable.dat.core.types.DeviceType.RAYBAN_META_OPTICS -> "rayBanMetaOptics"
            com.meta.wearable.dat.core.types.DeviceType.META_GLASSES -> "metaGlasses"
            com.meta.wearable.dat.core.types.DeviceType.UNKNOWN -> "unknown"
            else -> "unknown"
        }
    }

    /** Canonical link-state code, kept identical to the iOS side. */
    private fun linkStateCode(state: com.meta.wearable.dat.core.types.LinkState): String {
        return when (state) {
            com.meta.wearable.dat.core.types.LinkState.DISCONNECTED -> "disconnected"
            com.meta.wearable.dat.core.types.LinkState.CONNECTING -> "connecting"
            com.meta.wearable.dat.core.types.LinkState.CONNECTED -> "connected"
            else -> "unknown"
        }
    }

    /** Canonical compatibility code, kept identical to the iOS side. */
    private fun compatibilityCode(
            compatibility: com.meta.wearable.dat.core.types.DeviceCompatibility
    ): String {
        return when (compatibility) {
            com.meta.wearable.dat.core.types.DeviceCompatibility.UNDEFINED -> "undefined"
            com.meta.wearable.dat.core.types.DeviceCompatibility.COMPATIBLE -> "compatible"
            com.meta.wearable.dat.core.types.DeviceCompatibility.DEVICE_UPDATE_REQUIRED ->
                    "deviceUpdateRequired"
            com.meta.wearable.dat.core.types.DeviceCompatibility.SDK_UPDATE_REQUIRED ->
                    "sdkUpdateRequired"
            else -> "undefined"
        }
    }

    private fun getRegistrationState(result: Result) {
        try {
            ensureWearablesInitialized()
        } catch (e: Exception) {
            result.error("REGISTRATION_ERROR", e.message ?: "Failed to initialize Wearables.", null)
            return
        }
        scope.launch {
            try {
                val state = Wearables.registrationState.first()
                result.success(mapRegistrationState(state))
            } catch (e: Exception) {
                result.error(
                        "REGISTRATION_ERROR",
                        e.message ?: "Failed to fetch registration state.",
                        null
                )
            }
        }
    }

    // endregion

    // region URL Handling

    private fun handleUrl(call: MethodCall, result: Result) {
        // Note: handleUri is not available in the Android SDK (iOS only)
        // Deep link handling on Android is typically done at the app level
        result.success(false)
    }

    /**
     * Opens the Meta AI app to the DAT-app-update screen on the connected
     * glasses. Companion to the `datAppOnTheGlassesUpdateRequired`
     * `DeviceSessionError` surfaced on `streamSessionErrorStream()` — apps
     * receiving that error should call this method to prompt the user to
     * update the on-device DAT app before retrying. Cross-platform parity
     * with iOS `Wearables.shared.openDATGlassesAppUpdate()`.
     */
    private fun openDATGlassesAppUpdate(result: Result) {
        val act = activity
        if (act == null) {
            result.error("NO_ACTIVITY", "No activity bound to plugin", null)
            return
        }
        Wearables.openDATGlassesAppUpdate(act)
                .onSuccess { result.success(true) }
                .onFailure { error, _ ->
                    val identifier = error.toString().uppercase()
                    val code =
                            when {
                                identifier.contains("META_AI") ||
                                        identifier.contains("META AI") ||
                                        identifier.contains("NOT_INSTALLED") ->
                                        "metaAINotInstalled"
                                identifier.contains("NOT_REGISTERED") -> "notRegistered"
                                else -> "NAVIGATION_ERROR"
                            }
                    result.error(code, error.description, null)
                }
    }

    // endregion

    // region Background Streaming

    private fun enableBackgroundStreaming(call: MethodCall, result: Result) {
        val app = application
        if (app == null) {
            result.error(
                    "BACKGROUND_STREAMING_ERROR",
                    "Application context is not available.",
                    null,
            )
            return
        }
        val notification =
                @Suppress("UNCHECKED_CAST")
                (call.argument<Map<String, Any>>("androidNotification"))
        if (notification == null) {
            result.error(
                    "INVALID_ARGS",
                    "androidNotification is required on Android to display the foreground-service notification.",
                    null,
            )
            return
        }

        // On Android 13+ (API 33+), POST_NOTIFICATIONS is a runtime permission.
        // Without it the foreground service still runs, but the notification is
        // silently suppressed — so prompt for it now before starting the service.
        // Older API levels auto-grant, so this branch is a no-op pre-Tiramisu.
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.TIRAMISU) {
            val act = activity
            val granted =
                    app.let {
                        ContextCompat.checkSelfPermission(
                                it,
                                android.Manifest.permission.POST_NOTIFICATIONS,
                        ) == PackageManager.PERMISSION_GRANTED
                    }
            if (!granted && act != null) {
                pendingBackgroundCall = call
                pendingBackgroundResult = result
                ActivityCompat.requestPermissions(
                        act,
                        arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                        NOTIFICATION_PERMISSION_REQUEST_CODE,
                )
                return
            }
        }

        startBackgroundStreamingService(call, result)
    }

    private fun startBackgroundStreamingService(call: MethodCall, result: Result) {
        val app = application
        if (app == null) {
            result.error(
                    "BACKGROUND_STREAMING_ERROR",
                    "Application context is not available.",
                    null,
            )
            return
        }
        val notification =
                @Suppress("UNCHECKED_CAST")
                (call.argument<Map<String, Any>>("androidNotification"))
        if (notification == null) {
            result.error(
                    "INVALID_ARGS",
                    "androidNotification is required on Android to display the foreground-service notification.",
                    null,
            )
            return
        }
        try {
            val intent = Intent(app, BackgroundStreamingService::class.java).apply {
                putExtra(
                        BackgroundStreamingService.EXTRA_TITLE,
                        notification["title"] as? String,
                )
                putExtra(
                        BackgroundStreamingService.EXTRA_TEXT,
                        notification["text"] as? String,
                )
                putExtra(
                        BackgroundStreamingService.EXTRA_CHANNEL_ID,
                        notification["channelId"] as? String,
                )
                putExtra(
                        BackgroundStreamingService.EXTRA_CHANNEL_NAME,
                        notification["channelName"] as? String,
                )
                putExtra(
                        BackgroundStreamingService.EXTRA_ICON_RESOURCE_NAME,
                        notification["iconResourceName"] as? String,
                )
            }
            ContextCompat.startForegroundService(app, intent)
            backgroundStreamingStarted = true
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start BackgroundStreamingService", e)
            result.error(
                    "BACKGROUND_STREAMING_ERROR",
                    e.message ?: "Failed to start background streaming service.",
                    null,
            )
        }
    }

    private fun disableBackgroundStreaming(result: Result) {
        try {
            stopBackgroundServiceIfRunning()
            result.success(null)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to stop BackgroundStreamingService", e)
            result.error(
                    "BACKGROUND_STREAMING_ERROR",
                    e.message ?: "Failed to stop background streaming service.",
                    null,
            )
        }
    }

    private fun stopBackgroundServiceIfRunning() {
        if (!backgroundStreamingStarted) return
        val app = application ?: return
        app.stopService(Intent(app, BackgroundStreamingService::class.java))
        backgroundStreamingStarted = false
    }

    // endregion

    // region Streaming

    /**
     * True when starting would immediately contradict the background contract.
     * Checked at the commit point too, not just on entry, because a start can
     * be in flight when the app backgrounds.
     */
    private val mustNotStreamNow: Boolean
        get() = isAppInBackground && !backgroundStreamingStarted

    private fun startStreamSession(call: MethodCall, result: Result) {
        val app = application
        if (app == null) {
            result.error("STREAM_ERROR", "Application context is not available.", null)
            return
        }

        // Refuse outright while backgrounded — the belt to the contract's
        // braces. Even a consumer whose retry logic ignores
        // `stoppedForBackground` cannot reactivate the glasses camera from the
        // background. Same error code as iOS so Dart handling is uniform.
        if (mustNotStreamNow) {
            result.error(
                    "APP_BACKGROUNDED",
                    "Cannot start a stream while the app is backgrounded. " +
                            "Call enableBackgroundStreaming() first if you need background capture.",
                    null,
            )
            return
        }

        // Guard: the SDK can't create a selector/session until initialized, and
        // `ensureWearablesInitialized()` no-ops without BT permission. Bail with a
        // defined error before any pin mutation / selector construction / texture.
        if (!btPermissionsGranted) {
            result.error(
                    "NOT_INITIALIZED",
                    "Bluetooth permissions not granted; call requestAndroidPermissions() first.",
                    null,
            )
            return
        }

        val args = call.arguments as? Map<*, *>
        val fps = (args?.get("fps") as? Double) ?: 30.0
        val streamQuality = parseStreamQuality(args?.get("streamQuality") as? String)
        val videoCodec = args?.get("videoCodec") as? String
        val deviceId = args?.get("deviceId") as? String
        val key = deviceId ?: "auto"

        if (videoCodec != null && videoCodec != "raw") {
            Log.d(TAG, "videoCodec '$videoCodec' ignored on Android (only raw I420 supported)")
        }

        // A non-nil `stream` only counts as active if it's not terminal: the SDK
        // can stop a stream (hinges, thermal) without clearing our reference.
        // Same selection → return the existing texture; a *different* device →
        // caller must stop first; a stale (terminal) stream is torn down and
        // recreated below.
        val existingStream = stream
        if (existingStream != null) {
            val st = existingStream.state.value
            // PAUSED counts as LIVE, deliberately. There is no public
            // resume, but that is because the SDK drives the stream out of
            // PAUSED itself — Meta's guidance is "On PAUSED, keep the
            // connection and wait for STARTED or STOPPED". thermalCritical
            // pauses exactly this way and resumes once the glasses cool, so
            // tearing down here would destroy the SDK's own thermal recovery.
            // An app that really does want a fresh session calls
            // stopStreamSession() first, which never reaches this guard.
            // Mirrors the iOS guard.
            val live =
                    st != com.meta.wearable.dat.camera.types.StreamState.STOPPED &&
                            st !=
                                    com.meta.wearable.dat.camera.types.StreamState
                                            .STOPPING &&
                            st != com.meta.wearable.dat.camera.types.StreamState.CLOSED
            if (live) {
                if (deviceId == pinnedDeviceId) {
                    val entry = textureEntry
                    if (entry != null) {
                        result.success(entry.id())
                    } else {
                        result.error(
                                "TEXTURE_REGISTRATION_FAILED",
                                "No texture registered for session $key",
                                null,
                        )
                    }
                } else {
                    result.error(
                            "STREAM_ACTIVE",
                            "A stream is already active on another device. Stop it before switching devices.",
                            null,
                    )
                }
                return
            }
            // Stale (terminal) stream — drop it and recreate below.
            teardownStreamOnly()
        }

        // Reject a concurrent start: a second start that tore down the first's
        // in-flight session (on a pin change) would leave the first awaiting
        // STARTED forever.
        if (startInProgress) {
            result.error(
                    "STREAM_ACTIVE",
                    "A stream start is already in progress.",
                    null,
            )
            return
        }
        startInProgress = true

        scope.launch {
            try {
                ensureWearablesInitialized()

                // Apply a pin change (or clear) before creating the session:
                // rebuild the shared selector and rebind every observer. The
                // availability watchdog is relaunched by ensureSessionStarted()
                // below (it re-reads deviceSelector()).
                val pinChanged = deviceId != pinnedDeviceId
                if (pinChanged) {
                    pinnedDeviceId = deviceId
                    teardownSession()
                    deviceSelectorRef = makeDeviceSelector()
                    activeDeviceStreamHandler?.restartMonitoring(force = true)
                    deviceStateStreamHandler?.restartMonitoring(force = true)
                }

                // The just-rebuilt selector resolves its active device
                // asynchronously; creating the session before it resolves
                // returns noEligibleDevice. When a specific device is pinned,
                // wait briefly for it to resolve.
                if (pinChanged && deviceId != null) {
                    withTimeoutOrNull(8_000L) {
                        deviceSelector().activeDeviceFlow().first { it != null }
                    }
                }

                sessionKey = key
                frameProcessor.configure(fps)

                // Register a Flutter texture for zero-copy rendering
                val registry = textureRegistry
                if (registry == null) {
                    result.error(
                            "TEXTURE_REGISTRATION_FAILED",
                            "TextureRegistry is not available.",
                            null,
                    )
                    return@launch
                }
                val entry = registry.createSurfaceTexture()
                val surfaceTexture = entry.surfaceTexture()
                surfaceTexture.setDefaultBufferSize(1280, 720)
                val surface = Surface(surfaceTexture)
                textureEntry = entry
                textureSurface = surface
                val textureId = entry.id()
                Log.d(TAG, "Registered texture $textureId for session $key")

                val activeSession = ensureSessionStarted() ?: run {
                    teardownStreamOnly()
                    result.error(
                            "STREAM_ERROR",
                            "Failed to create or start device session.",
                            null,
                    )
                    return@launch
                }

                // DAT 0.9.0 replaced `addStream` with `addCamera`; the returned
                // `Camera` owns the stream.
                var addedCamera: Camera? = null
                activeSession
                        .addCamera(StreamConfiguration(videoQuality = streamQuality, fps.toInt()))
                        .onSuccess { addedCamera = it }
                        .onFailure { error, _ ->
                            val code =
                                    when {
                                        error.description.contains("already", ignoreCase = true) ->
                                                "capabilityAlreadyActive"
                                        else -> "unexpectedError"
                                    }
                            streamSessionErrorStreamHandler?.sendError(code, error.description)
                            Log.e(TAG, "addCamera failed: ${error.description}")
                        }

                val newCamera = addedCamera
                if (newCamera == null) {
                    teardownStreamOnly()
                    result.error("STREAM_ERROR", "Failed to add camera to session.", null)
                    return@launch
                }
                val newStream = newCamera.stream

                camera = newCamera
                stream = newStream
                streamStateStreamHandler?.stream = newStream

                videoJob =
                        scope.launch(Dispatchers.Default) {
                            newStream.videoStream.collect { videoFrame ->
                                if (frameProcessor.needsBufferSizeUpdate(
                                                videoFrame.width,
                                                videoFrame.height,
                                        )
                                ) {
                                    val (targetWidth, targetHeight) =
                                            frameProcessor.targetDimensions(
                                                    videoFrame.width,
                                                    videoFrame.height,
                                            )
                                    entry.surfaceTexture()
                                            .setDefaultBufferSize(targetWidth, targetHeight)
                                    videoStreamSizeStreamHandler?.send(targetWidth, targetHeight)
                                    frameProcessor.onSurfaceBufferSizeApplied(
                                            videoFrame.width,
                                            videoFrame.height,
                                    )
                                }
                                // Emit the raw I420 frame to Dart for recording /
                                // custom processing before handing off to the
                                // texture renderer. Guarded on hasListener so
                                // unsubscribed apps pay nothing.
                                if (videoFrameStreamHandler.hasListener) {
                                    emitVideoFrame(videoFrame)
                                }
                                frameProcessor.processFrame(videoFrame, surface)
                            }
                        }

                streamErrorJob =
                        scope.launch {
                            newStream.errorStream.collect { streamError ->
                                Log.e(
                                        TAG,
                                        "Stream error: $streamError (${streamError.description})",
                                )
                                streamSessionErrorStreamHandler?.send(streamError)
                            }
                        }

                // Teardown cascades parent -> child but NOT child -> parent, so a
                // `start()` returns a DatResult that used to be discarded,
                // silently swallowing start failures. A failure here means the
                // texture will never receive a frame, so tear it down and fail
                // the call — returning success would hand back a dead texture,
                // and an app without an error-stream subscription would see a
                // successful Future and a permanently frozen view. The typed
                // error still goes out on the channel for subscribers.
                //
                // iOS cannot do this: its `Stream.start()` returns Void, so a
                // synchronous start failure is undetectable there and the
                // texture is always returned.
                var startFailure: String? = null
                newStream.start().onFailure { error, _ ->
                    Log.e(TAG, "Stream start failed: ${error.description}")
                    streamSessionErrorStreamHandler?.send(error)
                    startFailure = error.description
                }
                val failure = startFailure
                if (failure != null) {
                    teardownStreamOnly()
                    result.error("STREAM_ERROR", failure, null)
                    return@launch
                }
                // Last commit point. Bringing a session up can take seconds,
                // which is ample time for the user to background the app
                // mid-start. Committing anyway would leave a live stream
                // running in a backgrounded app that nothing will stop.
                if (mustNotStreamNow) {
                    Log.d(TAG, "app backgrounded during start — abandoning")
                    teardownStreamOnly()
                    result.error(
                            "APP_BACKGROUNDED",
                            "The app was backgrounded before the stream could start.",
                            null,
                    )
                    return@launch
                }
                result.success(textureId)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start stream session", e)
                teardownStreamOnly()
                result.error("STREAM_ERROR", e.message ?: "Failed to start stream session.", null)
            } finally {
                startInProgress = false
            }
        }
    }

    /**
     * Lazily create and start a [DeviceSession], reusing an existing one
     * across stream start/stop toggles. Returns `null` if creation or
     * start-up failed (an error has already been pushed onto the error stream).
     */
    private suspend fun ensureSessionStarted(): DeviceSession? {
        val existing = session
        if (existing != null) {
            val currentState = existing.state.firstOrNull()
            if (currentState == DeviceSessionState.STARTED) {
                return existing
            }
        }

        // Capture the auto-selector's current pick *before* createSession so a
        // later A→B switch can't misattribute which device this session bound.
        val candidate = deviceSelector().activeDevice()?.identifier
        var created: DeviceSession? = null
        Wearables.createSession(deviceSelector())
                .onSuccess {
                    created = it
                    sessionDeviceId = candidate
                }
                .onFailure { error, _ ->
                    sessionDeviceId = null
                    val identifier = error.description.lowercase()
                    val code =
                            when {
                                identifier.contains("no eligible") -> "noEligibleDevice"
                                identifier.contains("already") -> "sessionAlreadyExists"
                                else -> "unexpectedError"
                            }
                    streamSessionErrorStreamHandler?.sendError(code, error.description)
                    Log.e(TAG, "createSession failed: ${error.description}")
                }

        val newSession = created ?: return null
        session = newSession
        newSession.start()

        // 0.7.0: subscribe to DeviceSession.errors so session-scoped errors
        // (thermal, battery, peakPower, datAppUpdate, dwaUnavailable) reach
        // Dart on the same event channel as stream errors. Replace any
        // previous subscription — sessions are reused across start/stop
        // toggles, but this is the canonical point to (re-)attach.
        sessionErrorsJob?.cancel()
        sessionErrorsJob =
                scope.launch {
                    newSession.errors.collect { error ->
                        streamSessionErrorStreamHandler?.send(error)
                    }
                }

        // Wait until the session transitions to STARTED before we try to add a
        // stream — mirrors the reference app pattern. Also bail on a terminal
        // STOPPED so a session torn down underneath us can't hang the awaiter.
        val reached =
                newSession.state.first {
                    it == DeviceSessionState.STARTED || it == DeviceSessionState.STOPPED
                }
        if (reached != DeviceSessionState.STARTED) {
            Log.w(TAG, "Session reached $reached before STARTED; aborting start")
            return null
        }

        // Subscribe to the active-device flow so we tear the Session down
        // when the device disappears. Safe to call multiple times.
        startDeviceAvailabilityMonitoring()

        return newSession
    }

    private fun startDeviceAvailabilityMonitoring() {
        if (deviceAvailabilityJob != null) return
        deviceAvailabilityJob =
                scope.launch {
                    deviceSelector().activeDeviceFlow().collect { device ->
                        if (device == null && session != null) {
                            Log.d(TAG, "Active device lost — tearing down Session")
                            teardownSession()
                        }
                    }
                }
    }

    private fun stopStreamSession(call: MethodCall, result: Result) {
        if (stream == null) {
            val key = sessionKey ?: "auto"
            result.error("SESSION_NOT_FOUND", "No stream found for '$key'.", null)
            return
        }

        teardownStreamOnly()
        result.success(true)
    }

    private fun capturePhoto(call: MethodCall, result: Result) {
        val activeStream = stream
        if (activeStream == null) {
            val key = sessionKey ?: "auto"
            result.error("SESSION_NOT_FOUND", "No active stream for '$key'.", null)
            return
        }

        val args = call.arguments as? Map<*, *>
        val format = args?.get("format") as? String
        if (format != null) {
            Log.d(
                    TAG,
                    "capturePhoto format '$format' received (device decides actual format on Android)",
            )
        }

        scope.launch {
            try {
                val photoResult = activeStream.capturePhoto()
                photoResult
                        .onSuccess { photoData ->
                            val response: Map<String, Any> =
                                    when (photoData) {
                                        is PhotoData.Bitmap -> {
                                            val buffer = ByteArrayOutputStream()
                                            photoData.bitmap.compress(
                                                    android.graphics.Bitmap.CompressFormat.JPEG,
                                                    85,
                                                    buffer,
                                            )
                                            mapOf(
                                                    "bytes" to buffer.toByteArray(),
                                                    "format" to "jpeg",
                                            )
                                        }
                                        is PhotoData.HEIC -> {
                                            val heicBuffer = photoData.data
                                            val bytes = ByteArray(heicBuffer.remaining())
                                            heicBuffer.get(bytes)
                                            mapOf("bytes" to bytes, "format" to "heic")
                                        }
                                    }
                            result.success(response)
                        }
                        .onFailure { error, _ ->
                            val errorCode =
                                    when (error) {
                                        is CaptureError.DeviceDisconnected -> "deviceDisconnected"
                                        is CaptureError.NotStreaming -> "notStreaming"
                                        is CaptureError.CaptureInProgress -> "captureInProgress"
                                        is CaptureError.CaptureFailed -> "captureFailed"
                                    }
                            Log.e(TAG, "Photo capture failed: $errorCode - ${error.description}")
                            // Capture failure is returned to the awaiting Dart
                            // caller via the method-channel error below; it is
                            // not a stream-session error, so (matching iOS) it
                            // is not pushed onto the stream_session_errors channel.
                            result.error("CAPTURE_PHOTO_FAILED", error.description, errorCode)
                        }
            } catch (e: Exception) {
                Log.e(TAG, "Photo capture exception", e)
                result.error("CAPTURE_PHOTO_FAILED", e.message ?: "Photo capture failed.", null)
            }
        }
    }

    /**
     * Copy the raw SDK frame bytes into a ByteArray and push them onto the
     * video_frames event channel. We forward the native I420 layout as-is
     * (no I420→ARGB conversion) — this is the most useful format for
     * on-device recording and keeps per-frame cost low.
     */
    private fun emitVideoFrame(videoFrame: com.meta.wearable.dat.camera.types.VideoFrame) {
        // 0.7.0 added VideoFrame.isCodecConfig to flag parameter-set frames
        // (codec headers) vs payload frames. Recording consumers should never
        // see codec-config frames as payload, so skip them defensively. In
        // practice raw I420 streams shouldn't emit codec-config frames at
        // all — this guard is mostly future-proofing.
        if (videoFrame.isCodecConfig) return
        val buffer = videoFrame.buffer
        val remaining = buffer.remaining()
        if (remaining <= 0) return
        val bytes = ByteArray(remaining)
        val originalPosition = buffer.position()
        buffer.get(bytes, 0, remaining)
        // Restore so the FrameProcessor can still read the same bytes.
        buffer.position(originalPosition)
        videoFrameStreamHandler.emit(
                codec = if (videoFrame.isCompressed) "hvc1" else "raw",
                bytes = bytes,
                width = videoFrame.width,
                height = videoFrame.height,
                ptsUs = videoFrame.presentationTimeUs,
                // SDK does not surface keyframe metadata on Android — assume
                // every frame is self-contained. Accurate for raw I420;
                // conservative for hvc1 (not currently reachable on Android).
                isKeyframe = true,
        )
    }

    /**
     * Tear down only the active stream, keeping the underlying [DeviceSession]
     * alive so a subsequent `startStreamSession` re-uses it via
     * `addCamera` instead of paying the full session-start cost.
     */
    private fun teardownStreamOnly() {
        if (isTearingDownStream) return
        isTearingDownStream = true
        try {
            teardownStreamOnlyLocked()
        } finally {
            isTearingDownStream = false
        }
    }

    private fun teardownStreamOnlyLocked() {
        videoJob?.cancel()
        videoJob = null
        streamErrorJob?.cancel()
        streamErrorJob = null
        // Detach *and* tell Dart. A bare `stream = null` cancels the state
        // collector before `stream.stop()` below produces STOPPING / STOPPED,
        // so every plugin-initiated teardown reached Dart as silence — a live
        // texture id and a frozen preview with nothing to react to. Matches the
        // iOS fix from 0.8.1.
        streamStateStreamHandler?.detachEmittingStopped()
        // Stop BOTH, stream first — they do different jobs and neither
        // substitutes for the other:
        //
        //   * stream.stop() shuts down the capture pipeline on the glasses.
        //     This is what 0.8.0 called; dropping it in favour of camera.stop()
        //     alone left the camera engaged on the device until the whole
        //     DeviceSession went away, so a following start resumed the old
        //     capture instead of starting a fresh one.
        //   * camera.stop() detaches the capability. Required since 0.9.0: the
        //     session stores it under Camera::class, so stopping only the
        //     stream leaves the camera attached and the next addCamera fails
        //     with CAPABILITY_ALREADY_ADDED — and we deliberately keep the
        //     DeviceSession alive across stop/start.
        try {
            stream?.stop()
        } catch (e: Exception) {
            Log.w(TAG, "Error stopping stream: ${e.message}")
        }
        try {
            camera?.stop()
        } catch (e: Exception) {
            Log.w(TAG, "Error stopping camera: ${e.message}")
        }
        camera = null
        stream = null
        sessionKey = null
        textureSurface?.release()
        textureSurface = null
        val entry = textureEntry
        if (entry != null) {
            Log.d(TAG, "Unregistered texture ${entry.id()}")
            entry.release()
        }
        textureEntry = null
        frameProcessor.release()
        videoStreamSizeStreamHandler?.reset()
    }

    /**
     * Tear down the entire session, including the active stream. Called on
     * device loss and plugin dispose. The next `startStreamSession` will create
     * a fresh Session.
     */
    private fun teardownSession() {
        teardownStreamOnly()
        sessionErrorsJob?.cancel()
        sessionErrorsJob = null
        deviceAvailabilityJob?.cancel()
        deviceAvailabilityJob = null
        try {
            session?.stop()
        } catch (e: Exception) {
            Log.w(TAG, "Error stopping session: ${e.message}")
        }
        session = null
        sessionDeviceId = null
    }

    // endregion

    // region Helpers

    private var wearablesInitializedLogged = false

    private fun ensureWearablesInitialized() {
        if (!btPermissionsGranted) {
            Log.d(TAG, "ensureWearablesInitialized — BT permissions not yet granted, skipping")
            return
        }
        val app = application ?: return
        Wearables.initialize(app)
        if (!wearablesInitializedLogged) {
            Log.d(TAG, "ensureWearablesInitialized — Wearables.initialize() called")
            wearablesInitializedLogged = true
        }
    }

    private fun mapRegistrationState(
            state: com.meta.wearable.dat.core.types.RegistrationState
    ): Int {
        // 0.7.0 reshaped RegistrationState from a sealed class hierarchy
        // (Unavailable / Available / Registering / Registered / Unregistering)
        // to a plain enum with UPPER_CASE values. Error payload that used to
        // live on the sealed-class subtypes now flows on
        // `Wearables.registrationErrorStream` — we don't subscribe (plugin
        // didn't surface it before either).
        return when (state) {
            com.meta.wearable.dat.core.types.RegistrationState.UNAVAILABLE -> 0
            com.meta.wearable.dat.core.types.RegistrationState.AVAILABLE -> 1
            com.meta.wearable.dat.core.types.RegistrationState.REGISTERING -> 2
            com.meta.wearable.dat.core.types.RegistrationState.REGISTERED -> 3
            com.meta.wearable.dat.core.types.RegistrationState.UNREGISTERING -> 2
        }
    }

    private fun parseStreamQuality(value: String?): VideoQuality {
        return when (value?.lowercase()) {
            "high" -> VideoQuality.HIGH
            "low" -> VideoQuality.LOW
            "medium" -> VideoQuality.MEDIUM
            else -> VideoQuality.HIGH
        }
    }

    // endregion
}
