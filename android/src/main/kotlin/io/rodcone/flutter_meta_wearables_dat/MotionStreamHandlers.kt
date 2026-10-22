package io.rodcone.flutter_meta_wearables_dat

import com.meta.wearable.dat.motion.types.MotionError
import com.meta.wearable.dat.motion.types.MotionSample
import com.meta.wearable.dat.motion.types.MotionSamplingRate
import com.meta.wearable.dat.motion.types.MotionSource
import com.meta.wearable.dat.motion.types.MotionState
import com.meta.wearable.dat.motion.types.Vector3
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

internal fun motionSamplingRate(hertz: Int): MotionSamplingRate? = when (hertz) {
    5 -> MotionSamplingRate.HZ_5
    10 -> MotionSamplingRate.HZ_10
    15 -> MotionSamplingRate.HZ_15
    24 -> MotionSamplingRate.HZ_24
    30 -> MotionSamplingRate.HZ_30
    60 -> MotionSamplingRate.HZ_60
    else -> null
}

internal fun motionStateName(state: MotionState): String = when (state) {
    MotionState.STOPPED -> "stopped"
    MotionState.STARTING -> "starting"
    MotionState.STARTED -> "started"
    MotionState.STOPPING -> "stopping"
    MotionState.PAUSED -> "paused"
    else -> "unknown"
}

internal fun motionErrorCode(error: MotionError): String = when (error) {
    MotionError.SENSOR_UNAVAILABLE -> "sensorUnavailable"
    MotionError.CAPABILITY_CLOSED -> "capabilityClosed"
    MotionError.DEVICE_DISCONNECTED -> "deviceDisconnected"
    else -> "unexpectedError"
}

private fun Vector3.toMotionMap(): Map<String, Double> =
        mapOf("x" to x.toDouble(), "y" to y.toDouble(), "z" to z.toDouble())

internal fun MotionSample.toMotionMap(): Map<String, Any?> = mapOf(
        "timestampNs" to timestampNs,
        "source" to when (source) {
            MotionSource.GLASSES -> "glasses"
            MotionSource.NEURAL_BAND -> "neuralBand"
            else -> "unknown"
        },
        "accelerometer" to accelerometer?.toMotionMap(),
        "gyroscope" to gyroscope?.toMotionMap(),
        "magnetometer" to magnetometer?.toMotionMap(),
        "orientation" to orientation?.let {
            mapOf("x" to it.x.toDouble(), "y" to it.y.toDouble(),
                    "z" to it.z.toDouble(), "w" to it.w.toDouble())
        },
)

/** Low-rate state/error events; all calls originate on the platform thread. */
internal class MotionEventStreamHandler(private val initialState: String? = null) : EventChannel.StreamHandler {
    private var sink: EventChannel.EventSink? = null
    private var latestState: Any? = initialState

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        if (initialState != null) events?.success(latestState)
    }

    override fun onCancel(arguments: Any?) { sink = null }

    fun send(event: Any) {
        if (initialState != null) latestState = event
        sink?.success(event)
    }

    fun sendError(code: String, message: String) = send(mapOf("code" to code, "message" to message))

    fun dispose() {
        sink = null
        latestState = initialState
    }
}

/**
 * One sequential SDK collector awaits each platform delivery. There is no posted
 * per-sample queue. Session/subscription tokens discard work queued before stop,
 * cancel, relisten, or replacement; no samples are replayed to new listeners.
 */
internal class MotionSamplesStreamHandler(
        private val platformDispatcher: CoroutineDispatcher = Dispatchers.Main.immediate,
) : EventChannel.StreamHandler {
    private val lock = Any()
    private var sink: EventChannel.EventSink? = null
    private var subscription = 0L
    private var session = 0L
    private var active = false

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        synchronized(lock) { subscription++; sink = events }
    }

    override fun onCancel(arguments: Any?) {
        synchronized(lock) { subscription++; sink = null }
    }

    fun beginSession(): Long = synchronized(lock) { active = true; ++session }

    fun endSession() { synchronized(lock) { active = false; session++ } }

    fun dispose() { endSession(); onCancel(null) }

    suspend fun emit(sessionId: Long, sample: MotionSample, canDeliver: () -> Boolean = { true }) {
        val listener = synchronized(lock) {
            if (!active || sessionId != session || sink == null) return
            subscription
        }
        val payload = sample.toMotionMap()
        withContext(platformDispatcher) {
            val current = synchronized(lock) {
                if (active && sessionId == session && listener == subscription) sink else null
            }
            if (canDeliver()) current?.success(payload)
        }
    }
}
