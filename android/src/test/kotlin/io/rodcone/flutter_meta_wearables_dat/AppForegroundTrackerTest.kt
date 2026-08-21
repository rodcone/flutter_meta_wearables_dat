package io.rodcone.flutter_meta_wearables_dat

import android.app.Activity
import kotlin.test.assertEquals
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import org.mockito.Mockito.mock
import org.mockito.Mockito.`when`

/**
 * Covers the four rules in [AppForegroundTracker] that make process-wide
 * foreground detection correct. Each of these is a real bug the naive
 * implementation has, and none of them is observable without a device
 * otherwise — this is the only part of the background-streaming contract that
 * can be tested on the JVM.
 */
class AppForegroundTrackerTest {

    /** Runs scheduled work only when the test says so. */
    private class FakeScheduler {
        private var pending: (() -> Unit)? = null
        var cancelled = 0
            private set

        fun schedule(@Suppress("UNUSED_PARAMETER") delayMs: Long, action: () -> Unit):
                AppForegroundTracker.Cancellable {
            pending = action
            return AppForegroundTracker.Cancellable {
                if (pending != null) cancelled++
                pending = null
            }
        }

        /** Fires the pending job, as the debounce elapsing would. */
        fun advance() {
            val action = pending
            pending = null
            action?.invoke()
        }

        val hasPending: Boolean
            get() = pending != null
    }

    private lateinit var scheduler: FakeScheduler
    private lateinit var tracker: AppForegroundTracker
    private var backgroundCount = 0
    private var foregroundCount = 0

    @BeforeEach
    fun setUp() {
        scheduler = FakeScheduler()
        backgroundCount = 0
        foregroundCount = 0
        tracker = AppForegroundTracker(schedule = scheduler::schedule)
        tracker.onEnteredBackground = { backgroundCount++ }
        tracker.onEnteredForeground = { foregroundCount++ }
    }

    private fun activity(changingConfigurations: Boolean = false): Activity {
        val a = mock(Activity::class.java)
        `when`(a.isChangingConfigurations).thenReturn(changingConfigurations)
        return a
    }

    @Test
    fun `start then stop reports background once the debounce elapses`() {
        val a = activity()
        tracker.onActivityStarted(a)
        tracker.onActivityStopped(a)

        assertEquals(0, backgroundCount, "must not fire before the debounce elapses")
        scheduler.advance()
        assertEquals(1, backgroundCount)
        assertEquals(0, foregroundCount)
    }

    @Test
    fun `activity to activity transition is not a background`() {
        // Android guarantees A.onPause -> B.onStart -> A.onStop, so the set is
        // never empty. A per-activity onStop hook gets this wrong.
        val a = activity()
        val b = activity()
        tracker.onActivityStarted(a)
        tracker.onActivityStarted(b)
        tracker.onActivityStopped(a)

        assertEquals(false, scheduler.hasPending, "no background should even be scheduled")
        scheduler.advance()
        assertEquals(0, backgroundCount)
    }

    @Test
    fun `configuration change is not a background`() {
        val a = activity(changingConfigurations = true)
        tracker.onActivityStarted(a)
        tracker.onActivityStopped(a)

        assertEquals(false, scheduler.hasPending)
        scheduler.advance()
        assertEquals(0, backgroundCount, "rotation must not stop the stream")
    }

    @Test
    fun `returning within the debounce cancels the pending background`() {
        val a = activity()
        tracker.onActivityStarted(a)
        tracker.onActivityStopped(a)
        tracker.onActivityStarted(a)

        assertEquals(1, scheduler.cancelled)
        scheduler.advance()
        assertEquals(0, backgroundCount)
        assertEquals(0, foregroundCount, "never went background, so never came foreground")
    }

    @Test
    fun `stop without a prior start is ignored`() {
        // Cached-engine / add-to-app: the plugin attached after the activity
        // already started, so we never saw the other half of the transition.
        // Failing closed keeps a live stream alive.
        tracker.onActivityStopped(activity())

        assertEquals(false, scheduler.hasPending)
        scheduler.advance()
        assertEquals(0, backgroundCount)
    }

    @Test
    fun `duplicate stop reports background only once`() {
        val a = activity()
        tracker.onActivityStarted(a)
        tracker.onActivityStopped(a)
        tracker.onActivityStopped(a)
        scheduler.advance()

        assertEquals(1, backgroundCount)
    }

    @Test
    fun `background then foreground reports one of each`() {
        val a = activity()
        tracker.onActivityStarted(a)
        tracker.onActivityStopped(a)
        scheduler.advance()
        tracker.onActivityStarted(a)

        assertEquals(1, backgroundCount)
        assertEquals(1, foregroundCount)
    }

    @Test
    fun `foreground is not reported when no background was reported`() {
        val a = activity()
        tracker.onActivityStarted(a)

        assertEquals(0, foregroundCount)
    }
}
