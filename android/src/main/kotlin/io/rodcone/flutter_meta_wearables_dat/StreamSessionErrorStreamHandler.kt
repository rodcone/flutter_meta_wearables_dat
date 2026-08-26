package io.rodcone.flutter_meta_wearables_dat

import android.util.Log
import com.meta.wearable.dat.camera.types.StreamError
import com.meta.wearable.dat.core.types.DeviceSessionError
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * Stream handler for stream-related errors. Acts as a programmable sink that
 * the plugin pushes into — errors come from three layers in 0.7.0:
 *
 * 1. `Stream.errorStream: Flow<StreamError>` — collected in [MetaWearablesDatPlugin]
 *    and mapped via [send] (`StreamError` overload).
 * 2. `DeviceSession.errors: SharedFlow<DeviceSessionError>` — collected in
 *    [MetaWearablesDatPlugin] and mapped via [send] (`DeviceSessionError` overload).
 * 3. Pre-stream failures (`Wearables.createSession` / `DeviceSession.addCamera`
 *    `onFailure`) forwarded via [sendError].
 *
 * All three funnel through a single Flutter event channel so Dart consumers
 * see one unified error stream. Code strings match the iOS plugin's mapping
 * exactly so cross-platform consumers can switch on a single set of codes.
 */
internal class StreamSessionErrorStreamHandler : EventChannel.StreamHandler {

    private var eventSink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    /** True while the plugin is deliberately stopping for a background transition. */
    private var isStoppingForBackground = false
    private var suppressionExpiry: Job? = null

    /**
     * Suppresses teardown noise for the duration of a deliberate background
     * stop.
     *
     * The SDK emits `videoStreamingError` as the pipeline comes down. That is
     * accurate when the stream died on its own and actively false when *we*
     * stopped it — the app implicitly asked for the stop by backgrounding — so
     * consumers were rendering a red "streaming encountered an error" banner
     * for a clean, expected shutdown.
     *
     * Bounded on purpose: a stalled teardown must not be able to hide unrelated
     * later errors indefinitely, so the window closes on a timer even if
     * [endBackgroundStopSuppression] never arrives. Mirrors iOS.
     *
     * `stoppedForBackground` is emitted *before* this opens, so the app still
     * learns why the session ended.
     */
    fun beginBackgroundStopSuppression(
            scope: CoroutineScope,
            timeoutMs: Long = DEFAULT_SUPPRESSION_TIMEOUT_MS,
    ) {
        isStoppingForBackground = true
        suppressionExpiry?.cancel()
        suppressionExpiry =
                scope.launch {
                    delay(timeoutMs)
                    isStoppingForBackground = false
                    suppressionExpiry = null
                }
    }

    fun endBackgroundStopSuppression() {
        suppressionExpiry?.cancel()
        suppressionExpiry = null
        isStoppingForBackground = false
    }

    /**
     * Emit an error event to the Dart side.
     * Map format: `{"code": "...", "message": "..."}`.
     *
     * [bypassSuppression] is for the plugin's own deliberate-stop notice, which
     * must reach Dart even though it opens the suppression window immediately
     * afterwards.
     */
    fun sendError(code: String, message: String, bypassSuppression: Boolean = false) {
        if (!bypassSuppression && isStoppingForBackground) {
            Log.d(TAG, "suppressed '$code' during background stop")
            return
        }
        eventSink?.success(mapOf("code" to code, "message" to message))
    }

    /**
     * Map a [StreamError] from the SDK onto the Flutter channel using the
     * same code strings used by the iOS plugin so Dart consumers see parity
     * across platforms.
     */
    fun send(streamError: StreamError) {
        val (code, message) = mapStreamError(streamError)
        sendError(code, message)
    }

    /**
     * Map a [DeviceSessionError] (session-scoped error from
     * `DeviceSession.errors`) onto the Flutter channel. These are the new
     * 0.7.0 cases — `DAT_APP_ON_THE_GLASSES_UPDATE_REQUIRED` is the trigger
     * for apps to call `MetaWearablesDat.openDATGlassesAppUpdate()`.
     */
    fun send(deviceSessionError: DeviceSessionError) {
        val (code, message) = mapDeviceSessionError(deviceSessionError)
        sendError(code, message)
    }

