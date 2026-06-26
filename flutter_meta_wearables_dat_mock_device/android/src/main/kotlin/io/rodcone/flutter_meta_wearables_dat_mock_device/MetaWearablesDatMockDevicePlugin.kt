package io.rodcone.flutter_meta_wearables_dat_mock_device

import android.app.Activity
import android.app.Application
import android.content.pm.PackageManager
import android.util.Log
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import com.meta.wearable.dat.mockdevice.MockDeviceKit
import com.meta.wearable.dat.mockdevice.api.GlassesModel
import com.meta.wearable.dat.mockdevice.api.MockGlasses
import com.meta.wearable.dat.mockdevice.api.camera.CameraFacing
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry

/**
 * Optional MockDeviceKit add-on for `flutter_meta_wearables_dat`.
 *
 * Hosts a dedicated `flutter_meta_wearables_dat_mock_device` method channel so
 * the core plugin has zero awareness of MockDeviceKit and production builds
 * that don't depend on this package never link `mwdat-mockdevice`.
 *
 * Stream-session teardown coordination: when this plugin disables the kit or
 * unpairs a device, the core plugin's `startDeviceAvailabilityMonitoring`
 * observes the resulting `activeDeviceFlow` change and tears its `Session`
 * down asynchronously — no direct cross-plugin call is needed.
 *
 * Frame-rotation coordination: file-fed mock videos arrive without their
 * container rotation honored, so this plugin reads the rotation via
 * `MediaMetadataRetriever` and forwards it to the core plugin's
 * `FrameProcessor` through the internal `_setVideoFeedRotation` method on the
 * core's existing channel. That's the only coupling between the two plugins.
 */
