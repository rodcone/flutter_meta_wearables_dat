package io.rodcone.flutter_meta_wearables_dat

import com.meta.wearable.dat.camera.types.StreamError
import io.flutter.plugin.common.EventChannel

/**
 * Stream handler for stream-related errors. Acts as a programmable sink
 * that the plugin pushes into — errors come from two layers:
 *
 * 1. `Stream.errorStream` (collected in [MetaWearablesDatPlugin] and mapped
 *    via [send]).
 * 2. Session-level failures (`Wearables.createSession` / `Session.addStream`
 *    `onFailure`) forwarded via [sendError].
 *
 * Both funnel through a single Flutter event channel so Dart consumers see
 * one unified error stream.
 */
internal class StreamSessionErrorStreamHandler : EventChannel.StreamHandler {

    private var eventSink: EventChannel.EventSink? = null

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

    /**
     * Map a [StreamError] from the SDK onto the Flutter channel using the
     * same code strings used by the iOS plugin so Dart consumers see parity
     * across platforms.
     */
    fun send(streamError: StreamError) {
        val (code, message) = mapStreamError(streamError)
        sendError(code, message)
    }

    fun dispose() {
        eventSink = null
    }

    companion object {
        private fun mapStreamError(error: StreamError): Pair<String, String> {
            val identifier = error.toString().uppercase()
            val description = error.description.ifBlank { identifier }
            val code =
                    when {
                        identifier.contains("HINGE") -> "hingesClosed"
                        identifier.contains("DISCONNECT") -> "deviceNotConnected"
                        identifier.contains("PERMISSION") -> "permissionDenied"
                        identifier.contains("THERMAL") || identifier.contains("OVERHEAT") ->
                                "thermalCritical"
                        identifier.contains("TIMEOUT") -> "timeout"
                        else -> "videoStreamingError"
                    }
            return code to description
        }
    }
}
