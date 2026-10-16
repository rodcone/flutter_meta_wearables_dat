package io.rodcone.flutter_meta_wearables_dat

import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.jupiter.api.Test

class StreamDiagnosticsTrackerTest {
    private var now = 100.0
    private fun tracker() = StreamDiagnosticsTracker { now }

    @Test fun deadlineReadIndependenceAndLateRecovery() {
        val t = tracker()
        now += 30
        assertFalse(t.pollFirstFrame())
        t.stateChanged(true)
        repeat(9) { now += 1; assertFalse(t.pollFirstFrame()) }
        repeat(10) { t.snapshot() }
        now += 1
        assertTrue(t.pollFirstFrame())
        assertFalse(t.pollFirstFrame())
        t.stateChanged(false); now += 20; t.stateChanged(true)
        now += 1
        assertFalse(t.pollFirstFrame())
        t.noteArrival()
        assertNull(t.snapshot()["stallReason"])
        assertEquals(false, t.snapshot()["waitingForFirstFrame"])
    }

    @Test fun pausesAndSuspensionGapsAreExcluded() {
        val t = tracker(); t.stateChanged(true)
        repeat(4) { now += 1; assertFalse(t.pollFirstFrame()) }
        t.stateChanged(false); now += 100
        assertFalse(t.pollFirstFrame())
        t.stateChanged(true)
        now += 50; assertFalse(t.pollFirstFrame())
        repeat(5) { now += 1; assertFalse(t.pollFirstFrame()) }
        now += 1; assertTrue(t.pollFirstFrame())
    }

    @Test fun twoFpsAndDecayAndGracePreserveActualTimestamps() {
        val t = tracker(); t.stateChanged(true)
        repeat(4) {
            now += .5; t.noteArrival(); t.noteSubmission()
            assertFalse(t.pollFirstFrame())
        }
        assertEquals(4L, t.snapshot()["framesReceived"])
        assertEquals(4L, t.snapshot()["framesSubmitted"])
        now += 3
        assertEquals(0.0, t.snapshot()["receivedFps"])
        val age = t.snapshot()["timeSinceLastSubmissionUs"]
        t.resumeGrace()
        assertEquals(age, t.snapshot()["timeSinceLastSubmissionUs"])
    }

    @Test fun submissionRecoveryAndSessionIsolation() {
        val t = tracker()
        t.setStallReason("textureSubmissionsStopped"); t.noteArrival()
        assertEquals("textureSubmissionsStopped", t.snapshot()["stallReason"])
        t.noteSubmission(); assertNull(t.snapshot()["stallReason"])
        val replacement = tracker()
        t.noteArrival()
        assertNotEquals(replacement.sessionId, t.sessionId)
        assertEquals(0L, replacement.snapshot()["framesReceived"])
    }

    @Test fun existingDeliveryThresholdsAndBackgroundRules() {
        assertNull(StreamDiagnosticsTracker.deliveryStall(1.5, 6.0, false))
        assertEquals("sdkFramesStopped", StreamDiagnosticsTracker.deliveryStall(1.501, 0.0, false))
        assertEquals("textureSubmissionsStopped", StreamDiagnosticsTracker.deliveryStall(.5, 6.001, false))
        assertNull(StreamDiagnosticsTracker.deliveryStall(.5, 100.0, true))
        assertEquals("sdkFramesStopped", StreamDiagnosticsTracker.deliveryStall(2.0, 100.0, true))
    }

    @Test fun foregroundGraceDoesNotConsumeWaitBudget() {
        val t = tracker(); t.stateChanged(true)
        repeat(9) { now += 1; assertFalse(t.pollFirstFrame()) }
        t.resumeGrace()
        now += 1; assertFalse(t.pollFirstFrame())
        assertEquals(9_000_000L, t.snapshot()["firstFrameWaitUs"])
        now += 1; assertFalse(t.pollFirstFrame())
        now += .5; assertTrue(t.pollFirstFrame())
    }

    @Test fun backgroundArrivalsNeedNoTextureSubmission() {
        val t = tracker(); t.stateChanged(true)
        repeat(40) { now += .5; t.noteArrival(); assertFalse(t.pollFirstFrame()) }
        assertEquals(0L, t.snapshot()["framesSubmitted"])
        assertNull(t.snapshot()["timeSinceLastSubmissionUs"])
        assertNull(t.snapshot()["stallReason"])
    }
}
