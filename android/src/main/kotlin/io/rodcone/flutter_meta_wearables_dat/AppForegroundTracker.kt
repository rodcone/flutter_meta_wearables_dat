package io.rodcone.flutter_meta_wearables_dat

import android.app.Activity
import android.app.Application
import android.os.Bundle
import android.util.Log
import java.util.Collections
import java.util.WeakHashMap

/**
 * Tracks whether the host app is in the foreground, process-wide.
 *
 * ## Why `ActivityLifecycleCallbacks` and not the alternatives
 *
 * * `ActivityPluginBinding`'s `HiddenLifecycleReference` is **Activity**-scoped,
 *   not process-scoped. It reports `ON_STOP` on a rotation and on any
 *   Activity-to-Activity transition inside the same app, so it would stop a
 *   stream when the user merely opens the app's own settings screen. It also
 *   needs the `flutter_plugin_android_lifecycle` package to cast safely.
 * * `ProcessLifecycleOwner` has the right semantics but lives in
 *   `androidx.lifecycle:lifecycle-process`, which is not on the classpath, and
 *   drags in `androidx.startup`'s `ContentProvider`. If a host app strips that
 *   provider — a real startup-time optimisation — the owner silently never
 *   advances past `INITIALIZED`, which is exactly the kind of quiet failure
 *   this whole change exists to remove.
 * * `ActivityLifecycleCallbacks` needs no new dependency (the plugin already
 *   holds the `Application`), cannot be stripped, and is plain-JVM testable.
 *   It is what `ProcessLifecycleOwner` wraps.
 *
 * ## The four rules that make it correct
 *
 * 1. **Identity set, not a counter.** A counter can be corrupted by a missed
 *    callback and can go negative; a set cannot double-count. Held weakly so a
 *    leaked Activity cannot pin the app in the "foreground" state forever.
 * 2. **Edge-triggered, and only after we have seen a foreground.** If the
 *    plugin attached after the Activity already started — cached engine,
 *    add-to-app — we never observed the start, so we never claim a background
 *    transition. Failing closed keeps a live stream alive; failing open would
 *    kill it.
 * 3. **Configuration changes are not backgrounding.** `isChangingConfigurations`
 *    filters rotation and `Activity.recreate()`.
 * 4. **Debounce before reporting.** Android can deliver `A.onStop` after
 *    `B.onStart`, and a recreate is a stop/start pair. The delay collapses both.
 *    This is the same trick `ProcessLifecycleOwner` uses.
 *
 * Note the platform asymmetry this leaves, which is inherent and not a bug:
 * opening Recents and lingering genuinely stops the Activity on Android, so the
 * app counts as backgrounded, whereas iOS's app switcher only resigns active.
 * The notification shade does *not* stop the Activity on either platform.
 */
internal class AppForegroundTracker(
        private val debounceMs: Long = DEFAULT_DEBOUNCE_MS,
        /** Injected so tests can drive time instead of waiting on it. */
        private val schedule: (Long, () -> Unit) -> Cancellable,
) : Application.ActivityLifecycleCallbacks {

    /** Something that can be cancelled before it runs. */
    internal fun interface Cancellable {
        fun cancel()
    }

    var onEnteredBackground: (() -> Unit)? = null
    var onEnteredForeground: (() -> Unit)? = null

    private val startedActivities: MutableSet<Activity> =
            Collections.newSetFromMap(WeakHashMap<Activity, Boolean>())
    private var pendingBackground: Cancellable? = null
    private var everForegrounded = false
    private var reportedBackground = false

    override fun onActivityStarted(activity: Activity) {
        val wasEmpty = startedActivities.isEmpty()
        startedActivities.add(activity)
        if (!wasEmpty) return

        everForegrounded = true
        // Cancel a pending background before it fires: this is the
        // Activity-transition and quick-return case.
        pendingBackground?.cancel()
        pendingBackground = null
        if (reportedBackground) {
            reportedBackground = false
            Log.d(TAG, "lifecycle: app entered foreground")
            onEnteredForeground?.invoke()
        }
    }

    override fun onActivityStopped(activity: Activity) {
        startedActivities.remove(activity)
        if (startedActivities.isNotEmpty()) return
        // Rule 3: a recreate is not a background.
        if (activity.isChangingConfigurations) return
        // Rule 2: never claim a transition we did not see the other half of.
        if (!everForegrounded || reportedBackground) return

        pendingBackground?.cancel()
        pendingBackground =
                schedule(debounceMs) {
                    pendingBackground = null
                    if (startedActivities.isNotEmpty()) return@schedule
                    reportedBackground = true
                    Log.d(TAG, "lifecycle: app entered background")
                    onEnteredBackground?.invoke()
                }
    }

    override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit

    override fun onActivityResumed(activity: Activity) = Unit

    override fun onActivityPaused(activity: Activity) = Unit

    override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit

    override fun onActivityDestroyed(activity: Activity) {
        startedActivities.remove(activity)
    }

    fun dispose() {
        pendingBackground?.cancel()
        pendingBackground = null
        startedActivities.clear()
    }

    companion object {
        private const val TAG = "MWDAT"
        /** Matches `ProcessLifecycleOwner`'s own debounce. */
        const val DEFAULT_DEBOUNCE_MS = 700L
    }
}
