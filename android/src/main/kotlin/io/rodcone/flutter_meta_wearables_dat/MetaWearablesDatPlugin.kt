package io.rodcone.flutter_meta_wearables_dat

import android.app.Activity
import android.app.Application
import android.content.Intent
import android.content.pm.PackageManager
import android.util.Log
import android.view.Surface
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.meta.wearable.dat.camera.StreamSession
import com.meta.wearable.dat.camera.startStreamSession
import com.meta.wearable.dat.camera.types.CaptureError
import com.meta.wearable.dat.camera.types.PhotoData
import com.meta.wearable.dat.camera.types.StreamConfiguration
import com.meta.wearable.dat.camera.types.VideoQuality
import com.meta.wearable.dat.core.Wearables
import com.meta.wearable.dat.core.selectors.AutoDeviceSelector
import com.meta.wearable.dat.core.selectors.DeviceSelector
import com.meta.wearable.dat.core.types.Permission
import com.meta.wearable.dat.core.types.PermissionStatus
import com.meta.wearable.dat.mockdevice.MockDeviceKit
import com.meta.wearable.dat.mockdevice.api.MockRaybanMeta
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
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
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
    private var application: Application? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var activeDeviceStreamHandler: ActiveDeviceStreamHandler? = null
    private var registrationStateStreamHandler: RegistrationStateStreamHandler? = null
    private var streamSessionStateStreamHandler: StreamSessionStateStreamHandler? = null
    private var streamSessionErrorStreamHandler: StreamSessionErrorStreamHandler? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    // Gate SDK initialization until BT permissions are granted (mirrors reference app).
    private var btPermissionsGranted = false

    // Permission request handling
    private var permissionContinuation: CancellableContinuation<PermissionStatus>? = null
    private val permissionMutex = Mutex()
    private val permissionContract = Wearables.RequestPermissionContract()
    private var btPermissionResult: Result? = null

    // Single shared device selector — mirrors reference app's WearablesViewModel pattern.
    // One instance is shared across device monitoring and stream session creation.
    private val deviceSelector: DeviceSelector = AutoDeviceSelector()

    // Streaming state
    private var streamSession: StreamSession? = null
    private var sessionKey: String? = null
    private var videoJob: Job? = null
    private var stateJob: Job? = null
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
                        deviceSelector,
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
        streamSessionStateStreamHandler = StreamSessionStateStreamHandler()
        streamSessionStateChannel.setStreamHandler(streamSessionStateStreamHandler)

        streamSessionErrorChannel =
                EventChannel(
                        flutterPluginBinding.binaryMessenger,
                        "flutter_meta_wearables_dat/stream_session_errors"
                )
        streamSessionErrorStreamHandler = StreamSessionErrorStreamHandler()
        streamSessionErrorChannel.setStreamHandler(streamSessionErrorStreamHandler)

        textureRegistry = flutterPluginBinding.textureRegistry

        val context = flutterPluginBinding.applicationContext
        application = context as? Application
        // NOTE: Do NOT call ensureWearablesInitialized() here.
        // The reference app initializes the SDK only AFTER Bluetooth permissions
        // are granted. Calling it before permissions breaks device discovery.
        // The SDK will be initialized lazily when first needed (e.g. after
        // requestAndroidPermissions grants BT permissions).
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "requestAndroidPermissions" -> requestAndroidPermissions(result)
            "startRegistration" -> startRegistration(result)
            "disconnect" -> disconnect(result)
            "getRegistrationState" -> getRegistrationState(result)
            "getCameraPermissionStatus" -> getCameraPermissionStatus(result)
            "requestCameraPermission" -> requestCameraPermission(result)
            "handleUrl" -> handleUrl(call, result)
            "pairMockRayBanMeta" -> pairMockRayBanMeta(result)
            "unpairMockRayBanMeta" -> unpairMockRayBanMeta(call, result)
            "mockDevicePowerOn", "mockDevicePowerOff", "mockDeviceDon", "mockDeviceDoff" ->
                    mockDeviceAction(call, result)
            "setMockCameraFeed" -> setMockCameraFeed(call, result)
            "setMockCapturedImage" -> setMockCapturedImage(call, result)
            "restartActiveDeviceMonitoring" -> {
                activeDeviceStreamHandler?.restartMonitoring()
                result.success(true)
            }
            "startStreamSession" -> startStreamSession(call, result)
            "stopStreamSession" -> stopStreamSession(call, result)
            "capturePhoto" -> capturePhoto(call, result)
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
        streamSessionStateStreamHandler?.dispose()
        streamSessionStateStreamHandler = null
        streamSessionErrorChannel.setStreamHandler(null)
        streamSessionErrorStreamHandler?.dispose()
        streamSessionErrorStreamHandler = null

        // Clean up stream session
        cleanupSession()

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
        val status = permissionContract.parseResult(resultCode, data)
        val permissionStatus = status.getOrDefault(PermissionStatus.Denied)
        permissionContinuation?.resume(permissionStatus)
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
        if (requestCode != BT_PERMISSION_REQUEST_CODE) return false
        val pendingResult = btPermissionResult ?: return false
        btPermissionResult = null
        val allGranted =
                grantResults.isNotEmpty() &&
                        grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        if (allGranted) {
            // Initialize SDK now that BT permissions are granted (mirrors reference app pattern)
            btPermissionsGranted = true
            ensureWearablesInitialized()
            // Start monitoring now that SDK is properly initialized with permissions
            registrationStateStreamHandler?.restartMonitoring()
            activeDeviceStreamHandler?.restartMonitoring()
        }
        pendingResult.success(allGranted)
        return true
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
            btPermissionsGranted = true
            ensureWearablesInitialized()
            registrationStateStreamHandler?.restartMonitoring()
            activeDeviceStreamHandler?.restartMonitoring()
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
                        "PERMISSION_ERROR",
                        e.message ?: "Failed to check camera permission status.",
                        null
                )
            }
        }
    }

    private suspend fun checkCameraPermissionStatus(result: Result): PermissionStatus? {
        val checkResult = Wearables.checkPermissionStatus(Permission.CAMERA)
        var permissionErrorMessage: String? = null
        checkResult.onFailure { error, _ -> permissionErrorMessage = error.description }
        if (permissionErrorMessage != null) {
            result.error("PERMISSION_ERROR", permissionErrorMessage, null)
            return null
        }
        return checkResult.getOrNull() ?: PermissionStatus.Denied
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
                        result.success(true)
                        return@withLock
                    }

                    val act = activity
                    if (act == null) {
                        result.error(
                                "PERMISSION_ERROR",
                                "Activity is not available. Ensure the app is in the foreground.",
                                null
                        )
                        return@withLock
                    }

                    val permissionStatus =
                            suspendCancellableCoroutine<PermissionStatus> { continuation ->
                                permissionContinuation = continuation
                                continuation.invokeOnCancellation { permissionContinuation = null }
                                val intent = permissionContract.createIntent(act, Permission.CAMERA)
                                act.startActivityForResult(intent, PERMISSION_REQUEST_CODE)
                            }

                    result.success(permissionStatus == PermissionStatus.Granted)
                } catch (e: Exception) {
                    result.error(
                            "PERMISSION_ERROR",
                            e.message ?: "Failed to request permission.",
                            null
                    )
                }
            }
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

    // region Mock Device

    private fun pairMockRayBanMeta(result: Result) {
        val app = application
        if (app == null) {
            result.error("MOCK_DEVICE_ERROR", "Application context is not available.", null)
            return
        }
        try {
            val mockDevice = MockDeviceKit.getInstance(app).pairRaybanMeta()
            result.success(mockDevice.deviceIdentifier.toString())
        } catch (e: Exception) {
            result.error("MOCK_DEVICE_ERROR", e.message ?: "Failed to pair mock device", null)
        }
    }

    private fun unpairMockRayBanMeta(call: MethodCall, result: Result) {
        val app = application
        if (app == null) {
            result.error("MOCK_DEVICE_ERROR", "Application context is not available.", null)
            return
        }
        val deviceId = call.argument<String>("deviceUUID")
        if (deviceId == null) {
            result.error("INVALID_ARGS", "deviceUUID is missing", null)
            return
        }
        try {
            val kit = MockDeviceKit.getInstance(app)
            val device = kit.pairedDevices.find { it.deviceIdentifier.toString() == deviceId }
            if (device != null) {
                kit.unpairDevice(device)
                result.success(true)
            } else {
                result.error("DEVICE_NOT_FOUND", "No mock device found with uuid $deviceId", null)
            }
        } catch (e: Exception) {
            result.error("MOCK_DEVICE_ERROR", e.message ?: "Failed to unpair mock device", null)
        }
    }

    private fun mockDeviceAction(call: MethodCall, result: Result) {
        val app = application
        if (app == null) {
            result.error("MOCK_DEVICE_ERROR", "Application context is not available.", null)
            return
        }
        val deviceId = call.argument<String>("deviceUUID")
        if (deviceId == null) {
            result.error("INVALID_ARGS", "deviceUUID is missing", null)
            return
        }
        try {
            val kit = MockDeviceKit.getInstance(app)
            val device = kit.pairedDevices.find { it.deviceIdentifier.toString() == deviceId }
            if (device != null) {
                when (call.method) {
                    "mockDevicePowerOn" -> device.powerOn()
                    "mockDevicePowerOff" -> device.powerOff()
                    "mockDeviceDon" -> device.don()
                    "mockDeviceDoff" -> device.doff()
                }
                result.success(true)
            } else {
                result.error("DEVICE_NOT_FOUND", "No mock device found with uuid $deviceId", null)
            }
        } catch (e: Exception) {
            result.error("MOCK_DEVICE_ERROR", e.message ?: "Failed to perform action", null)
        }
    }

    private fun setMockCameraFeed(call: MethodCall, result: Result) {
        val app = application
        if (app == null) {
            result.error("MOCK_DEVICE_ERROR", "Application context is not available.", null)
            return
        }
        val deviceId = call.argument<String>("deviceUUID")
        val videoPath = call.argument<String>("videoPath")
        if (deviceId == null) {
            result.error("INVALID_ARGS", "deviceUUID is missing", null)
            return
        }
        try {
            val kit = MockDeviceKit.getInstance(app)
            val device = kit.pairedDevices.find { it.deviceIdentifier.toString() == deviceId }
            if (device is MockRaybanMeta) {
                if (videoPath != null) {
                    device.getCameraKit().setCameraFeed(android.net.Uri.parse(videoPath))
                }
                result.success(true)
            } else {
                result.error("INVALID_DEVICE", "Device is not a mock glasses device", null)
            }
        } catch (e: Exception) {
            result.error("MOCK_DEVICE_ERROR", e.message ?: "Failed to set camera feed", null)
        }
    }

    private fun setMockCapturedImage(call: MethodCall, result: Result) {
        val app = application
        if (app == null) {
            result.error("MOCK_DEVICE_ERROR", "Application context is not available.", null)
            return
        }
        val deviceId = call.argument<String>("deviceUUID")
        val imagePath = call.argument<String>("imagePath")
        if (deviceId == null) {
            result.error("INVALID_ARGS", "deviceUUID is missing", null)
            return
        }
        try {
            val kit = MockDeviceKit.getInstance(app)
            val device = kit.pairedDevices.find { it.deviceIdentifier.toString() == deviceId }
            if (device is MockRaybanMeta) {
                if (imagePath != null) {
                    device.getCameraKit().setCapturedImage(android.net.Uri.parse(imagePath))
                }
                result.success(true)
            } else {
                result.error("INVALID_DEVICE", "Device is not a mock glasses device", null)
            }
        } catch (e: Exception) {
            result.error("MOCK_DEVICE_ERROR", e.message ?: "Failed to set captured image", null)
        }
    }

    // endregion

    // region URL Handling

    private fun handleUrl(call: MethodCall, result: Result) {
        // Note: handleUri is not available in the Android SDK (iOS only)
        // Deep link handling on Android is typically done at the app level
        result.success(false)
    }

    // endregion

    // region Streaming

    private fun startStreamSession(call: MethodCall, result: Result) {
        val app = application
        if (app == null) {
            result.error("STREAM_ERROR", "Application context is not available.", null)
            return
        }

        val args = call.arguments as? Map<*, *>
        val fps = (args?.get("fps") as? Double) ?: 30.0
        val streamQuality = parseStreamQuality(args?.get("streamQuality") as? String)
        val videoCodec = args?.get("videoCodec") as? String
        val deviceUUID = args?.get("deviceUUID") as? String
        val key = deviceUUID ?: "auto"

        if (videoCodec != null && videoCodec != "raw") {
            Log.d(TAG, "videoCodec '$videoCodec' ignored on Android (only raw I420 supported)")
        }

        if (streamSession != null) {
            val entry = textureEntry
            if (entry != null) {
                result.success(entry.id())
            } else {
                result.error("TEXTURE_REGISTRATION_FAILED", "No texture registered for session $key", null)
            }
            return
        }

        scope.launch {
            try {
                ensureWearablesInitialized()

                sessionKey = key
                frameProcessor.configure(fps)

                // Register a Flutter texture for zero-copy rendering
                val registry = textureRegistry
                if (registry == null) {
                    result.error("TEXTURE_REGISTRATION_FAILED", "TextureRegistry is not available.", null)
                    return@launch
                }
                val entry = registry.createSurfaceTexture()
                val surfaceTexture = entry.surfaceTexture()
                // Set default buffer size — will be updated when first frame arrives
                surfaceTexture.setDefaultBufferSize(1280, 720)
                val surface = Surface(surfaceTexture)
                textureEntry = entry
                textureSurface = surface
                val textureId = entry.id()
                Log.d(TAG, "Registered texture $textureId for session $key")

                val session =
                        Wearables.startStreamSession(
                                app,
                                deviceSelector,
                                StreamConfiguration(videoQuality = streamQuality, fps.toInt())
                        )
                streamSession = session
                streamSessionStateStreamHandler?.session = session
                streamSessionErrorStreamHandler?.session = session

                // Subscribe to video frames — render I420 → ARGB bitmap → SurfaceTexture
                videoJob = scope.launch(Dispatchers.Default) {
                    session.videoStream.collect { videoFrame ->
                        // Update SurfaceTexture buffer size if frame dimensions change
                        if (frameProcessor.needsBufferSizeUpdate(videoFrame.width, videoFrame.height)) {
                            entry.surfaceTexture().setDefaultBufferSize(videoFrame.width, videoFrame.height)
                        }
                        frameProcessor.processFrame(videoFrame, surface)
                    }
                }

                stateJob =
                        scope.launch {
                            session.state.collect { state ->
                                Log.d(TAG, "StreamSession [$key] state: $state")
                            }
                        }

                result.success(textureId)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start stream session", e)
                cleanupSession()
                result.error("STREAM_ERROR", e.message ?: "Failed to start stream session.", null)
            }
        }
    }

    private fun stopStreamSession(call: MethodCall, result: Result) {
        val session = streamSession
        if (session == null) {
            val key = sessionKey ?: "auto"
            result.error("SESSION_NOT_FOUND", "No stream session found for '$key'.", null)
            return
        }

        cleanupSession()
        result.success(true)
    }

    private fun capturePhoto(call: MethodCall, result: Result) {
        val session = streamSession
        if (session == null) {
            val key = sessionKey ?: "auto"
            result.error("SESSION_NOT_FOUND", "No stream session found for '$key'.", null)
            return
        }

        val args = call.arguments as? Map<*, *>
        val format = args?.get("format") as? String
        if (format != null) {
            Log.d(TAG, "capturePhoto format '$format' received (device decides actual format on Android)")
        }

        scope.launch {
            try {
                val photoResult = session.capturePhoto()
                photoResult
                        .onSuccess { photoData ->
                            val response: Map<String, Any> =
                                    when (photoData) {
                                        is PhotoData.Bitmap -> {
                                            val stream = ByteArrayOutputStream()
                                            photoData.bitmap.compress(
                                                    android.graphics.Bitmap.CompressFormat.JPEG,
                                                    85,
                                                    stream
                                            )
                                            mapOf(
                                                    "bytes" to stream.toByteArray(),
                                                    "format" to "jpeg"
                                            )
                                        }
                                        is PhotoData.HEIC -> {
                                            val buffer = photoData.data
                                            val bytes = ByteArray(buffer.remaining())
                                            buffer.get(bytes)
                                            mapOf("bytes" to bytes, "format" to "heic")
                                        }
                                    }
                            result.success(response)
                        }
                        .onFailure { error, _ ->
                            val errorCode = when (error) {
                                is CaptureError.DeviceDisconnected -> "deviceDisconnected"
                                is CaptureError.NotStreaming -> "notStreaming"
                                is CaptureError.CaptureInProgress -> "captureInProgress"
                                is CaptureError.CaptureFailed -> "captureFailed"
                            }
                            Log.e(TAG, "Photo capture failed: $errorCode - ${error.description}")
                            streamSessionErrorStreamHandler?.sendError(errorCode, error.description)
                            result.error("CAPTURE_PHOTO_FAILED", error.description, errorCode)
                        }
            } catch (e: Exception) {
                Log.e(TAG, "Photo capture exception", e)
                result.error("CAPTURE_PHOTO_FAILED", e.message ?: "Photo capture failed.", null)
            }
        }
    }

    private fun cleanupSession() {
        videoJob?.cancel()
        videoJob = null
        stateJob?.cancel()
        stateJob = null
        streamSessionStateStreamHandler?.session = null
        streamSessionErrorStreamHandler?.session = null
        streamSession?.close()
        streamSession = null
        sessionKey = null
        // Release texture resources
        textureSurface?.release()
        textureSurface = null
        val entry = textureEntry
        if (entry != null) {
            Log.d(TAG, "Unregistered texture ${entry.id()}")
            entry.release()
        }
        textureEntry = null
        frameProcessor.release()
    }

    // endregion

    // region Helpers

    private fun ensureWearablesInitialized() {
        if (!btPermissionsGranted) return
        val app = application ?: return
        Wearables.initialize(app)
    }

    private fun mapRegistrationState(
            state: com.meta.wearable.dat.core.types.RegistrationState
    ): Int {
        return when (state) {
            is com.meta.wearable.dat.core.types.RegistrationState.Unavailable -> 0
            is com.meta.wearable.dat.core.types.RegistrationState.Available -> 1
            is com.meta.wearable.dat.core.types.RegistrationState.Registering -> 2
            is com.meta.wearable.dat.core.types.RegistrationState.Registered -> 3
            is com.meta.wearable.dat.core.types.RegistrationState.Unregistering -> 2
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