class MetaWearablesDatMockDevicePlugin :
        FlutterPlugin,
        MethodCallHandler,
        ActivityAware,
        PluginRegistry.RequestPermissionsResultListener {

    private companion object {
        private const val TAG = "MWDATMockDevice"
        private const val MOCK_CAMERA_PERMISSION_REQUEST_CODE = 48293
        private const val CORE_CHANNEL = "flutter_meta_wearables_dat"
    }

    private lateinit var channel: MethodChannel
    // Channel pointed at the core plugin's existing handler — used solely to
    // call `_setVideoFeedRotation` so the core's FrameProcessor can rotate
    // file-fed frames before they hit the texture.
    private lateinit var coreChannel: MethodChannel

    private var application: Application? = null
    private var activity: Activity? = null
    private var activityBinding: ActivityPluginBinding? = null

    private var mockKitEnabled = false

    // Pending state for the Android runtime CAMERA permission request.
    private var pendingCameraFacingCall: MethodCall? = null
    private var pendingCameraFacingResult: Result? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        val messenger: BinaryMessenger = binding.binaryMessenger
        channel = MethodChannel(messenger, "flutter_meta_wearables_dat_mock_device")
        channel.setMethodCallHandler(this)
        coreChannel = MethodChannel(messenger, CORE_CHANNEL)
        application = binding.applicationContext as? Application
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        // Best-effort: leave MockDeviceKit disabled on engine detach so a hot
        // restart doesn't carry over a paired mock device.
        try {
            if (mockKitEnabled) {
                application?.let { MockDeviceKit.getInstance(it).disable() }
                mockKitEnabled = false
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to disable MockDeviceKit on detach", e)
        }
        application = null
    }

    // region ActivityAware

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        activityBinding = binding
        binding.addRequestPermissionsResultListener(this)
    }

    override fun onDetachedFromActivity() {
        activityBinding?.removeRequestPermissionsResultListener(this)
        activityBinding = null
        activity = null
    }

    // endregion

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "configure" -> configure(call, result)
            "disable" -> disable(result)
            "pairGlasses" -> pairGlasses(call, result)
            "unpairGlasses" -> unpairGlasses(call, result)
            "powerOn", "powerOff", "don", "doff" -> mockDeviceAction(call, result)
            "setCameraFeed" -> setCameraFeed(call, result)
            "setCameraFacing" -> setCameraFacing(call, result)
            "setCapturedImage" -> setCapturedImage(call, result)
            // The Android SDK has no programmatic permission-injection hook
            // analogous to MockDeviceKit's iOS `permissions` API. The Dart
            // facade still exposes these for parity with iOS — we just
            // no-op here so the call doesn't throw.
            "setPermission", "setPermissionRequestResult" -> result.success(true)
            else -> result.notImplemented()
        }
    }

    // region MockDeviceKit lifecycle

    private fun ensureMockKitEnabled() {
        if (mockKitEnabled) return
        val app = application ?: return
        MockDeviceKit.getInstance(app).enable()
        mockKitEnabled = true
    }

    private fun configure(call: MethodCall, result: Result) {
        val app = application
        if (app == null) {
            result.error("MOCK_DEVICE_ERROR", "Application context is not available.", null)
            return
        }
        val initiallyRegistered = call.argument<Boolean>("initiallyRegistered") ?: true
        val initialPermissionsGranted =
                call.argument<Boolean>("initialPermissionsGranted") ?: true
        if (!initiallyRegistered || !initialPermissionsGranted) {
            Log.w(
                    TAG,
                    "configure: initiallyRegistered/initialPermissionsGranted overrides are " +
                            "not yet supported on Android; enabling MockDeviceKit with default settings.",
            )
        }
        try {
            val kit = MockDeviceKit.getInstance(app)
            // Re-enable to apply the new config (disable is a no-op when off).
            // The core plugin's activeDeviceFlow observer will tear down any
            // running stream session when the underlying mock device disappears.
            if (mockKitEnabled) {
                kit.disable()
                mockKitEnabled = false
            }
            kit.enable()
            mockKitEnabled = true
            result.success(true)
        } catch (e: Exception) {
            result.error("MOCK_DEVICE_ERROR", e.message ?: "Failed to configure mock devices", null)
        }
    }

    private fun disable(result: Result) {
        val app = application
        if (app == null) {
            result.error("MOCK_DEVICE_ERROR", "Application context is not available.", null)
            return
        }
        try {
            if (mockKitEnabled) {
                MockDeviceKit.getInstance(app).disable()
                mockKitEnabled = false
            }
            result.success(true)
        } catch (e: Exception) {
            result.error("MOCK_DEVICE_ERROR", e.message ?: "Failed to disable mock devices", null)
        }
    }

    /** Maps the Dart `GlassesModel.value` token to the SDK's `GlassesModel`. */
    private fun parseGlassesModel(raw: String?): GlassesModel? =
            when (raw) {
                "rayBanMeta" -> GlassesModel.RAYBAN_META
                "oakleyMetaHSTN" -> GlassesModel.OAKLEY_META_HSTN
                "oakleyMetaVanguard" -> GlassesModel.OAKLEY_META_VANGUARD
                "rayBanMetaOptics" -> GlassesModel.RAYBAN_META_OPTICS
                "metaGlasses" -> GlassesModel.META_GLASSES
                else -> null
            }

    private fun pairGlasses(call: MethodCall, result: Result) {
        val app = application
        if (app == null) {
            result.error("MOCK_DEVICE_ERROR", "Application context is not available.", null)
            return
        }
        // Default to Ray-Ban Meta to match the Dart facade's default.
        val model = parseGlassesModel(call.argument<String>("model") ?: "rayBanMeta")
        if (model == null) {
            result.error(
                    "INVALID_ARGS",
                    "Unknown glasses model: ${call.argument<String>("model")}",
                    null,
            )
            return
        }
        try {
            ensureMockKitEnabled()
            MockDeviceKit.getInstance(app)
                    .pairGlasses(model)
                    .onSuccess { glasses ->
                        result.success(glasses.deviceIdentifier.toString())
                    }
                    .onFailure { error, _ ->
                        result.error("MOCK_DEVICE_ERROR", error.description, null)
                    }
        } catch (e: Exception) {
            result.error("MOCK_DEVICE_ERROR", e.message ?: "Failed to pair mock device", null)
        }
    }

    private fun unpairGlasses(call: MethodCall, result: Result) {
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
                    "powerOn" -> device.powerOn()
                    "powerOff" -> device.powerOff()
                    "don" -> device.don()
                    "doff" -> device.doff()
                }
                result.success(true)
            } else {
                result.error("DEVICE_NOT_FOUND", "No mock device found with uuid $deviceId", null)
            }
        } catch (e: Exception) {
            result.error("MOCK_DEVICE_ERROR", e.message ?: "Failed to perform action", null)
        }
    }

    // endregion

    // region Mock camera feed

    private fun setCameraFeed(call: MethodCall, result: Result) {
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
            if (device is MockGlasses) {
                if (videoPath != null) {
                    val uri = android.net.Uri.parse(videoPath)
                    // MockDeviceKit extracts raw NAL units from the file without
                    // honoring the container's rotation metadata, so phone-recorded
                    // portrait videos arrive as native-landscape frames. Forward the
                    // rotation to the core plugin so its FrameProcessor can rotate
                    // before drawing to the Flutter texture.
                    val rotation = readVideoRotationDegrees(app, uri)
                    coreChannel.invokeMethod(
                            "_setVideoFeedRotation",
                            mapOf("degrees" to rotation),
                    )
                    device.services.camera.setCameraFeed(uri)
                }
                result.success(true)
            } else {
                result.error("INVALID_DEVICE", "Device is not a mock glasses device", null)
            }
        } catch (e: Exception) {
            result.error("MOCK_DEVICE_ERROR", e.message ?: "Failed to set camera feed", null)
        }
    }

    private fun readVideoRotationDegrees(
            context: android.content.Context,
            uri: android.net.Uri,
    ): Int {
        val retriever = android.media.MediaMetadataRetriever()
        return try {
            retriever.setDataSource(context, uri)
            retriever
                    .extractMetadata(
                            android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION,
                    )
                    ?.toIntOrNull()
                    ?: 0
        } catch (e: Exception) {
            Log.w(TAG, "Failed to read video rotation metadata for $uri", e)
            0
        } finally {
            try {
                retriever.release()
            } catch (_: Exception) {}
        }
    }

    private fun setCameraFacing(call: MethodCall, result: Result) {
        val app = application
        if (app == null) {
            result.error("MOCK_DEVICE_ERROR", "Application context is not available.", null)
            return
        }
        val deviceId = call.argument<String>("deviceUUID")
        val facingRaw = call.argument<String>("cameraFacing")
        if (deviceId == null) {
            result.error("INVALID_ARGS", "deviceUUID is missing", null)
            return
        }
        if (facingRaw?.lowercase() !in setOf("front", "back")) {
            result.error("INVALID_ARGS", "cameraFacing must be 'front' or 'back'", null)
            return
        }

        // MockDeviceKit reads from the phone's physical camera to simulate the
        // wearable feed, so the Android runtime CAMERA permission must be granted.
        if (ContextCompat.checkSelfPermission(app, android.Manifest.permission.CAMERA) !=
                        PackageManager.PERMISSION_GRANTED
        ) {
            val act = activity
            if (act == null) {
                result.error(
                        "PERMISSION_ERROR",
                        "Activity is not available to request CAMERA permission.",
                        null,
                )
                return
            }
            if (pendingCameraFacingResult != null) {
                result.error(
                        "PERMISSION_ERROR",
                        "A CAMERA permission request is already in progress.",
                        null,
                )
                return
            }
            pendingCameraFacingCall = call
            pendingCameraFacingResult = result
            ActivityCompat.requestPermissions(
                    act,
                    arrayOf(android.Manifest.permission.CAMERA),
                    MOCK_CAMERA_PERMISSION_REQUEST_CODE,
            )
            return
        }

        applyCameraFacing(call, result)
    }

    private fun applyCameraFacing(call: MethodCall, result: Result) {
        val app = application
        if (app == null) {
            result.error("MOCK_DEVICE_ERROR", "Application context is not available.", null)
            return
        }
        val deviceId = call.argument<String>("deviceUUID")
        val facingRaw = call.argument<String>("cameraFacing")
        if (deviceId == null) {
            result.error("INVALID_ARGS", "deviceUUID is missing", null)
            return
        }
        val facing =
                when (facingRaw?.lowercase()) {
                    "front" -> CameraFacing.FRONT
                    "back" -> CameraFacing.BACK
                    else -> {
                        result.error(
                                "INVALID_ARGS",
                                "cameraFacing must be 'front' or 'back'",
                                null,
                        )
                        return
                    }
                }
        try {
            val kit = MockDeviceKit.getInstance(app)
            val device = kit.pairedDevices.find { it.deviceIdentifier.toString() == deviceId }
            if (device is MockGlasses) {
                // Physical camera frames are already oriented correctly by the
                // SDK's internal CameraFrameRotator — clear any rotation left
                // over from a previous video-feed session.
                coreChannel.invokeMethod(
                        "_setVideoFeedRotation",
                        mapOf("degrees" to 0),
                )
                device.services.camera.setCameraFeed(facing)
                result.success(true)
            } else {
                result.error("INVALID_DEVICE", "Device is not a mock glasses device", null)
            }
        } catch (e: Exception) {
            result.error("MOCK_DEVICE_ERROR", e.message ?: "Failed to set camera facing", null)
        }
    }

    private fun setCapturedImage(call: MethodCall, result: Result) {
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
            if (device is MockGlasses) {
                if (imagePath != null) {
                    device.services.camera.setCapturedImage(android.net.Uri.parse(imagePath))
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

    // region RequestPermissionsResultListener

    override fun onRequestPermissionsResult(
            requestCode: Int,
            permissions: Array<out String>,
            grantResults: IntArray,
    ): Boolean {
        if (requestCode != MOCK_CAMERA_PERMISSION_REQUEST_CODE) return false
        val pendingCall = pendingCameraFacingCall
        val pendingResult = pendingCameraFacingResult
        pendingCameraFacingCall = null
        pendingCameraFacingResult = null
        if (pendingCall == null || pendingResult == null) return false
        val granted =
                grantResults.isNotEmpty() &&
                        grantResults.all { it == PackageManager.PERMISSION_GRANTED }
        if (!granted) {
            pendingResult.error(
                    "PERMISSION_DENIED",
                    "CAMERA permission is required for mock device camera feed.",
                    null,
            )
            return true
        }
        applyCameraFacing(pendingCall, pendingResult)
        return true
    }

    // endregion
}
