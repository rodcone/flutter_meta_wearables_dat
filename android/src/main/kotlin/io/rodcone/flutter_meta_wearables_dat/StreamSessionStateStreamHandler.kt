package io.rodcone.flutter_meta_wearables_dat

import com.meta.wearable.dat.camera.StreamSession
import com.meta.wearable.dat.camera.types.StreamSessionState
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

/**
 * Stream handler for stream session state updates from the DAT SDK.
 * Emits integer values matching the Dart `StreamSessionState` enum.
 *
 * Set the [session] property when a stream session is created.
 * Clear it when the session is torn down.
 */
internal class StreamSessionStateStreamHandler : EventChannel.StreamHandler {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var job: Job? = null
    private var eventSink: EventChannel.EventSink? = null

    /** The active stream session to observe. Setting this resubscribes to the state flow. */
    var session: StreamSession? = null
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
        val currentSession = session ?: return

        job =
                scope.launch {
                    currentSession.state.collect { state -> sink.success(mapState(state)) }
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
         * Maps Android SDK StreamSessionState to int values expected by Dart.
         *
         * Android enum: STARTING, STARTED, STREAMING, STOPPING, STOPPED, CLOSED
         * Dart enum:    stopping(0), stopped(1), waitingForDevice(2), starting(3), streaming(4), paused(5)
         *
         * Mapping notes:
         * - STARTED has no direct Dart equivalent; mapped to starting(3) since it precedes streaming.
         * - CLOSED has no direct Dart equivalent; mapped to stopped(1).
         * - Android has no WAITING_FOR_DEVICE or PAUSED states.
         */
        fun mapState(state: StreamSessionState): Int {
            return when (state) {
                StreamSessionState.STOPPING -> 0
                StreamSessionState.STOPPED -> 1
                StreamSessionState.STARTING -> 3
                StreamSessionState.STARTED -> 3  // No Dart equivalent; treat as "starting"
                StreamSessionState.STREAMING -> 4
                StreamSessionState.CLOSED -> 1   // No Dart equivalent; treat as "stopped"
            }
        }
    }
}
