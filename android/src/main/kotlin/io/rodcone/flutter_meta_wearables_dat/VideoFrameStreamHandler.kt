package io.rodcone.flutter_meta_wearables_dat

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * Event-channel handler that forwards each decoded stream frame to Dart.
 * Serialization is skipped entirely when `hasListener` is false so there is
 * no per-frame cost for apps that don't opt in to the video_frames stream.
 */
internal class VideoFrameStreamHandler : EventChannel.StreamHandler {

    @Volatile private var sink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    val hasListener: Boolean
        get() = sink != null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    fun dispose() {
        sink = null
    }

    /**
     * Emit a raw frame payload. Safe to call from any thread — the emission
     * is forwarded to the main Looper which is what Flutter's event-channel
     * contract requires.
     */
    fun emit(
        codec: String,
        bytes: ByteArray,
        width: Int,
        height: Int,
        ptsUs: Long,
        isKeyframe: Boolean,
    ) {
        val currentSink = sink ?: return
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
            // cancelled between the sink capture and the dispatch.
            sink?.success(payload)
        }
    }
}
