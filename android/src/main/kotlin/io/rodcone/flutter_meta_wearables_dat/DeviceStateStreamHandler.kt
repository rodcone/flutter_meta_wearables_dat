package io.rodcone.flutter_meta_wearables_dat

import com.meta.wearable.dat.core.Wearables
import com.meta.wearable.dat.core.selectors.DeviceSelector
import com.meta.wearable.dat.core.types.*
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*

/** Observes physical and connection metadata without owning a device session. */
internal class DeviceStateStreamHandler(
        private val deviceSelectorProvider: () -> DeviceSelector,
        private val isInitialized: () -> Boolean,
        private val metadata: (DeviceIdentifier) -> Flow<Device>? = { Wearables.devicesMetadata[it] },
        private val registrations: () -> Flow<RegistrationState> = { Wearables.registrationState },
        private val devices: () -> Flow<Set<DeviceIdentifier>> = { Wearables.devices },
) : EventChannel.StreamHandler {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private var outerJob: Job? = null
    private var innerJob: Job? = null
    private var eventSink: EventChannel.EventSink? = null
    private var monitoringGeneration = 0L
    private var deviceGeneration = 0L
    private var disposed = false

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        if (disposed || events == null) return
        eventSink = events
        startCollecting()
    }

    override fun onCancel(arguments: Any?) {
        invalidateMonitoring()
        eventSink = null
    }

    fun restartMonitoring(force: Boolean = false) {
        if (disposed || eventSink == null) return
        if (!force && outerJob?.isActive == true) return
        startCollecting()
    }

    private fun invalidateDevice() {
        deviceGeneration++
        innerJob?.cancel()
        innerJob = null
    }

    private fun invalidateMonitoring() {
        monitoringGeneration++
        invalidateDevice()
        outerJob?.cancel()
        outerJob = null
    }

    private fun startCollecting() {
        invalidateMonitoring()
        val events = eventSink ?: return
        events.success(emptySnapshot())
        if (!isInitialized()) return // Restarted after Bluetooth permission/initialization.
        val generation = monitoringGeneration
        outerJob = scope.launch {
            try {
                registrations().distinctUntilChanged().collectLatest { registration ->
                    if (generation != monitoringGeneration) return@collectLatest
                    invalidateDevice()
                    events.success(emptySnapshot())
                    if (registration != RegistrationState.REGISTERED) return@collectLatest
                    val selector = deviceSelectorProvider()
                    var currentId: DeviceIdentifier? = null
                    try {
                        // Device-list changes retry a missing metadata lookup, without polling.
                        combine(
                            selector.activeDeviceFlow().onStart { emit(selector.activeDevice()) },
                            devices().onStart { emit(emptySet()) },
                        ) { id, known -> id?.takeIf { it in known } }.collect { id ->
                            if (generation != monitoringGeneration) return@collect
                            if (id == currentId && (id == null || innerJob?.isActive == true)) return@collect
                            invalidateDevice()
                            currentId = id
                            events.success(emptySnapshot(id))
                            if (id != null) subscribe(id, generation, events)
                        }
                    } finally {
                        if (generation == monitoringGeneration) {
                            invalidateDevice()
                            events.success(emptySnapshot())
                        }
                    }
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                if (generation == monitoringGeneration) {
                    events.error("DEVICE_STATE_ERROR", error.message, null)
                }
            } finally {
                if (generation == monitoringGeneration) {
                    invalidateDevice()
                    events.success(emptySnapshot())
                }
            }
        }
    }

    private fun subscribe(id: DeviceIdentifier, generation: Long, events: EventChannel.EventSink) {
        val source = metadata(id) ?: return
        val device = deviceGeneration
        innerJob = scope.launch {
            try {
                source.collect { state ->
                    if (generation == monitoringGeneration && device == deviceGeneration) {
                        events.success(snapshot(id, state))
                    }
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (error: Exception) {
                if (generation == monitoringGeneration && device == deviceGeneration) {
                    events.error("DEVICE_STATE_ERROR", error.message, null)
                }
            } finally {
                if (generation == monitoringGeneration && device == deviceGeneration) {
                    events.success(emptySnapshot(id))
                }
            }
        }
    }

    fun dispose() {
        onCancel(null)
        disposed = true
        scope.cancel()
    }

    companion object {
        private fun emptySnapshot(id: DeviceIdentifier? = null): Map<String, Any?> = mapOf(
            "deviceId" to id?.identifier, "linkState" to "unknown", "compatibility" to "undefined",
            "thermalLevel" to 0, "batteryLevel" to null, "chargingState" to "unknown",
            "donState" to "unknown", "hingeState" to "unknown",
        )

        private fun snapshot(id: DeviceIdentifier, state: Device): Map<String, Any?> {
            val connected = state.linkState == LinkState.CONNECTED
            return mapOf(
                "deviceId" to id.identifier,
                "linkState" to when (state.linkState) {
                    LinkState.CONNECTED -> "connected"
                    LinkState.CONNECTING -> "connecting"
                    LinkState.DISCONNECTED -> "disconnected"
                    else -> "unknown"
                },
                "compatibility" to when (state.compatibility) {
                    DeviceCompatibility.COMPATIBLE -> "compatible"
                    DeviceCompatibility.DEVICE_UPDATE_REQUIRED -> "deviceUpdateRequired"
                    DeviceCompatibility.SDK_UPDATE_REQUIRED -> "sdkUpdateRequired"
                    else -> "undefined"
                },
                "thermalLevel" to if (connected) thermalLevelToInt(state.thermalLevel) else 0,
                // DAT uses zero for unknown OR empty; never fabricate an empty battery.
                "batteryLevel" to state.batteryLevel.takeIf { connected && it in 1..100 },
                "chargingState" to if (!connected) "unknown" else when (state.chargingState) {
                    ChargingState.CHARGING -> "charging"
                    ChargingState.NOT_CHARGING -> "notCharging"
                    else -> "unknown"
                },
                "donState" to if (!connected) "unknown" else when (state.donState) {
                    DonState.DONNED -> "donned"
                    DonState.DOFFED -> "doffed"
                    else -> "unknown"
                },
                "hingeState" to if (!connected) "unknown" else when (state.hingeState) {
                    HingeState.OPEN -> "open"
                    HingeState.CLOSED -> "closed"
                    else -> "unknown"
                },
            )
        }

        private fun thermalLevelToInt(level: ThermalLevel): Int = when (level) {
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
