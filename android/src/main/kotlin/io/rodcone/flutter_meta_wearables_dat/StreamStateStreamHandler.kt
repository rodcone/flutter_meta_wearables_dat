package io.rodcone.flutter_meta_wearables_dat

import com.meta.wearable.dat.camera.Stream
import com.meta.wearable.dat.camera.types.StreamState
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Stream handler for stream session state updates from the DAT SDK.
 * Emits integer values matching the Dart `StreamState` enum.
 *
 * Set the [stream] property when a stream is added to a session.
 * Clear it when the stream is torn down.
 */
internal class StreamStateStreamHandler : EventChannel.StreamHandler {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var job: Job? = null
    private var eventSink: EventChannel.EventSink? = null

    /** The active stream to observe. Setting this resubscribes to the state flow. */
    var stream: Stream? = null
        set(value) {
            field = value
            resubscribe()
        }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        if (events == null) return
        eventSink = events
        resubscribe()
    }

    override fun onCancel(arguments: Any?) {
        job?.cancel()
        job = null
        eventSink = null
    }

    private fun resubscribe() {
        job?.cancel()
        job = null
        val sink = eventSink ?: return
        val currentStream = stream ?: return

        job =
                scope.launch {
                    currentStream.state.collect { state -> sink.success(mapState(state)) }
                }
    }

    fun dispose() {
        job?.cancel()
        job = null
        eventSink = null
        scope.cancel()
    }

    companion object {
        /**
         * Maps Android SDK StreamState to int values expected by Dart.
         *
         * Android enum: STARTING, STARTED, STREAMING, STOPPING, STOPPED, CLOSED
         * Dart enum:    stopping(0), stopped(1), waitingForDevice(2), starting(3), streaming(4), paused(5)
         *
         * Mapping notes:
         * - STARTED has no direct Dart equivalent; mapped to starting(3) since it precedes streaming.
         * - CLOSED has no direct Dart equivalent; mapped to stopped(1).
         * - Android has no WAITING_FOR_DEVICE or PAUSED states.
         */
        fun mapState(state: StreamState): Int {
            return when (state) {
                StreamState.STOPPING -> 0
                StreamState.STOPPED -> 1
                StreamState.STARTING -> 3
                StreamState.STARTED -> 3
                StreamState.STREAMING -> 4
                StreamState.CLOSED -> 1
            }
        }
    }
}
