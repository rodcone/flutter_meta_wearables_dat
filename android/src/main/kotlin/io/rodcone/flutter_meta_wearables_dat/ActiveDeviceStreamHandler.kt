package io.rodcone.flutter_meta_wearables_dat

import com.meta.wearable.dat.core.Wearables
import com.meta.wearable.dat.core.selectors.DeviceSelector
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

/**
 * Stream handler for active device availability updates from the DAT SDK.
 * Emits `true` when an active device is available, `false` otherwise.
 */
internal class ActiveDeviceStreamHandler(
        private val deviceSelector: DeviceSelector,
        private val isInitialized: () -> Boolean,
        private val ensureInitialized: () -> Unit,
) : EventChannel.StreamHandler {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var job: Job? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        if (events == null) return
        eventSink = events
        // Only start collecting if SDK is already initialized.
        // If not yet initialized, restartMonitoring() will be called later
        // after BT permissions are granted.
        if (isInitialized()) {
            startCollecting(events)
        }
    }

    override fun onCancel(arguments: Any?) {
        job?.cancel()
        job = null
        eventSink = null
    }

    /**
     * Restart device monitoring by cancelling the current collection and re-subscribing to the
     * active device flow. Called after BT permissions are granted or after registration
     * completes so the flow picks up newly available devices.
     */
    fun restartMonitoring() {
        val sink = eventSink ?: return
        job?.cancel()
        job = null
        // Brief delay to let the SDK finish discovering devices after
        // initialization or registration before we re-subscribe.
        scope.launch {
            delay(500)
            startCollecting(sink)
        }
    }

    private fun startCollecting(events: EventChannel.EventSink) {
        ensureInitialized()

        job?.cancel()
        job =
                scope.launch {
                    deviceSelector.activeDevice(Wearables.devices).collect { device ->
                        events.success(device != null)
                    }
                }
    }

    fun dispose() {
        job?.cancel()
        job = null
        eventSink = null
        scope.cancel()
    }
}
