package io.rodcone.flutter_meta_wearables_dat

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import io.flutter.plugin.common.EventChannel
import kotlin.math.floor

/**
 * Event-channel handler that forwards each decoded stream frame to Dart.
 * Serialization is skipped entirely when `hasListener` is false so there is
 * no per-frame cost for apps that don't opt in to the video_frames stream.
 */
internal class VideoFrameStreamHandler : EventChannel.StreamHandler {

    private data class DeliveryReservation(val generation: Long)

    private val lock = Any()
    private var sink: EventChannel.EventSink? = null
    private var generation = 0L
    private var pendingDeliveries = 0
    private var droppedFrames = 0
    private var samplingIntervalSeconds: Double? = null
    private var nextSampleDeadlineSeconds: Double? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    val hasListener: Boolean
        get() = synchronized(lock) { sink != null }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        val maxFramesPerSecond =
                (arguments as? Map<*, *>)?.get("maxFramesPerSecond") as? Number
        val value = maxFramesPerSecond?.toDouble()
        if (value != null && (!value.isFinite() || value <= 0.0 || value > 30.0)) {
            events?.error(
                    "INVALID_ARGUMENT",
                    "maxFramesPerSecond must be finite, greater than 0, and no greater than 30.",
                    value,
            )
            return
        }
        synchronized(lock) {
            generation += 1
            sink = events
            droppedFrames = 0
            samplingIntervalSeconds = value?.let { 1.0 / it }
            nextSampleDeadlineSeconds = null
        }
    }

    override fun onCancel(arguments: Any?) {
        synchronized(lock) {
            generation += 1
            sink = null
            samplingIntervalSeconds = null
            nextSampleDeadlineSeconds = null
        }
    }

    fun dispose() {
        synchronized(lock) {
            generation += 1
            sink = null
            samplingIntervalSeconds = null
            nextSampleDeadlineSeconds = null
        }
    }

    /** Make the first frame of a replacement stream immediately eligible. */
    fun resetSessionState() {
        synchronized(lock) { nextSampleDeadlineSeconds = null }
    }

    /**
     * Emit a raw frame payload. Safe to call from any thread — the emission
     * is forwarded to the main Looper which is what Flutter's event-channel
     * contract requires.
     */
    fun emit(
        codec: String,
        width: Int,
        height: Int,
        ptsUs: Long,
        isKeyframe: Boolean,
        bytesProvider: () -> ByteArray?,
    ) {
        val reservation = reserveDelivery() ?: return
        val bytes =
                try {
                    bytesProvider()
                } catch (error: Throwable) {
                    abandonDelivery()
                    throw error
                }
        if (bytes == null) {
            abandonDelivery()
            return
        }
        val payload: Map<String, Any> = mapOf(
            "codec" to codec,
            "bytes" to bytes,
            "width" to width,
            "height" to height,
            "ptsUs" to ptsUs,
            "isKeyframe" to isKeyframe,
        )
        mainHandler.post {
            // Re-check inside the main-thread block — the subscriber may have
            // cancelled and a new one may have attached since this frame was
            // prepared. A generation match prevents leaking an old frame into
            // that new subscription.
            val currentSink =
                    synchronized(lock) {
                        pendingDeliveries = (pendingDeliveries - 1).coerceAtLeast(0)
                        if (generation == reservation.generation) sink else null
                    }
            currentSink?.success(payload)
        }
    }

    /** Reserve delivery before the expensive I420 byte copy. */
    private fun reserveDelivery(): DeliveryReservation? =
            synchronized(lock) {
                if (sink == null) return@synchronized null

                samplingIntervalSeconds?.let { interval ->
                    val now = SystemClock.elapsedRealtimeNanos() / 1_000_000_000.0
                    val deadline = nextSampleDeadlineSeconds
                    if (deadline != null && now < deadline) {
                        return@synchronized null
                    }
                    nextSampleDeadlineSeconds =
                            if (deadline == null) {
                                now + interval
                            } else {
                                val elapsedIntervals = floor((now - deadline) / interval) + 1.0
                                deadline + elapsedIntervals * interval
                            }
                }

                if (pendingDeliveries >= MAX_PENDING_DELIVERIES) {
                    droppedFrames += 1
                    if (droppedFrames % 30 == 1) {
                        Log.w(
                                TAG,
                                "Platform thread behind; dropped $droppedFrames video frame(s)",
                        )
                    }
                    return@synchronized null
                }
                pendingDeliveries += 1
                DeliveryReservation(generation)
            }

    private fun abandonDelivery() {
        synchronized(lock) {
            pendingDeliveries = (pendingDeliveries - 1).coerceAtLeast(0)
        }
    }

    private companion object {
        private const val TAG = "MWDATVideoFrames"
        private const val MAX_PENDING_DELIVERIES = 8
    }
}
