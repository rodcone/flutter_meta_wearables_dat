package io.rodcone.flutter_meta_wearables_dat

import android.util.Log
import com.meta.wearable.dat.core.Wearables
import com.meta.wearable.dat.core.selectors.DeviceSelector
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Stream handler for active device availability updates from the DAT SDK.
 * Emits `true` when an active device is available, `false` otherwise.
 */
internal class ActiveDeviceStreamHandler(
        private val deviceSelectorProvider: () -> DeviceSelector,
        private val isInitialized: () -> Boolean,
        private val ensureInitialized: () -> Unit,
) : EventChannel.StreamHandler {

    private companion object {
        private const val TAG = "MetaWearablesDat"
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var job: Job? = null
    private var rawDevicesJob: Job? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        if (events == null) return
        eventSink = events
        val initialized = isInitialized()
        Log.d(TAG, "ActiveDeviceStream onListen — initialized=$initialized")
        // Only start collecting if SDK is already initialized.
        // If not yet initialized, restartMonitoring() will be called later
        // after BT permissions are granted.
        if (initialized) {
            startCollecting(events)
        }
    }

    override fun onCancel(arguments: Any?) {
        Log.d(TAG, "ActiveDeviceStream onCancel")
        job?.cancel()
        job = null
        eventSink = null
    }

    /**
     * Start device monitoring if not already collecting. Idempotent: safe to call from multiple
     * paths (BT permission grant, registration completion, Dart-triggered restart) without
     * double-subscribing. Matches the official CameraAccess sample's one-shot `startMonitoring()`
     * pattern.
     */
    fun restartMonitoring(force: Boolean = false) {
        val sink = eventSink
        if (sink == null) {
            Log.d(TAG, "ActiveDeviceStream restartMonitoring — no sink yet, skipping")
            return
        }
        // `force` rebinds to a freshly-swapped selector even while a job is live
        // (e.g. after a device-pin change). startCollecting() cancels the old job
        // and re-reads the selector provider.
        if (!force && job?.isActive == true) {
            Log.d(TAG, "ActiveDeviceStream restartMonitoring — already collecting, skipping")
            return
        }
        Log.d(TAG, "ActiveDeviceStream restartMonitoring — starting collection (force=$force)")
        startCollecting(sink)
    }

    private fun startCollecting(events: EventChannel.EventSink) {
        ensureInitialized()

        job?.cancel()
        rawDevicesJob?.cancel()
        val selector = deviceSelectorProvider()
        // Seed the subscriber with the current active-device state. `activeDeviceFlow()`
        // does not guarantee replaying the latest value to new collectors, so a device
        // that was already active before Dart subscribed would otherwise leave the UI
        // stuck on "waiting for an active device".
        val initial = selector.activeDevice()
        val rawDevices = Wearables.devices.value
        Log.d(
                TAG,
                "ActiveDeviceStream startCollecting — seed activeDevice=$initial (hasActive=${initial != null}), Wearables.devices=$rawDevices",
        )
        events.success(initial != null)
        job =
                scope.launch {
                    selector.activeDeviceFlow().collect { device ->
                        Log.d(TAG, "ActiveDeviceStream flow emit — device=$device (hasActive=${device != null})")
                        events.success(device != null)
                    }
                }
        // Observe the raw DAT SDK device set separately so we can tell whether
        // the SDK sees the glasses at all (vs. the selector filtering them out).
        rawDevicesJob =
                scope.launch {
                    Wearables.devices.collect { ids ->
                        Log.d(TAG, "Wearables.devices emit — ids=$ids")
                    }
                }
    }

    fun dispose() {
        job?.cancel()
        job = null
        rawDevicesJob?.cancel()
        rawDevicesJob = null
        eventSink = null
        scope.cancel()
    }
}
