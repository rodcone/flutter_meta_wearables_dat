package io.rodcone.flutter_meta_wearables_dat

import com.meta.wearable.dat.camera.StreamSession
import io.flutter.plugin.common.EventChannel

/**
 * Stream handler for stream session errors.
 *
 * The Android DAT SDK does not have an error publisher on [StreamSession]
 * (unlike iOS's `errorPublisher`). This handler acts as a programmable sink —
 * call [sendError] to emit errors from the plugin (e.g., capture failures).
 *
 * Set the [session] property for API consistency with iOS.
 */
internal class StreamSessionErrorStreamHandler : EventChannel.StreamHandler {

    private var eventSink: EventChannel.EventSink? = null

    /** The active stream session. Stored for API consistency but does not trigger collection. */
    @Suppress("unused")
    var session: StreamSession? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    /**
     * Emit an error event to the Dart side.
     * The map format matches what the Dart layer expects:
     * `{"code": "...", "message": "..."}`.
     */
    fun sendError(code: String, message: String) {
        eventSink?.success(mapOf("code" to code, "message" to message))
    }

    fun dispose() {
        eventSink = null
    }
}
