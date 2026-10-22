package io.rodcone.flutter_meta_wearables_dat

import android.app.Application
import com.meta.wearable.dat.camera.Stream
import com.meta.wearable.dat.camera.types.StreamState
import com.meta.wearable.dat.core.session.DeviceSessionState
import com.meta.wearable.dat.core.session.DeviceSession
import com.meta.wearable.dat.core.types.DatResult
import com.meta.wearable.dat.core.types.DeviceSessionError
import com.meta.wearable.dat.motion.Motion
import com.meta.wearable.dat.motion.types.MotionState
import com.meta.wearable.dat.motion.types.MotionConfiguration
import com.meta.wearable.dat.motion.types.MotionSamplingRate
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.test.*
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.test.*
import org.junit.jupiter.api.Test
import org.mockito.Mockito.*

@OptIn(ExperimentalCoroutinesApi::class)
class AndroidMotionLifecycleTest {
    private fun field(plugin: MetaWearablesDatPlugin, name: String) =
            plugin.javaClass.getDeclaredField(name).apply { isAccessible = true }

    private fun ready(plugin: MetaWearablesDatPlugin) {
        field(plugin, "application").set(plugin, mock(Application::class.java))
        field(plugin, "btPermissionsGranted").set(plugin, true)
    }

    @Test fun `camera stop preserves Motion and shared device session`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        try {
            val plugin = MetaWearablesDatPlugin()
            val parent = mock(DeviceSession::class.java); val motion = mock(Motion::class.java)
            `when`(motion.state).thenReturn(MutableStateFlow(MotionState.STARTED))
            val camera = mock(Stream::class.java)
            field(plugin, "session").set(plugin, parent); field(plugin, "motion").set(plugin, motion)
            field(plugin, "stream").set(plugin, camera)
            val result = mock(MethodChannel.Result::class.java)
            plugin.onMethodCall(MethodCall("stopStreamSession", null), result); advanceUntilIdle()
            verify(result).success(true); verify(camera).stop(); verify(parent, never()).stop(); verify(motion, never()).stop()
            assertSame(parent, field(plugin, "session").get(plugin))
            assertSame(motion, field(plugin, "motion").get(plugin))
        } finally { Dispatchers.resetMain() }
    }

    @Test fun `Motion stop preserves camera and does not end the parent`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        try {
            val plugin = MetaWearablesDatPlugin(); val motion = mock(Motion::class.java)
            val camera = mock(Stream::class.java)
            field(plugin, "motion").set(plugin, motion); field(plugin, "stream").set(plugin, camera)
            val result = mock(MethodChannel.Result::class.java)
            plugin.onMethodCall(MethodCall("stopMotion", null), result); advanceUntilIdle()
            verify(result).success(true); verify(motion).stop(); verify(camera, never()).stop(); verify(camera, never()).start()
            assertSame(camera, field(plugin, "stream").get(plugin))
            assertNull(field(plugin, "motion").get(plugin))
        } finally { Dispatchers.resetMain() }
    }

    @Test fun `stopping final Motion ends parent and repeated stop is idempotent`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        try {
            val plugin = MetaWearablesDatPlugin(); val parent = mock(DeviceSession::class.java)
            field(plugin, "session").set(plugin, parent)
            val motion = mock(Motion::class.java); field(plugin, "motion").set(plugin, motion)
            val result = mock(MethodChannel.Result::class.java)
            plugin.onMethodCall(MethodCall("stopMotion", null), result)
            plugin.onMethodCall(MethodCall("stopMotion", null), result); advanceUntilIdle()
            verify(result, times(2)).success(true); verify(parent, times(1)).stop()
            assertNull(field(plugin, "session").get(plugin))
        } finally { Dispatchers.resetMain() }
    }

    @Test fun `Motion stop waits for shared capability operation before inspecting references`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        try {
            val plugin = MetaWearablesDatPlugin()
            val mutex = field(plugin, "capabilityMutex").get(plugin) as Mutex
            mutex.lock()
            val result = mock(MethodChannel.Result::class.java)
            plugin.onMethodCall(MethodCall("stopMotion", null), result); runCurrent()
            verifyNoInteractions(result)
            // An in-flight camera start commits while stopMotion is waiting.
            val camera = mock(Stream::class.java); field(plugin, "stream").set(plugin, camera)
            mutex.unlock(); advanceUntilIdle()
            verify(result).success(true); verify(camera, never()).stop(); verify(camera, never()).start()
            assertSame(camera, field(plugin, "stream").get(plugin))
        } finally { Dispatchers.resetMain() }
    }

    @Test fun `different pinned devices are rejected before changing either capability`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        try {
            val plugin = MetaWearablesDatPlugin(); ready(plugin)
            val motion = mock(Motion::class.java); field(plugin, "motion").set(plugin, motion)
            field(plugin, "sessionDeviceId").set(plugin, "glasses-a")
            val result = mock(MethodChannel.Result::class.java)
            plugin.onMethodCall(MethodCall("startStreamSession", mapOf("deviceId" to "glasses-b")), result)
            verify(result).error(eq("MOTION_ACTIVE"), anyString(), isNull()); verifyNoInteractions(motion)
            assertEquals("glasses-a", field(plugin, "sessionDeviceId").get(plugin))
        } finally { Dispatchers.resetMain() }
    }

    @Test fun `Motion reuse is idempotent but rate change requires explicit stop`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        try {
            val plugin = MetaWearablesDatPlugin(); ready(plugin)
            val motion = mock(Motion::class.java)
            `when`(motion.state).thenReturn(MutableStateFlow(MotionState.PAUSED))
            `when`(motion.configuration).thenReturn(MotionConfiguration(MotionSamplingRate.HZ_10))
            field(plugin, "motion").set(plugin, motion)
            val same = mock(MethodChannel.Result::class.java)
            plugin.onMethodCall(MethodCall("startMotion", mapOf("samplingRate" to 10)), same)
            verify(same).success(true)
            val different = mock(MethodChannel.Result::class.java)
            plugin.onMethodCall(MethodCall("startMotion", mapOf("samplingRate" to 60)), different)
            verify(different).error(eq("MOTION_ACTIVE"), anyString(), isNull())
            verify(motion, never()).start(); verify(motion, never()).stop()
        } finally { Dispatchers.resetMain() }
    }

    @Test fun `stop failure retains Motion for a subsequent retry`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        try {
            val plugin = MetaWearablesDatPlugin(); val motion = mock(Motion::class.java)
            doThrow(IllegalStateException("stop failed")).`when`(motion).stop()
            field(plugin, "motion").set(plugin, motion)
            val result = mock(MethodChannel.Result::class.java)
            plugin.onMethodCall(MethodCall("stopMotion", null), result); advanceUntilIdle()
            verify(result).error(eq("MOTION_ERROR"), eq("stop failed"), isNull())
            assertSame(motion, field(plugin, "motion").get(plugin))
        } finally { Dispatchers.resetMain() }
    }

    @Test fun `remove failure keeps both handles and retry can detach without stopping camera`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        try {
            val plugin = MetaWearablesDatPlugin()
            var failRemoval = true
            // Exercise the SDK extension; emulate its internal capability registry
            // returning an explicit failure, then a success on the next attempt.
            val parent = mock(DeviceSession::class.java) { invocation ->
                if (invocation.method.name.startsWith("removeCapabilityByType")) {
                    if (failRemoval) DatResult.failure<Unit, DeviceSessionError>(DeviceSessionError.UNEXPECTED_ERROR)
                    else DatResult.success<Unit, DeviceSessionError>(Unit)
                } else RETURNS_DEFAULTS.answer(invocation)
            }
            val motion = mock(Motion::class.java); val camera = mock(Stream::class.java)
            `when`(camera.state).thenReturn(MutableStateFlow(StreamState.STREAMING))
            field(plugin, "session").set(plugin, parent); field(plugin, "motion").set(plugin, motion)
            field(plugin, "stream").set(plugin, camera)
            val failed = mock(MethodChannel.Result::class.java)
            plugin.onMethodCall(MethodCall("stopMotion", null), failed); advanceUntilIdle()
            verify(failed).error(eq("MOTION_ERROR"), anyString(), isNull())
            assertSame(motion, field(plugin, "motion").get(plugin))
            assertSame(parent, field(plugin, "session").get(plugin))
            verify(camera, never()).stop(); verify(camera, never()).start(); verify(parent, never()).stop()
            failRemoval = false
            val retried = mock(MethodChannel.Result::class.java)
            plugin.onMethodCall(MethodCall("stopMotion", null), retried); advanceUntilIdle()
            verify(retried).success(true)
            assertNull(field(plugin, "motion").get(plugin))
            assertSame(parent, field(plugin, "session").get(plugin))
            verify(camera, never()).stop(); verify(camera, never()).start(); verify(parent, never()).stop()
        } finally { Dispatchers.resetMain() }
    }

    @Test fun `paused parent rejects adding either sibling without stopping active capability`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        try {
            for (startCamera in listOf(false, true)) {
                val plugin = MetaWearablesDatPlugin(); ready(plugin)
                val parent = mock(DeviceSession::class.java)
                `when`(parent.state).thenReturn(MutableStateFlow(DeviceSessionState.PAUSED))
                field(plugin, "session").set(plugin, parent)
                val motion = mock(Motion::class.java); val camera = mock(Stream::class.java)
                if (startCamera) field(plugin, "motion").set(plugin, motion)
                else field(plugin, "stream").set(plugin, camera)
                val result = mock(MethodChannel.Result::class.java)
                plugin.onMethodCall(MethodCall(if (startCamera) "startStreamSession" else "startMotion", null), result)
                verify(result).error(eq("DEVICE_SESSION_NOT_READY"), anyString(), isNull())
                verify(parent, never()).stop(); verifyNoInteractions(motion, camera)
                assertSame(parent, field(plugin, "session").get(plugin))
            }
        } finally { Dispatchers.resetMain() }
    }

    @Test fun `stale stopped Motion does not keep parent alive after final camera stop`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        try {
            val plugin = MetaWearablesDatPlugin()
            val motion = mock(Motion::class.java); val parent = mock(DeviceSession::class.java)
            `when`(motion.state).thenReturn(MutableStateFlow(MotionState.STOPPED))
            `when`(motion.errors).thenReturn(MutableStateFlow(null))
            field(plugin, "motion").set(plugin, motion); field(plugin, "session").set(plugin, parent)
            field(plugin, "stream").set(plugin, mock(Stream::class.java))
            val result = mock(MethodChannel.Result::class.java)
            plugin.onMethodCall(MethodCall("stopStreamSession", null), result); advanceUntilIdle()
            verify(result).success(true); verify(parent).stop()
            assertNull(field(plugin, "motion").get(plugin)); assertNull(field(plugin, "session").get(plugin))
        } finally { Dispatchers.resetMain() }
    }

    @Test fun `backgrounding stops Motion and shared session unless explicitly opted in`() = runTest {
        Dispatchers.setMain(StandardTestDispatcher(testScheduler))
        try {
            for (enabled in listOf(false, true)) {
                val plugin = MetaWearablesDatPlugin(); val motion = mock(Motion::class.java)
                val parent = mock(DeviceSession::class.java)
                field(plugin, "motion").set(plugin, motion); field(plugin, "session").set(plugin, parent)
                field(plugin, "backgroundStreamingStarted").set(plugin, enabled)
                plugin.javaClass.getDeclaredMethod("handleEnteredBackground").apply { isAccessible = true }.invoke(plugin)
                if (enabled) {
                    verify(parent, never()).stop(); assertSame(motion, field(plugin, "motion").get(plugin))
                } else {
                    verify(parent).stop(); assertNull(field(plugin, "motion").get(plugin))
                }
            }
        } finally { Dispatchers.resetMain() }
    }
}