    fun dispose() {
        eventSink = null
    }

    companion object {
        private const val TAG = "MetaWearablesDat"

        /**
         * Upper bound on the background-stop suppression window. Matches iOS,
         * whose bound tracks its teardown worst case (3s stream + 10s session
         * backstops, plus slack). On Android teardown is synchronous and the
         * window is closed explicitly right after it, so this timer is a pure
         * backstop that should never fire.
         */
        const val DEFAULT_SUPPRESSION_TIMEOUT_MS = 15_000L

        // String-pattern matching against `error.toString()` keeps us
        // forward-compatible: new error cases that aren't explicitly listed
        // here still get a reasonable fallback code rather than crashing.

        private fun mapStreamError(error: StreamError): Pair<String, String> {
            val identifier = error.toString().uppercase()
            val description = error.description.ifBlank { identifier }
            // Order matters — check the more specific tokens first.
            val code =
                    when {
                        identifier.contains("HINGE") -> "hingesClosed"
                        identifier.contains("DISCONNECT") -> "deviceNotConnected"
                        identifier.contains("PERMISSION") -> "permissionDenied"
                        // 0.7.0 split THERMAL into HOT (still recoverable) and
                        // EMERGENCY (terminal). HOT maps to the same code iOS
                        // emits for `.thermalCritical` so cross-platform
                        // consumers see one code per severity tier.
                        //
                        // 0.9.0 removed `StreamError.THERMAL_EMERGENCY`, so a
                        // thermal emergency now reaches Dart on Android only as
                        // the session-level `deviceThermalEmergency`. The bare
                        // EMERGENCY guard is kept so a future rename still lands
                        // somewhere sane rather than in `videoStreamingError`.
                        identifier.contains("EMERGENCY") -> "thermalEmergency"
                        identifier.contains("THERMAL") || identifier.contains("OVERHEAT") ->
                                "thermalCritical"
                        identifier.contains("BATTERY") -> "batteryCritical"
                        identifier.contains("PEAK_POWER") || identifier.contains("PEAK POWER") ->
                                "peakPowerShutdown"
                        identifier.contains("CRITICAL") -> "internalError"
                        identifier.contains("TIMEOUT") -> "timeout"
                        else -> "videoStreamingError"
                    }
            return code to description
        }

        private fun mapDeviceSessionError(
                error: DeviceSessionError
        ): Pair<String, String> {
            val identifier = error.toString().uppercase()
            val description = error.description.ifBlank { identifier }
            val code =
                    when {
                        identifier.contains("DAT_APP") || identifier.contains("DATAPP") ->
                                "datAppOnTheGlassesUpdateRequired"
                        identifier.contains("DWA") -> "dwaUnavailable"
                        identifier.contains("THERMAL_EMERGENCY") ->
                                "deviceThermalEmergency"
                        identifier.contains("THERMAL") -> "deviceThermalCritical"
                        identifier.contains("BATTERY") -> "deviceBatteryCritical"
                        identifier.contains("PEAK_POWER") -> "devicePeakPowerShutdown"
                        identifier.contains("NO_ELIGIBLE") ||
                                identifier.contains("NO ELIGIBLE") -> "noEligibleDevice"
                        identifier.contains("ALREADY_STOPPED") -> "sessionAlreadyStopped"
                        identifier.contains("ALREADY_EXISTS") -> "sessionAlreadyExists"
                        identifier.contains("IDLE") -> "sessionIdle"
                        identifier.contains("CAPABILITY_ALREADY") -> "capabilityAlreadyActive"
                        identifier.contains("CAPABILITY_NOT") -> "capabilityNotFound"
                        identifier.contains("CAPABILITY_DENIED") -> "capabilityDenied"
                        // These three used to collapse into `unexpectedError`.
                        // Android-only: iOS's `DeviceSessionError` is @frozen
                        // with no equivalent cases.
                        identifier.contains("SESSION_ENDED") -> "sessionEndedByDevice"
                        identifier.contains("DISCONNECT") -> "deviceNotConnected"
                        else -> "unexpectedError"
                    }
            return code to description
        }
    }
}
