package io.rodcone.flutter_meta_wearables_dat

import android.app.Application
import com.meta.wearable.dat.camera.Stream
import com.meta.wearable.dat.core.selectors.DeviceSelector
import com.meta.wearable.dat.core.session.DeviceSession
import com.meta.wearable.dat.core.session.DeviceSessionState
import com.meta.wearable.dat.core.types.DatResult
import com.meta.wearable.dat.core.types.DeviceIdentifier
import com.meta.wearable.dat.core.types.DeviceSessionError
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import kotlin.test.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.*
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.mockito.Mockito.*

/** Exercises the real method-channel lifecycle with controllable SDK state flows. */
@OptIn(ExperimentalCoroutinesApi::class)
class DeviceSessionLifecycleTest {
    private val plugins = mutableListOf<MetaWearablesDatPlugin>()

    @BeforeEach
    fun setUp() {
        Dispatchers.setMain(StandardTestDispatcher())
    }

    @AfterEach
    fun tearDown() {
        plugins.forEach { (field(it, "scope") as CoroutineScope).cancel() }
        Dispatchers.resetMain()
    }

    private fun field(plugin: MetaWearablesDatPlugin, name: String): Any? =
            plugin.javaClass.getDeclaredField(name).apply { isAccessible = true }.get(plugin)

    private fun setField(plugin: MetaWearablesDatPlugin, name: String, value: Any?) {
        plugin.javaClass.getDeclaredField(name).apply { isAccessible = true }.set(plugin, value)
    }

    private class Session(
            startsImmediately: Boolean = true,
            stopsImmediately: Boolean = true,
    ) {
        val state = MutableStateFlow(DeviceSessionState.IDLE)
        val sdk = mock(DeviceSession::class.java).also {
            `when`(it.state).thenReturn(state)
            `when`(it.errors).thenReturn(MutableSharedFlow<DeviceSessionError>())
            doAnswer {
                state.value = if (startsImmediately) DeviceSessionState.STARTED else DeviceSessionState.STARTING
                null
            }.`when`(it).start()
            doAnswer {
                state.value = if (stopsImmediately) DeviceSessionState.STOPPED else DeviceSessionState.STOPPING
                null
            }.`when`(it).stop()
        }
    }

    private fun plugin(
            create: () -> DatResult<DeviceSession, DeviceSessionError>,
    ): MetaWearablesDatPlugin {
        val plugin = MetaWearablesDatPlugin(initializeSdk = {}, createDeviceSession = { create() })
        plugins.add(plugin)
        setField(plugin, "application", mock(Application::class.java))
        setField(plugin, "btPermissionsGranted", true)
        setField(plugin, "deviceSelectorRef", object : DeviceSelector {
            override fun activeDevice() = DeviceIdentifier("test-glasses")
            override fun activeDeviceFlow() = flowOf(activeDevice())
        })
        return plugin
    }

    private fun call(plugin: MetaWearablesDatPlugin, method: String): MethodChannel.Result =
            mock(MethodChannel.Result::class.java).also {
                plugin.onMethodCall(MethodCall(method, null), it)
            }

    private fun events(plugin: MetaWearablesDatPlugin): MutableList<String> {
        val events = mutableListOf<String>()
        (field(plugin, "deviceSessionStateHandler") as DeviceSessionStateStreamHandler).onListen(
                null,
                object : EventChannel.EventSink {
                    override fun success(value: Any?) { events.add(value as String) }
                    override fun error(code: String, message: String?, details: Any?) {
                        fail("Unexpected event error: $code")
                    }
                    override fun endOfStream() {}
                },
        )
        return events
    }

    @Test
    fun `timed out start stops its session and releases observers before retry`() = runTest {
        val first = Session(startsImmediately = false)
        val second = Session()
        var creations = 0
        val plugin = plugin { DatResult.success(if (creations++ == 0) first.sdk else second.sdk) }
        val states = events(plugin)
        val result = call(plugin, "startDeviceSession")
        runCurrent()
        advanceTimeBy(20_000)
        runCurrent()

        verify(first.sdk).stop()
        verify(result).error(eq("DEVICE_SESSION_ERROR"), anyString(), isNull())
        assertNull(field(plugin, "session"))
        assertNull(field(plugin, "sessionStateJob"))
        assertNull(field(plugin, "sessionErrorsJob"))
        assertEquals(false, field(plugin, "startInProgress"))
        assertEquals(listOf("stopped", "starting", "stopping", "stopped"), states)

        val retry = call(plugin, "startDeviceSession")
        runCurrent()
        verify(retry).success(true)
        assertEquals(2, creations)
        assertSame(second.sdk, field(plugin, "session"))
        first.state.value = DeviceSessionState.STARTED
        runCurrent()
        assertEquals(1, states.count { it == "started" }, "old callbacks must not reach the new session")
    }

