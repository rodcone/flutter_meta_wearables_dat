package io.rodcone.flutter_meta_wearables_dat

import android.app.Activity
import android.app.Application
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.Canvas
import android.util.Log
import android.view.Surface
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.meta.wearable.dat.camera.StreamSession
import com.meta.wearable.dat.camera.startStreamSession
import com.meta.wearable.dat.camera.types.PhotoData
import com.meta.wearable.dat.camera.types.StreamConfiguration
import com.meta.wearable.dat.camera.types.VideoFrame
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
import java.nio.ByteBuffer
import kotlin.coroutines.resume
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
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
    private var application: Application? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null
    private var activeDeviceStreamHandler: ActiveDeviceStreamHandler? = null
    private var registrationStateStreamHandler: RegistrationStateStreamHandler? = null
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
    private val streamSessions = mutableMapOf<String, StreamSession>()
    private val targetFPS = mutableMapOf<String, Double>()
    private val lastFrameSendTime = mutableMapOf<String, Long>()
    private val frameCounters = mutableMapOf<String, Int>()
    private val videoJobs = mutableMapOf<String, Job>()
    private val stateJobs = mutableMapOf<String, Job>()
    // Texture API — renders I420 frames to a SurfaceTexture
    // instead of encoding to JPEG and copying bytes across the platform channel.
    private var textureRegistry: TextureRegistry? = null
    private val textureEntries = mutableMapOf<String, TextureRegistry.SurfaceTextureEntry>()
    private val textureSurfaces = mutableMapOf<String, Surface>()
    // Reusable bitmap per session to avoid per-frame allocation
    private val reusableBitmaps = mutableMapOf<String, Bitmap>()

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

        // Clean up all stream sessions
        videoJobs.values.forEach { it.cancel() }
        videoJobs.clear()
        stateJobs.values.forEach { it.cancel() }
        stateJobs.clear()
        streamSessions.values.forEach { it.close() }
        streamSessions.clear()
        targetFPS.clear()
        frameCounters.clear()
        lastFrameSendTime.clear()

        // Clean up texture resources
        textureSurfaces.values.forEach { it.release() }
        textureSurfaces.clear()
        textureEntries.values.forEach { it.release() }
        textureEntries.clear()
        reusableBitmaps.values.forEach { it.recycle() }
        reusableBitmaps.clear()
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
        val deviceUUID = args?.get("deviceUUID") as? String
        val sessionKey = deviceUUID ?: "auto"

        if (streamSessions.containsKey(sessionKey)) {
            val existingEntry = textureEntries[sessionKey]
            if (existingEntry != null) {
                result.success(existingEntry.id())
            } else {
                result.error("TEXTURE_REGISTRATION_FAILED", "No texture registered for session $sessionKey", null)
            }
            return
        }

        scope.launch {
            try {
                ensureWearablesInitialized()

                targetFPS[sessionKey] = fps
                frameCounters[sessionKey] = 0
                lastFrameSendTime.remove(sessionKey)

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
                textureEntries[sessionKey] = entry
                textureSurfaces[sessionKey] = surface
                val textureId = entry.id()
                Log.d(TAG, "Registered texture $textureId for session $sessionKey")

                val streamSession =
                        Wearables.startStreamSession(
                                app,
                                deviceSelector,
                                StreamConfiguration(videoQuality = streamQuality, fps.toInt())
                        )
                streamSessions[sessionKey] = streamSession

                // Subscribe to video frames — render I420 → ARGB bitmap → SurfaceTexture
                videoJobs[sessionKey] = scope.launch(Dispatchers.Default) {
                    streamSession.videoStream.collect { videoFrame ->
                        // Update SurfaceTexture buffer size if frame dimensions change
                        val texEntry = textureEntries[sessionKey]
                        if (texEntry != null) {
                            val bmp = reusableBitmaps[sessionKey]
                            if (bmp == null || bmp.width != videoFrame.width || bmp.height != videoFrame.height) {
                                texEntry.surfaceTexture().setDefaultBufferSize(videoFrame.width, videoFrame.height)
                            }
                        }
                        processAndSendFrame(videoFrame, sessionKey)
                    }
                }

                stateJobs[sessionKey] =
                        scope.launch {
                            streamSession.state.collect { state ->
                                Log.d(TAG, "StreamSession [$sessionKey] state: $state")
                            }
                        }

                result.success(textureId)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start stream session", e)
                cleanupSession(sessionKey)
                result.error("STREAM_ERROR", e.message ?: "Failed to start stream session.", null)
            }
        }
    }

    private fun stopStreamSession(call: MethodCall, result: Result) {
        val args = call.arguments as? Map<*, *>
        val deviceUUID = args?.get("deviceUUID") as? String
        val sessionKey = deviceUUID ?: "auto"

        val streamSession = streamSessions[sessionKey]
        if (streamSession == null) {
            result.error("SESSION_NOT_FOUND", "No stream session found for '$sessionKey'.", null)
            return
        }

        videoJobs[sessionKey]?.cancel()
        stateJobs[sessionKey]?.cancel()
        streamSession.close()
        cleanupSession(sessionKey)

        result.success(true)
    }


    private fun capturePhoto(call: MethodCall, result: Result) {
        val args = call.arguments as? Map<*, *>
        val deviceUUID = args?.get("deviceUUID") as? String
        val sessionKey = deviceUUID ?: "auto"

        val streamSession = streamSessions[sessionKey]
        if (streamSession == null) {
            result.error("SESSION_NOT_FOUND", "No stream session found for '$sessionKey'.", null)
            return
        }

        scope.launch {
            try {
                val photoResult = streamSession.capturePhoto()
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
                        .onFailure { error ->
                            Log.e(TAG, "Photo capture failed", error)
                            result.error(
                                    "CAPTURE_PHOTO_FAILED",
                                    error.message ?: "Photo capture failed.",
                                    null
                            )
                        }
            } catch (e: Exception) {
                Log.e(TAG, "Photo capture exception", e)
                result.error("CAPTURE_PHOTO_FAILED", e.message ?: "Photo capture failed.", null)
            }
        }
    }

    /**
     * Convert I420 → ARGB bitmap → draw onto SurfaceTexture (zero-copy path).
     * Called on Dispatchers.Default.
     */
    private fun processAndSendFrame(videoFrame: VideoFrame, sessionKey: String) {
        // FPS throttling
        val fps = targetFPS[sessionKey] ?: 30.0
        val minIntervalNanos = (1_000_000_000.0 / fps).toLong()
        val now = System.nanoTime()
        val lastTime = lastFrameSendTime[sessionKey]
        if (lastTime != null && (now - lastTime) < minIntervalNanos) {
            return
        }

        val surface = textureSurfaces[sessionKey] ?: return
        if (!surface.isValid) return

        val width = videoFrame.width
        val height = videoFrame.height

        // Reuse bitmap to avoid per-frame allocation
        var bitmap = reusableBitmaps[sessionKey]
        if (bitmap == null || bitmap.width != width || bitmap.height != height) {
            bitmap?.recycle()
            bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            reusableBitmaps[sessionKey] = bitmap
        }

        // Convert I420 → ARGB directly into the bitmap's pixel buffer
        convertI420toArgbBitmap(videoFrame.buffer, width, height, bitmap)

        // Draw bitmap onto the SurfaceTexture — this pushes a frame to Flutter
        try {
            val canvas: Canvas = surface.lockCanvas(null) ?: return
            try {
                canvas.drawBitmap(bitmap, 0f, 0f, null)
            } finally {
                surface.unlockCanvasAndPost(canvas)
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to render frame to texture surface", e)
            return
        }

        lastFrameSendTime[sessionKey] = now
        val count = (frameCounters[sessionKey] ?: 0) + 1
        frameCounters[sessionKey] = count
        if (count % 30 == 0 && lastTime != null) {
            val actualFPS = 1_000_000_000.0 / (now - lastTime)
            Log.d(
                    TAG,
                    "Texture path — $count frames for $sessionKey, " +
                            "target: $fps, actual: ${"%.1f".format(actualFPS)} FPS"
            )
        }
    }

    /**
     * Convert I420 (planar YUV) directly to an ARGB_8888 Bitmap — no JPEG intermediate step.
     * Uses the BT.601 full-range conversion matrix. Writes directly into [bitmap]'s pixels.
     */
    private fun convertI420toArgbBitmap(buffer: ByteBuffer, width: Int, height: Int, bitmap: Bitmap) {
        val dataSize = buffer.remaining()
        val byteArray = ByteArray(dataSize)
        val originalPosition = buffer.position()
        buffer.get(byteArray)
        buffer.position(originalPosition)

        val ySize = width * height
        val uvQuarter = ySize / 4
        val pixels = IntArray(ySize)

        for (j in 0 until height) {
            for (i in 0 until width) {
                val yIndex = j * width + i
                val uvIndex = (j / 2) * (width / 2) + (i / 2)

                val y = (byteArray[yIndex].toInt() and 0xFF)
                val u = (byteArray[ySize + uvIndex].toInt() and 0xFF) - 128
                val v = (byteArray[ySize + uvQuarter + uvIndex].toInt() and 0xFF) - 128

                var r = y + (1.370705f * v).toInt()
                var g = y - (0.337633f * u).toInt() - (0.698001f * v).toInt()
                var b = y + (1.732446f * u).toInt()

                r = r.coerceIn(0, 255)
                g = g.coerceIn(0, 255)
                b = b.coerceIn(0, 255)

                pixels[yIndex] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
            }
        }

        bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
    }

    private fun cleanupSession(sessionKey: String) {
        videoJobs.remove(sessionKey)
        stateJobs.remove(sessionKey)
        streamSessions.remove(sessionKey)
        targetFPS.remove(sessionKey)
        frameCounters.remove(sessionKey)
        lastFrameSendTime.remove(sessionKey)
        // Release texture resources
        textureSurfaces.remove(sessionKey)?.release()
        val entry = textureEntries.remove(sessionKey)
        if (entry != null) {
            Log.d(TAG, "Unregistered texture ${entry.id()} for session $sessionKey")
            entry.release()
        }
        reusableBitmaps.remove(sessionKey)?.recycle()
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

    // region Stream Handlers

    private class ActiveDeviceStreamHandler(
            private val deviceSelector: DeviceSelector,
            private val isInitialized: () -> Boolean,
            private val ensureInitialized: () -> Unit,
    ) : EventChannel.StreamHandler {
        private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        private var job: Job? = null
        private var eventSink: EventChannel.EventSink? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            if (events == null) return
            eventSink = events
            // Only start collecting if SDK is already initialized.
            // If not yet initialized, restartMonitoring() will be called later
            // after BT permissions are granted.
            if (isInitialized()) {
                startCollecting(events)
            }
        }

        override fun onCancel(arguments: Any?) {
            job?.cancel()
            job = null
            eventSink = null
        }

        /**
         * Restart device monitoring by cancelling the current collection and re-subscribing to the
         * active device flow. Called after BT permissions are granted or after registration
         * completes so the flow picks up newly available devices.
         */
        fun restartMonitoring() {
            val sink = eventSink ?: return
            job?.cancel()
            job = null
            // Brief delay to let the SDK finish discovering devices after
            // initialization or registration before we re-subscribe.
            scope.launch {
                delay(500)
                startCollecting(sink)
            }
        }

        private fun startCollecting(events: EventChannel.EventSink) {
            ensureInitialized()

            job?.cancel()
            job =
                    scope.launch {
                        deviceSelector.activeDevice(Wearables.devices).collect { device ->
                            events.success(device != null)
                        }
                    }
        }

        fun dispose() {
            job?.cancel()
            job = null
            eventSink = null
            scope.cancel()
        }
    }

    private class RegistrationStateStreamHandler(
            private val isInitialized: () -> Boolean,
            private val ensureInitialized: () -> Unit,
            private val mapState: (com.meta.wearable.dat.core.types.RegistrationState) -> Int
    ) : EventChannel.StreamHandler {
        private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
        private var job: Job? = null
        private var eventSink: EventChannel.EventSink? = null

        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            if (events == null) return
            eventSink = events
            if (isInitialized()) {
                startCollecting(events)
            }
        }

        /**
         * Start or restart collecting registration state events. Called when SDK becomes
         * initialized.
         */
        fun restartMonitoring() {
            val sink = eventSink ?: return
            startCollecting(sink)
        }

        private fun startCollecting(events: EventChannel.EventSink) {
            ensureInitialized()

            job?.cancel()
            job =
                    scope.launch {
                        // Send initial state
                        val initialState = Wearables.registrationState.first()
                        events.success(mapState(initialState))
                        // Listen to state changes
                        Wearables.registrationState.collect { state ->
                            events.success(mapState(state))
                        }
                    }
        }

        override fun onCancel(arguments: Any?) {
            job?.cancel()
            job = null
            eventSink = null
        }

        fun dispose() {
            job?.cancel()
            job = null
            scope.cancel()
        }
    }

    // endregion
}
