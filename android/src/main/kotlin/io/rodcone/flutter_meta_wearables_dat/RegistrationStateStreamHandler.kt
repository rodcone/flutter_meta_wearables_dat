package io.rodcone.flutter_meta_wearables_dat

import android.util.Log
import com.meta.wearable.dat.core.Wearables
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

/**
 * Stream handler for registration state updates from the DAT SDK.
 * Emits integer values matching the Dart `RegistrationState` enum.
 */
internal class RegistrationStateStreamHandler(
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
     * Start collecting registration state events if not already collecting. Idempotent: safe to
     * call from multiple paths (permission-just-granted, permissions-already-granted, etc.)
     * without double-subscribing.
     */
    fun restartMonitoring() {
        val sink = eventSink ?: return
        if (job?.isActive == true) return
        startCollecting(sink)
    }

    private fun startCollecting(events: EventChannel.EventSink) {
        ensureInitialized()

        job?.cancel()
        job =
                scope.launch {
                    // Send initial state
                    val initialState = Wearables.registrationState.first()
                    Log.d("MetaWearablesDat", "RegistrationState initial=$initialState")
                    events.success(mapState(initialState))
                    // Listen to state changes
                    Wearables.registrationState.collect { state ->
                        Log.d("MetaWearablesDat", "RegistrationState emit=$state")
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
