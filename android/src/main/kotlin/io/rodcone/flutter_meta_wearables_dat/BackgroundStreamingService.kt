package io.rodcone.flutter_meta_wearables_dat

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat

/**
 * Foreground service that keeps the Flutter process alive while a DAT stream
 * session is active, so the stream keeps running when the host app is
 * backgrounded or the phone is locked. Paired with a PARTIAL_WAKE_LOCK to
 * keep the CPU awake for BLE / camera-frame delivery.
 *
 * Mirrors Meta's `StreamingService` from the official BackgroundStreamingGuide.
 * The plugin starts/stops this service via `enableBackgroundStreaming` /
 * `disableBackgroundStreaming` method-channel calls.
 *
 * Notification title/text/channel is passed as intent extras so consumer apps
 * can brand the ongoing notification. Icon falls back to the host app's
 * launcher icon when `iconResourceName` is absent or cannot be resolved.
 */
internal class BackgroundStreamingService : Service() {

    companion object {
        private const val TAG = "MetaWearablesDat"
        private const val NOTIFICATION_ID = 0x4D574441 // "MWDA"
        private const val WAKE_LOCK_TAG = "MWDAT::StreamingWakeLock"

        const val EXTRA_TITLE = "title"
        const val EXTRA_TEXT = "text"
        const val EXTRA_CHANNEL_ID = "channelId"
        const val EXTRA_CHANNEL_NAME = "channelName"
        const val EXTRA_ICON_RESOURCE_NAME = "iconResourceName"

        private const val DEFAULT_CHANNEL_ID = "flutter_meta_wearables_dat.streaming"
        private const val DEFAULT_CHANNEL_NAME = "Stream Session"
        private const val DEFAULT_TITLE = "Streaming"
        private const val DEFAULT_TEXT = "Streaming from your Meta glasses"
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE) ?: DEFAULT_TITLE
        val text = intent?.getStringExtra(EXTRA_TEXT) ?: DEFAULT_TEXT
        val channelId = intent?.getStringExtra(EXTRA_CHANNEL_ID) ?: DEFAULT_CHANNEL_ID
        val channelName = intent?.getStringExtra(EXTRA_CHANNEL_NAME) ?: DEFAULT_CHANNEL_NAME
        val iconResourceName = intent?.getStringExtra(EXTRA_ICON_RESOURCE_NAME)

        ensureNotificationChannel(channelId, channelName)
        val notification = buildNotification(channelId, title, text, iconResourceName)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // API 30+: must declare foregroundServiceType explicitly. We use
            // `connectedDevice` because the work is driven by the BLE-linked
            // wearable — matches Meta's reference service.
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }

        acquireWakeLock()
        Log.d(TAG, "BackgroundStreamingService started (wake lock + foreground notification)")

        // START_STICKY: if Android kills us for memory pressure, re-deliver
        // the service intent (without extras) so the notification comes back.
        return START_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        Log.d(TAG, "BackgroundStreamingService destroyed")
        super.onDestroy()
    }

    private fun ensureNotificationChannel(channelId: String, channelName: String) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (manager.getNotificationChannel(channelId) != null) return

        val channel = NotificationChannel(
            channelId,
            channelName,
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Keeps the Meta glasses stream alive in the background."
            setShowBadge(false)
            enableLights(false)
            enableVibration(false)
        }
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(
        channelId: String,
        title: String,
        text: String,
        iconResourceName: String?,
    ): Notification {
        val iconRes = resolveIcon(iconResourceName)
        return NotificationCompat.Builder(this, channelId)
            .setContentTitle(title)
            .setContentText(text)
            .setSmallIcon(iconRes)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setShowWhen(false)
            .build()
    }

    private fun resolveIcon(iconResourceName: String?): Int {
        if (!iconResourceName.isNullOrBlank()) {
            val id = resources.getIdentifier(iconResourceName, "drawable", packageName)
            if (id != 0) return id
            val mipmapId = resources.getIdentifier(iconResourceName, "mipmap", packageName)
            if (mipmapId != 0) return mipmapId
            Log.w(TAG, "Icon resource '$iconResourceName' not found — falling back to app icon")
        }
        val appIcon = applicationInfo.icon
        if (appIcon != 0) return appIcon
        // Last-resort fallback — a system icon guaranteed to exist.
        return android.R.drawable.ic_media_play
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
        val lock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG)
        lock.setReferenceCounted(false)
        // No timeout — we hold the lock for the lifetime of the service and
        // release it in `onDestroy`. This mirrors Meta's reference service.
        lock.acquire()
        wakeLock = lock
    }

    private fun releaseWakeLock() {
        val lock = wakeLock ?: return
        if (lock.isHeld) lock.release()
        wakeLock = null
    }
}
