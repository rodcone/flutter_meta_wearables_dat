package io.rodcone.flutter_meta_wearables_dat

import java.util.UUID
import kotlin.math.floor

// One instance per camera session: stale callbacks cannot contaminate a replacement.
internal class StreamDiagnosticsTracker(private val clock: () -> Double = { System.nanoTime() / 1e9 }) {
    companion object {
        fun deliveryStall(sinceArrival: Double, sinceSubmission: Double, background: Boolean): String? = when {
            sinceArrival > 1.5 -> "sdkFramesStopped"
            !background && sinceSubmission > 6 -> "textureSubmissionsStopped"
            else -> null
        }
    }

    val sessionId = UUID.randomUUID().toString()
    private val created = clock()
    private var first: Double? = null
    private var last: Double? = null
    private var submitted: Double? = null
    private var receivedCount = 0L
    private var submittedCount = 0L
    private var stallReason: String? = null
    private var streaming = false
    private var elapsed = 0.0
    private var graceUntil = Double.NEGATIVE_INFINITY
    private var checkpoint = created
    private var reportedFirst = false
    private val epochs = LongArray(20) { -1 }
    private val arrivals = LongArray(20)
    private val pushes = LongArray(20)

    private fun eligibleDelta(now: Double): Double {
        if (now - checkpoint > 2) return 0.0
        return (now - maxOf(checkpoint, graceUntil)).coerceAtLeast(0.0)
    }

    private fun advance(now: Double) {
        // The watchdog normally polls every second. Exclude long suspension gaps.
        if (streaming && first == null) elapsed += eligibleDelta(now)
        checkpoint = now
    }
    @Synchronized fun stateChanged(next: Boolean) { advance(clock()); streaming = next }
    @Synchronized fun resumeGrace() {
        checkpoint = clock()
        graceUntil = checkpoint + 1.5
    }
    private fun record(now: Double, arrival: Boolean) {
        val epoch = floor(now * 10).toLong()
        val index = Math.floorMod(epoch, 20).toInt()
        if (epochs[index] != epoch) {
            epochs[index] = epoch; arrivals[index] = 0; pushes[index] = 0
        }
        if (arrival) arrivals[index]++ else pushes[index]++
    }
    @Synchronized fun setStallReason(reason: String) { stallReason = reason }
    @Synchronized fun noteArrival() {
        val now = clock()
        if (first == null) { advance(now); first = now }
        if (stallReason != "textureSubmissionsStopped") stallReason = null
        last = now; receivedCount++; record(now, true)
    }
    @Synchronized fun noteSubmission() {
        val now = clock()
        if (stallReason == "textureSubmissionsStopped") stallReason = null
        submitted = now; submittedCount++; record(now, false)
    }
    @Synchronized fun pollFirstFrame(): Boolean {
        advance(clock())
        if (!streaming || first != null || elapsed < 10 || reportedFirst) return false
        reportedFirst = true
        return true
    }
    @Synchronized fun snapshot(): MutableMap<String, Any> {
        val now = clock()
        val window = (now - created).coerceIn(0.0, 2.0)
        val epoch = floor(now * 10).toLong()
        var received = 0L; var pushed = 0L
        for (i in 0..19) if (epochs[i] > epoch - 20 && epochs[i] <= epoch) {
            received += arrivals[i]; pushed += pushes[i]
        }
        // Do not expose speculative time that could rewind after a suspension.
        val wait = elapsed
        val result = mutableMapOf<String, Any>(
            "sessionId" to sessionId, "framesReceived" to receivedCount, "framesSubmitted" to submittedCount,
            "waitingForFirstFrame" to (first == null), "firstFrameWaitUs" to (wait * 1e6).toLong(),
            "measurementWindowUs" to (window * 1e6).toLong()
        )
        if (window >= 0.1) {
            result["receivedFps"] = received / window; result["submittedFps"] = pushed / window
        }
        last?.let { result["timeSinceLastFrameUs"] = ((now - it).coerceAtLeast(0.0) * 1e6).toLong() }
        submitted?.let { result["timeSinceLastSubmissionUs"] = ((now - it).coerceAtLeast(0.0) * 1e6).toLong() }
        stallReason?.let { result["stallReason"] = it }
        if (first == null && reportedFirst) result["stallReason"] = "firstFrameTimeout"
        return result
    }
}
