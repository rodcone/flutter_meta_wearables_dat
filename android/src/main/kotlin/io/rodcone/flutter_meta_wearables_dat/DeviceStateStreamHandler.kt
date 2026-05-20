package io.rodcone.flutter_meta_wearables_dat

import android.util.Log
import com.meta.wearable.dat.core.Wearables
import com.meta.wearable.dat.core.selectors.DeviceSelector
import com.meta.wearable.dat.core.types.DeviceState
import com.meta.wearable.dat.core.types.ThermalLevel
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch

/**
 * Stream handler for per-device state updates (currently: thermal level).
 *
 * 0.7.0 added `Wearables.getDeviceState(deviceIdentifier): StateFlow<DeviceState>`
 * keyed by `DeviceIdentifier`. The plugin's Dart-facing API exposes a single
 * `deviceStateStream()` that tracks the *active* device, so this handler
 * wraps the per-device flow in an outer subscription to
 * `deviceSelector.activeDeviceFlow()` and switches its inner subscription
 * whenever the active device changes.
 *
 * Mirrors the iOS `DeviceStateStreamHandler.swift` design exactly so the
 * Dart-side `Stream<DeviceState>` API behaves identically on both platforms.
 */
internal class DeviceStateStreamHandler(
        private val deviceSelectorProvider: () -> DeviceSelector,
        private val isInitialized: () -> Boolean,
) : EventChannel.StreamHandler {

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var outerJob: Job? = null
    private var innerJob: Job? = null
    private var eventSink: EventChannel.EventSink? = null

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        if (events == null) return
        eventSink = events
        if (!isInitialized()) {
            // SDK not yet initialized — bail. The plugin can call
            // [restartMonitoring] once Bluetooth permissions are granted and
            // `Wearables.initialize` has run.
            Log.d(TAG, "DeviceStateStream onListen — SDK not initialized yet")
            return
        }
        startCollecting(events)
    }

    override fun onCancel(arguments: Any?) {
        outerJob?.cancel()
        outerJob = null
        innerJob?.cancel()
        innerJob = null
        eventSink = null
    }

    /**
     * Restart the active-device subscription. Called after BT permissions are
     * granted so we don't miss the first device emission.
     */
    fun restartMonitoring() {
        val sink = eventSink ?: return
        if (outerJob?.isActive == true) return
        if (!isInitialized()) return
        startCollecting(sink)
    }

    private fun startCollecting(events: EventChannel.EventSink) {
        outerJob?.cancel()
        innerJob?.cancel()
        innerJob = null
        val selector = deviceSelectorProvider()
        var currentDeviceId: com.meta.wearable.dat.core.types.DeviceIdentifier? = null

        // Seed: if a device is already active, attach the inner subscription
        // immediately so Dart subscribers see the first thermal reading
        // without waiting for an `activeDeviceFlow` tick.
        selector.activeDevice()?.let { deviceId ->
            currentDeviceId = deviceId
            innerJob = subscribe(deviceId, events)
        }

        outerJob =
                scope.launch {
                    selector.activeDeviceFlow().collect { deviceId ->
                        // `activeDeviceFlow()` replays the current value to
                        // new collectors. The SDK's
                        // `Wearables.getDeviceState(...)` doesn't tolerate
                        // rapid cancel+resubscribe for the same device, so
                        // only tear down + restart when the device actually
                        // changes (mirrors the iOS handler's behaviour).
                        if (deviceId == currentDeviceId) return@collect
                        innerJob?.cancel()
                        innerJob = null
                        currentDeviceId = deviceId
                        if (deviceId != null) {
                            innerJob = subscribe(deviceId, events)
                        }
                    }
                }
    }

    private fun subscribe(
            deviceId: com.meta.wearable.dat.core.types.DeviceIdentifier,
            events: EventChannel.EventSink,
    ): Job {
        return scope.launch {
            Wearables.getDeviceState(deviceId).collect { state ->
                events.success(mapOf("thermalLevel" to thermalLevelToInt(state.thermalLevel)))
            }
        }
    }

    fun dispose() {
        outerJob?.cancel()
        outerJob = null
        innerJob?.cancel()
        innerJob = null
        eventSink = null
        scope.cancel()
    }

    companion object {
        private const val TAG = "MetaWearablesDat"

        /**
         * Mirrors the int values the Dart `ThermalLevel` enum uses
         * (also the same as the iOS handler emits). Keep these aligned.
         */
        private fun thermalLevelToInt(level: ThermalLevel): Int {
            return when (level) {
                ThermalLevel.UNKNOWN -> 0
                ThermalLevel.NONE -> 1
                ThermalLevel.LIGHT -> 2
                ThermalLevel.MODERATE -> 3
                ThermalLevel.SEVERE -> 4
                ThermalLevel.CRITICAL -> 5
                ThermalLevel.EMERGENCY -> 6
                ThermalLevel.SHUTDOWN -> 7
            }
        }
    }
}