    @Test
    fun `legacy connection timeout keeps STREAM_ERROR`() = runTest {
        val session = Session(startsImmediately = false)
        val plugin = plugin { DatResult.success(session.sdk) }
        val result = call(plugin, "startStreamSession")
        advanceUntilIdle()

        verify(result).error(eq("STREAM_ERROR"), anyString(), isNull())
        verify(result, never()).success(any())
        verify(session.sdk).stop()
        assertNull(field(plugin, "session"))
    }

    @Test
    fun `session creation failure preserves error code for each entry point`() = runTest {
        for ((method, code) in listOf(
                "startStreamSession" to "STREAM_ERROR",
                "startDeviceSession" to "DEVICE_SESSION_ERROR",
        )) {
            val plugin = plugin { DatResult.failure(DeviceSessionError.NO_ELIGIBLE_DEVICE) }
            val result = call(plugin, method)
            runCurrent()
            verify(result).error(eq(code), anyString(), isNull())
            verify(result, never()).success(any())
            assertNull(field(plugin, "session"))
        }
    }

    @Test
    fun `external stop emits one terminal event after releasing the stream`() = runTest {
        val session = Session()
        val plugin = plugin { DatResult.success(session.sdk) }
        val states = events(plugin)
        call(plugin, "startDeviceSession")
        runCurrent()
        states.clear()
        val stream = mock(Stream::class.java)
        val texture = mock(TextureRegistry.SurfaceTextureEntry::class.java)
        setField(plugin, "stream", stream)
        setField(plugin, "textureEntry", texture)

        session.state.value = DeviceSessionState.STOPPED
        runCurrent()

        assertEquals(listOf("stopped"), states)
        verify(session.sdk, never()).stop()
        verify(stream).stop()
        verify(texture).release()
        assertNull(field(plugin, "session"))
        assertNull(field(plugin, "textureEntry"))
        assertNull(field(plugin, "sessionStateJob"))
    }

    @Test
    fun `stop timeout retains ownership and waits for confirmation before retry`() = runTest {
        val first = Session(stopsImmediately = false)
        val second = Session()
        var creations = 0
        val plugin = plugin { DatResult.success(if (creations++ == 0) first.sdk else second.sdk) }
        val states = events(plugin)
        call(plugin, "startDeviceSession")
        runCurrent()
        states.clear()
        val stop = call(plugin, "stopDeviceSession")
        runCurrent()
        assertEquals(listOf("stopping"), states)
        advanceTimeBy(10_000)
        runCurrent()

        verify(stop).error(eq("STOP_TIMEOUT"), anyString(), isNull())
        assertSame(first.sdk, field(plugin, "session"))
        assertNotNull(field(plugin, "sessionStateJob"))
        assertEquals(listOf("stopping"), events(plugin), "late listeners must not see a false stopped")

        // A delayed STARTED must not let the connection-only fast path reuse a
        // session for which stop was already requested.
        first.state.value = DeviceSessionState.STARTED
        val retry = call(plugin, "startDeviceSession")
        runCurrent()
        verifyNoInteractions(retry)
        assertEquals(1, creations)
        first.state.value = DeviceSessionState.STOPPED
        runCurrent()

        verify(retry).success(true)
        assertEquals(2, creations)
        assertSame(second.sdk, field(plugin, "session"))
    }

    @Test
    fun `timed out start cannot replace an unconfirmed stopping session`() = runTest {
        val session = Session(startsImmediately = false, stopsImmediately = false)
        var creations = 0
        val plugin = plugin { creations++; DatResult.success(session.sdk) }
        val states = events(plugin)
        val start = call(plugin, "startDeviceSession")
        advanceUntilIdle()
        verify(start).error(eq("DEVICE_SESSION_ERROR"), anyString(), isNull())
        verify(session.sdk).stop()
        assertEquals("stopping", states.last())
        assertSame(session.sdk, field(plugin, "session"))

        session.state.value = DeviceSessionState.STARTED
        runCurrent()
        assertEquals("stopping", states.last(), "late STARTED must not revive a timed-out start")
        val retry = call(plugin, "startDeviceSession")
        advanceUntilIdle()
        verify(retry).error(eq("DEVICE_SESSION_ERROR"), anyString(), isNull())
        assertEquals(1, creations)
        assertEquals("stopping", states.last())
        session.state.value = DeviceSessionState.STOPPED
        runCurrent()
        assertNull(field(plugin, "session"))
        assertEquals("stopped", states.last())
    }

