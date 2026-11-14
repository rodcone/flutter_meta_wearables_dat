package io.rodcone.flutter_meta_wearables_dat

import com.meta.wearable.dat.core.selectors.DeviceSelector
import com.meta.wearable.dat.core.types.*
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.StandardMethodCodec
import kotlin.test.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.test.*
import org.junit.jupiter.api.Test
import org.mockito.Mockito.*

@OptIn(ExperimentalCoroutinesApi::class)
class DeviceStateStreamHandlerTest {
    private class Sink : EventChannel.EventSink {
        val values = mutableListOf<Map<*, *>>()
        val errors = mutableListOf<String>()
        override fun success(event: Any?) {
            val encoded = StandardMethodCodec.INSTANCE.encodeSuccessEnvelope(event)
            encoded.flip()
            values.add(StandardMethodCodec.INSTANCE.decodeEnvelope(encoded) as Map<*, *>)
        }
        override fun error(code: String, message: String?, details: Any?) { errors.add(code) }
        override fun endOfStream() = Unit
        val last get() = values.last()
    }

    private fun state(
        battery: Int = 72, link: LinkState = LinkState.CONNECTED,
        thermal: ThermalLevel = ThermalLevel.MODERATE,
        charging: ChargingState = ChargingState.NOT_CHARGING,
        don: DonState = DonState.DONNED, hinge: HingeState = HingeState.OPEN,
        compatibility: DeviceCompatibility = DeviceCompatibility.COMPATIBLE,
    ): Device = mock(Device::class.java).apply {
        doReturn(battery).`when`(this).batteryLevel
        doReturn(link).`when`(this).linkState
        doReturn(thermal).`when`(this).thermalLevel
        doReturn(charging).`when`(this).chargingState
        doReturn(don).`when`(this).donState
        doReturn(hinge).`when`(this).hingeState
        doReturn(compatibility).`when`(this).compatibility
    }

    private class Fixture {
        var initialized = true
        var lookups = 0
        val selected = MutableStateFlow<DeviceIdentifier?>(DeviceIdentifier("a"))
        val registrations = MutableStateFlow(RegistrationState.REGISTERED)
        val devices = MutableStateFlow(setOf("a", "b").map(::DeviceIdentifier).toSet())
        val sources = mutableMapOf<String, Flow<Device>>()
        val selector: DeviceSelector = mock(DeviceSelector::class.java).apply {
            doAnswer { selected.value }.`when`(this).activeDevice()
            doReturn(selected).`when`(this).activeDeviceFlow()
        }
        val handler = DeviceStateStreamHandler(
            { selector }, { initialized }, { lookups++; sources[it.identifier] },
            { registrations }, { devices },
        )
        val sink = Sink()
        fun listen() { handler.onListen(null, sink) }
    }

