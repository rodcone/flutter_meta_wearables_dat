package io.rodcone.flutter_meta_wearables_dat

import com.meta.wearable.dat.motion.types.MotionSample
import com.meta.wearable.dat.motion.types.MotionSource
import com.meta.wearable.dat.motion.types.Vector3
import com.meta.wearable.dat.motion.types.Quaternion
import io.flutter.plugin.common.EventChannel
import kotlin.test.*
import kotlinx.coroutines.*
import kotlinx.coroutines.test.*
import org.junit.jupiter.api.Test

@OptIn(ExperimentalCoroutinesApi::class)
class MotionStreamHandlersTest {
    private class Sink : EventChannel.EventSink {
        val events = mutableListOf<Any?>()
        val threads = mutableListOf<Thread>()
        override fun success(event: Any?) { events.add(event); threads.add(Thread.currentThread()) }
        override fun error(code: String, message: String?, details: Any?) = error("Unexpected $code")
        override fun endOfStream() = Unit
    }

    private fun sample(timestamp: Long = 1) = MotionSample(
            timestampNs = timestamp, accelerometer = Vector3(1f, -2f, 3f),
            gyroscope = null, magnetometer = Vector3(4f, 5f, 6f),
            orientation = Quaternion(0f, 0f, 0f, 1f), source = MotionSource.GLASSES)

    @Test fun `native values retain nanoseconds nullable independent sensors and quaternion ordering`() {
        val map = sample(9_876_543_210L).toMotionMap()
        assertEquals(9_876_543_210L, map["timestampNs"])
        assertEquals("glasses", map["source"])
        assertEquals(mapOf("x" to 1.0, "y" to -2.0, "z" to 3.0), map["accelerometer"])
        assertNull(map["gyroscope"])
        assertEquals(mapOf("x" to 4.0, "y" to 5.0, "z" to 6.0), map["magnetometer"])
        assertEquals(mapOf("x" to 0.0, "y" to 0.0, "z" to 0.0, "w" to 1.0), map["orientation"])
        assertEquals("neuralBand", sample().copy(source = MotionSource.NEURAL_BAND).toMotionMap()["source"])
        assertEquals("unknown", sample().copy(source = MotionSource.UNKNOWN).toMotionMap()["source"])
    }

    @Test fun `slow platform bounds collection to one pending sample and preserves ordering`() = runTest {
        val handler = MotionSamplesStreamHandler(StandardTestDispatcher(testScheduler))
        val sink = Sink(); handler.onListen(null, sink)
        val session = handler.beginSession()
        var produced = 0
        val job = launch(start = CoroutineStart.UNDISPATCHED) {
            repeat(100) { produced++; handler.emit(session, sample(it.toLong())) }
        }
        assertEquals(1, produced); assertTrue(sink.events.isEmpty())
        advanceUntilIdle(); job.join()
        assertEquals((0L..99L).toList(), sink.events.map { (it as Map<*, *>)["timestampNs"] })
    }

    @Test fun `cancel and relisten cannot replay queued samples`() = runTest {
        val handler = MotionSamplesStreamHandler(StandardTestDispatcher(testScheduler))
        val old = Sink(); val replacement = Sink(); handler.onListen(null, old)
        val session = handler.beginSession()
        launch(start = CoroutineStart.UNDISPATCHED) { handler.emit(session, sample()) }
        handler.onCancel(null); handler.onListen(null, replacement)
        advanceUntilIdle()
        assertTrue(old.events.isEmpty()); assertTrue(replacement.events.isEmpty())
        launch { handler.emit(session, sample(2)) }; advanceUntilIdle()
        assertEquals(2L, (replacement.events.single() as Map<*, *>)["timestampNs"])
    }

    @Test fun `stop and replacement reject both queued and late callbacks`() = runTest {
        val handler = MotionSamplesStreamHandler(StandardTestDispatcher(testScheduler))
        val sink = Sink(); handler.onListen(null, sink)
        val old = handler.beginSession()
        launch(start = CoroutineStart.UNDISPATCHED) { handler.emit(old, sample(1)) }
        handler.endSession(); val fresh = handler.beginSession()
        launch { handler.emit(old, sample(2)) }; launch { handler.emit(fresh, sample(3)) }
        advanceUntilIdle()
        assertEquals(3L, (sink.events.single() as Map<*, *>)["timestampNs"])
    }

    @Test fun `SDK stop before delivery suppresses pending sample`() = runTest {
        val handler = MotionSamplesStreamHandler(StandardTestDispatcher(testScheduler))
        val sink = Sink(); handler.onListen(null, sink)
        val session = handler.beginSession(); var running = true
        launch(start = CoroutineStart.UNDISPATCHED) { handler.emit(session, sample()) { running } }
        running = false; advanceUntilIdle(); assertTrue(sink.events.isEmpty())
    }

    @Test fun `all sink delivery uses the platform dispatcher`() = runBlocking {
        val executor = java.util.concurrent.Executors.newSingleThreadExecutor { r -> Thread(r, "motion-platform") }
        executor.asCoroutineDispatcher().use { platform ->
            val handler = MotionSamplesStreamHandler(platform); val sink = Sink()
            withContext(platform) { handler.onListen(null, sink) }
            val session = handler.beginSession()
            withContext(Dispatchers.Default) { handler.emit(session, sample()) }
            assertEquals(listOf(withContext(platform) { Thread.currentThread() }), sink.threads)
        }
    }

    @Test fun `state replays current state but errors do not replay to replacement subscribers`() {
        val states = MotionEventStreamHandler("stopped"); val errors = MotionEventStreamHandler()
        states.send("paused"); errors.sendError("sensorUnavailable", "Unavailable")
        val sink = Sink(); states.onListen(null, sink); errors.onListen(null, sink)
        assertEquals(listOf<Any?>("paused"), sink.events)
    }
}