    @Test
    fun `external stopping releases the camera and stays stopping until acknowledged`() = runTest {
        val session = Session()
        val plugin = plugin { DatResult.success(session.sdk) }
        val states = events(plugin)
        call(plugin, "startDeviceSession")
        runCurrent()
        states.clear()
        val stream = mock(Stream::class.java)
        setField(plugin, "stream", stream)

        session.state.value = DeviceSessionState.STOPPING
        runCurrent()
        verify(stream).stop()
        verify(session.sdk, never()).stop()
        assertNull(field(plugin, "stream"))
        assertSame(session.sdk, field(plugin, "session"))
        assertEquals(listOf("stopping"), states)

        session.state.value = DeviceSessionState.STOPPED
        runCurrent()
        assertEquals(listOf("stopping", "stopped"), states)
        assertNull(field(plugin, "session"))
    }

    @Test
    fun `SDK acknowledgement during camera cleanup cannot reorder terminal events`() = runTest {
        val session = Session()
        val plugin = plugin { DatResult.success(session.sdk) }
        val states = events(plugin)
        call(plugin, "startDeviceSession")
        runCurrent()
        states.clear()
        val stream = mock(Stream::class.java)
        doAnswer {
            session.state.value = DeviceSessionState.STOPPED
            null
        }.`when`(stream).stop()
        setField(plugin, "stream", stream)

        session.state.value = DeviceSessionState.STOPPING
        runCurrent()

        assertEquals(listOf("stopping", "stopped"), states)
        assertNull(field(plugin, "session"))
        verify(session.sdk, never()).stop()
    }

    @Test
    fun `reentrant SDK stop waits for texture release before terminal notification`() = runTest {
        Dispatchers.setMain(UnconfinedTestDispatcher(testScheduler))
        val session = Session()
        val plugin = plugin { DatResult.success(session.sdk) }
        val states = events(plugin)
        call(plugin, "startDeviceSession")
        val stream = mock(Stream::class.java)
        val texture = mock(TextureRegistry.SurfaceTextureEntry::class.java)
        states.clear()
        doAnswer {
            session.state.value = DeviceSessionState.STOPPED
            null
        }.`when`(stream).stop()
        doAnswer {
            assertFalse("stopped" in states, "terminal state must follow resource cleanup")
            null
        }.`when`(texture).release()
        setField(plugin, "stream", stream)
        setField(plugin, "textureEntry", texture)

        val stop = call(plugin, "stopDeviceSession")
        runCurrent()

        verify(stop).success(true)
        verify(texture).release()
        assertEquals(listOf("stopped"), states)
        assertNull(field(plugin, "session"))
        assertNull(field(plugin, "textureEntry"))
    }

    @Test
    fun `stop during start tears down before completing either command`() = runTest {
        val session = Session(startsImmediately = false)
        val plugin = plugin { DatResult.success(session.sdk) }
        val states = events(plugin)
        val start = call(plugin, "startDeviceSession")
        runCurrent()
        val stop = call(plugin, "stopDeviceSession")
        session.state.value = DeviceSessionState.STARTED
        runCurrent()

        verify(start).error(eq("DEVICE_SESSION_ERROR"), anyString(), isNull())
        verify(stop).success(true)
        verify(session.sdk).stop()
        assertNull(field(plugin, "session"))
        assertEquals(1, states.drop(1).count { it == "stopped" })
    }

    @Test
    fun `SDK start exception also cleans up the owned session`() = runTest {
        val session = Session()
        doThrow(IllegalStateException("SDK start failed")).`when`(session.sdk).start()
        val plugin = plugin { DatResult.success(session.sdk) }
        val result = call(plugin, "startStreamSession")
        runCurrent()

        verify(result).error(eq("STREAM_ERROR"), anyString(), isNull())
        verify(session.sdk).stop()
        assertNull(field(plugin, "session"))
        assertNull(field(plugin, "sessionErrorsJob"))
    }

    @Test
    fun `repeated stop of an idle session does not emit new transitions`() = runTest {
        val plugin = plugin { fail("Idle stop must not create a session") }
        val states = events(plugin)
        val first = call(plugin, "stopDeviceSession")
        val second = call(plugin, "stopDeviceSession")
        runCurrent()

        verify(first).success(true)
        verify(second).success(true)
        assertEquals(listOf("stopped"), states)
    }
}