    private fun check(block: suspend TestScope.(Fixture) -> Unit) = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        val f = Fixture()
        try { block(f) } finally { f.handler.dispose(); runCurrent(); Dispatchers.resetMain() }
    }

    @Test fun `initial full snapshot and physical-only updates`() = check { f ->
        val states = MutableStateFlow(state())
        f.sources["a"] = states
        f.listen(); runCurrent()
        assertEquals(mapOf("deviceId" to "a", "linkState" to "connected",
            "compatibility" to "compatible", "thermalLevel" to 3, "batteryLevel" to 72,
            "chargingState" to "notCharging", "donState" to "donned", "hingeState" to "open"), f.sink.last)
        states.value = state(battery = 71, charging = ChargingState.CHARGING, don = DonState.DOFFED, hinge = HingeState.CLOSED)
        runCurrent()
        assertEquals(71, f.sink.last["batteryLevel"])
        assertEquals("charging", f.sink.last["chargingState"])
        assertEquals("doffed", f.sink.last["donState"])
        assertEquals("closed", f.sink.last["hingeState"])
        assertEquals(3, f.sink.last["thermalLevel"])
    }

    @Test fun `battery and enum boundaries use canonical codes`() = check { f ->
        val states = MutableStateFlow(state())
        f.sources["a"] = states; f.listen(); runCurrent()
        for (battery in listOf(-1, 0, 1, 100, 101)) {
            states.value = state(battery = battery); runCurrent()
            assertEquals(battery.takeIf { it in 1..100 }, f.sink.last["batteryLevel"])
        }
        for ((index, thermal) in ThermalLevel.entries.withIndex()) {
            states.value = state(thermal = thermal); runCurrent()
            assertEquals(index, f.sink.last["thermalLevel"])
        }
        states.value = state(charging = ChargingState.UNKNOWN, don = DonState.UNKNOWN, hinge = HingeState.UNKNOWN,
            compatibility = DeviceCompatibility.SDK_UPDATE_REQUIRED)
        runCurrent()
        assertEquals("unknown", f.sink.last["chargingState"])
        assertEquals("unknown", f.sink.last["donState"])
        assertEquals("unknown", f.sink.last["hingeState"])
        assertEquals("sdkUpdateRequired", f.sink.last["compatibility"])
    }

    @Test fun `permission initialization is deferred without losing the listener`() = check { f ->
        f.initialized = false; f.sources["a"] = MutableStateFlow(state())
        f.listen(); runCurrent()
        assertNull(f.sink.last["deviceId"]); assertEquals(0, f.lookups)
        verifyNoInteractions(f.selector)
        f.initialized = true; f.handler.restartMonitoring(); runCurrent()
        assertEquals(72, f.sink.last["batteryLevel"])
    }

    @Test fun `no device and missing metadata clear and later recover`() = check { f ->
        f.selected.value = null; f.listen(); runCurrent()
        assertNull(f.sink.last["deviceId"])
        f.selected.value = DeviceIdentifier("a"); runCurrent()
        assertEquals("a", f.sink.last["deviceId"]); assertNull(f.sink.last["batteryLevel"])
        f.sources["a"] = MutableStateFlow(state())
        f.devices.value = setOf("a", "b", "c").map(::DeviceIdentifier).toSet(); runCurrent()
        assertEquals(72, f.sink.last["batteryLevel"])
        val lookups = f.lookups
        f.devices.value = setOf("a", "b").map(::DeviceIdentifier).toSet(); f.handler.restartMonitoring(); runCurrent()
        assertEquals(lookups, f.lookups, "Same-device replay must not duplicate collectors")
    }

    @Test fun `disconnect clears physical values but preserves connection identity`() = check { f ->
        val states = MutableStateFlow(state()); f.sources["a"] = states
        f.listen(); runCurrent()
        for (link in listOf(LinkState.CONNECTING, LinkState.DISCONNECTED)) {
            states.value = state(link = link); runCurrent()
            assertEquals("a", f.sink.last["deviceId"])
            assertEquals(link.name.lowercase(), f.sink.last["linkState"])
            assertNull(f.sink.last["batteryLevel"]); assertEquals(0, f.sink.last["thermalLevel"])
            assertEquals("unknown", f.sink.last["donState"])
        }
        f.selected.value = null; runCurrent(); assertNull(f.sink.last["deviceId"])
        states.value = state(battery = 44); f.selected.value = DeviceIdentifier("a"); runCurrent()
        assertEquals(44, f.sink.last["batteryLevel"])
    }

    private class LateFlow : Flow<Device> {
        lateinit var collector: FlowCollector<Device>
        override suspend fun collect(collector: FlowCollector<Device>) {
            this.collector = collector
            awaitCancellation()
        }
    }

    @Test fun `late callback cannot cross device or listener generations`() = check { f ->
        val a = LateFlow(); f.sources["a"] = a
        f.sources["b"] = MutableStateFlow(state(battery = 30))
        f.listen(); runCurrent(); a.collector.emit(state())
        f.selected.value = DeviceIdentifier("b"); runCurrent()
        a.collector.emit(state(battery = 99))
        assertEquals("b", f.sink.last["deviceId"]); assertEquals(30, f.sink.last["batteryLevel"])
        f.handler.onCancel(null); val count = f.sink.values.size
        a.collector.emit(state()); runCurrent(); assertEquals(count, f.sink.values.size)
        f.listen(); runCurrent(); a.collector.emit(state())
        assertEquals("b", f.sink.last["deviceId"])
    }

    @Test fun `removed metadata cannot leave a pinned device reading alive`() = check { f ->
        val old = LateFlow(); f.sources["a"] = old; f.listen(); runCurrent()
        old.collector.emit(state())
        f.devices.value = emptySet(); runCurrent()
        old.collector.emit(state()); assertNull(f.sink.last["deviceId"])
        f.sources["a"] = MutableStateFlow(state(battery = 23))
        f.devices.value = setOf(DeviceIdentifier("a")); runCurrent()
        assertEquals(23, f.sink.last["batteryLevel"])
    }

    @Test fun `forced restart rebinds and rejects the old collector`() = check { f ->
        val old = LateFlow(); f.sources["a"] = old; f.listen(); runCurrent()
        f.sources["a"] = MutableStateFlow(state(battery = 21))
        f.handler.restartMonitoring(force = true); runCurrent()
        old.collector.emit(state(battery = 98))
        assertEquals(21, f.sink.last["batteryLevel"])
    }

    @Test fun `unregister cancels observation and registered resumes without session work`() = check { f ->
        val old = LateFlow(); f.sources["a"] = old; f.listen(); runCurrent()
        old.collector.emit(state())
        f.registrations.value = RegistrationState.AVAILABLE; runCurrent()
        old.collector.emit(state()); assertNull(f.sink.last["deviceId"])
        f.sources["a"] = MutableStateFlow(state(battery = 55))
        f.registrations.value = RegistrationState.REGISTERED; runCurrent()
        assertEquals(55, f.sink.last["batteryLevel"])
    }

    @Test fun `dispose rejects pending work and does not resubscribe`() = check { f ->
        val old = LateFlow(); f.sources["a"] = old; f.listen(); runCurrent()
        f.handler.dispose(); val count = f.sink.values.size
        old.collector.emit(state()); f.listen(); f.handler.restartMonitoring(force = true); runCurrent()
        assertEquals(count, f.sink.values.size)
    }

    @Test fun `collector errors clear state and reach the channel`() = check { f ->
        f.sources["a"] = flow { emit(state()); throw IllegalStateException("metadata unavailable") }
        f.listen(); runCurrent()
        assertTrue(f.sink.errors.isNotEmpty())
        assertTrue(f.sink.errors.all { it == "DEVICE_STATE_ERROR" })
        assertNull(f.sink.last["batteryLevel"])
    }
}
