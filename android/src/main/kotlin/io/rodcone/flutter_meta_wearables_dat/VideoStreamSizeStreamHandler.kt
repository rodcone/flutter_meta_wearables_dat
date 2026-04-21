package io.rodcone.flutter_meta_wearables_dat

import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.EventChannel

/**
 * Stream handler that surfaces the video frame dimensions of the active
 * stream to Dart, so the Flutter side can wrap the `Texture` widget in
 * an `AspectRatio` matching the source instead of stretching it into a
 * hardcoded box.
 *
 * The plugin pushes a size whenever the SurfaceTexture's default buffer
 * size is set (first frame) or changes mid-stream.
 */
internal class VideoStreamSizeStreamHandler : EventChannel.StreamHandler {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null
    private var lastWidth: Int = 0
    private var lastHeight: Int = 0

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        // Replay the latest known size so a late subscriber still gets it.
        if (lastWidth > 0 && lastHeight > 0) {
            events?.success(mapOf("width" to lastWidth, "height" to lastHeight))
        }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun send(width: Int, height: Int) {
        if (width <= 0 || height <= 0) return
        if (width == lastWidth && height == lastHeight) return
        lastWidth = width
        lastHeight = height
        val sink = eventSink ?: return
        // EventSinks must be touched from the main thread.
        mainHandler.post {
            sink.success(mapOf("width" to width, "height" to height))
        }
    }

    fun reset() {
        lastWidth = 0
        lastHeight = 0
    }

    fun dispose() {
        eventSink = null
        lastWidth = 0
        lastHeight = 0
    }
}
