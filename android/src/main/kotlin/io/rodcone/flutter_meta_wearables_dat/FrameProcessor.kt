package io.rodcone.flutter_meta_wearables_dat

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Matrix
import android.util.Log
import android.view.Surface
import com.meta.wearable.dat.camera.types.VideoFrame
import java.nio.ByteBuffer

/**
 * A read of the frame pipeline's clocks, taken together.
 *
 * `null` means no frame of that kind has been seen on this stream yet — a
 * stream that has not produced its first frame is starting up, not stalled.
 */
internal data class FrameLiveness(
        val sinceArrivalNanos: Long?,
        val sincePushNanos: Long?,
        /**
         * Nanos since the *first* arrival. The baseline for "frames are arriving
         * but none has ever reached the surface" — without it a pipeline that
         * never pushed anything looks healthy forever, because the arrival clock
         * keeps resetting and there is no push clock to compare against.
         */
        val sinceFirstArrivalNanos: Long?,
        val framesArrived: Int,
        val framesPushed: Int,
) {
    val hasArrived: Boolean
        get() = sinceArrivalNanos != null
}

/**
 * Handles I420 → ARGB frame conversion, FPS throttling, and SurfaceTexture rendering.
 * Reuses byte/pixel arrays and bitmaps across frames to avoid per-frame GC pressure.
 */
internal class FrameProcessor {

    companion object {
        private const val TAG = "MetaWearablesDat"
    }

    private var targetFPS: Int = 30

    // Frame liveness, mirroring iOS's FrameLivenessTracker. `0L` means "never",
    // so these stay unboxed primitives the stall watchdog can read from another
    // coroutine without allocating per frame. Arrival is stamped by the stream's
    // collect loop before any gate; push only when a frame reaches the surface.
    // A freeze with both flat is the stream going quiet; arrivals climbing with
    // pushes flat is a plugin fault.
    @Volatile private var firstArrivalNanos: Long = 0L
    @Volatile private var lastArrivalNanos: Long = 0L
    @Volatile private var lastPushNanos: Long = 0L
    @Volatile private var framesArrived: Int = 0
    @Volatile private var framesPushed: Int = 0

    // When the next frame is due. A deadline rather than a minimum gap — see
    // `processFrame`.
    @Volatile private var nextPushDueNanos: Long = 0L
    private var reusableBitmap: Bitmap? = null
    private var reusableByteArray: ByteArray? = null
    private var reusablePixelArray: IntArray? = null

    // Post-conversion rotation in degrees (0/90/180/270). Used to compensate
    // for video rotation metadata that the MockDeviceKit SDK ignores when
    // it streams user-picked files — phone-recorded portrait videos arrive
    // as native-landscape I420 and would otherwise render sideways.
    @Volatile private var rotationDegrees: Int = 0
    private var lastTargetWidth: Int = 0
    private var lastTargetHeight: Int = 0

    // `@Volatile` + synchronization below prevents a teardown race where the
    // stream's coroutine delivers a final frame on Dispatchers.Default while
    // the main thread calls `release()` and recycles the bitmap.
    @Volatile private var released: Boolean = false
    private val lock = Any()

    fun configure(fps: Int) {
        targetFPS = fps
        framesArrived = 0
        framesPushed = 0
        firstArrivalNanos = 0L
        lastArrivalNanos = 0L
        lastPushNanos = 0L
        nextPushDueNanos = 0L
        released = false
    }

    /**
     * Records that the SDK delivered a frame. Called by the stream's collect
     * loop before any gate, so it tracks delivery regardless of what the plugin
     * then does with the frame.
     */
    fun noteArrival() {
        val now = System.nanoTime()
        if (firstArrivalNanos == 0L) firstArrivalNanos = now
        lastArrivalNanos = now
        framesArrived++
    }

    /**
     * Restarts the push clock without counting a push, for when the surface is
     * legitimately expected to have gone undrawn — returning to the foreground
     * after background streaming. Without it the first watchdog tick after
     * foregrounding measures the whole background window.
     */
    fun resyncPushClock() {
        lastPushNanos = System.nanoTime()
        nextPushDueNanos = 0L
    }

    /** A read of the frame clocks, relative to now. */
    fun liveness(): FrameLiveness {
        val now = System.nanoTime()
        val arrival = lastArrivalNanos
        val push = lastPushNanos
        val first = firstArrivalNanos
        return FrameLiveness(
                sinceArrivalNanos = if (arrival == 0L) null else now - arrival,
                sincePushNanos = if (push == 0L) null else now - push,
                sinceFirstArrivalNanos = if (first == 0L) null else now - first,
                framesArrived = framesArrived,
                framesPushed = framesPushed,
        )
    }

    fun setRotation(degrees: Int) {
        val normalized = ((degrees % 360) + 360) % 360
        if (normalized == rotationDegrees) return
        rotationDegrees = normalized
        // Force the caller to re-push the target buffer size on the next frame.
        synchronized(lock) {
            lastTargetWidth = 0
            lastTargetHeight = 0
        }
    }

    /**
     * Returns the post-rotation dimensions for a source frame. Callers use
     * these to size the Flutter surface and the `VideoStreamSize` channel.
     */
    fun targetDimensions(srcWidth: Int, srcHeight: Int): Pair<Int, Int> =
            if (rotationDegrees == 90 || rotationDegrees == 270) {
                srcHeight to srcWidth
            } else {
                srcWidth to srcHeight
            }

    /**
     * Process a video frame: throttle by FPS, convert I420 → ARGB, render to surface.
     */
    fun processFrame(videoFrame: VideoFrame, surface: Surface) {
        if (released) return

        // FPS throttling
        // A deadline, not a minimum gap. Dropping anything that arrives less
        // than `1/targetFPS` after the last push aliases badly whenever the
        // source rate sits near the target: measured on iOS, a 29 fps stream
        // against a 30 fps request rendered at 16 fps, because every gap that
        // jittered under the interval was dropped and the next landed at twice
        // it. Android ran the same rule and had the same flaw. Against a
        // deadline, a source at or below the target passes through untouched
        // and a faster one is still decimated to the target.
        val minIntervalNanos = 1_000_000_000L / targetFPS
        val now = System.nanoTime()
        val lastTime = lastPushNanos
        if (nextPushDueNanos != 0L && now < nextPushDueNanos) {
            return
        }

        if (!surface.isValid) return

        // Guarded against `release()` racing with an in-flight frame.
        synchronized(lock) {
            if (released) return
            val width = videoFrame.width
            val height = videoFrame.height

            // Reuse bitmap to avoid per-frame allocation
            var bitmap = reusableBitmap
            if (bitmap == null || bitmap.width != width || bitmap.height != height) {
                bitmap?.recycle()
                bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
                reusableBitmap = bitmap
            }

            convertI420toArgbBitmap(videoFrame.buffer, width, height, bitmap)

            // Draw bitmap onto the SurfaceTexture — this pushes a frame to Flutter
            try {
                val canvas: Canvas = surface.lockCanvas(null) ?: return
                try {
                    val rotation = rotationDegrees
                    if (rotation == 0) {
                        canvas.drawBitmap(bitmap, 0f, 0f, null)
                    } else {
                        val matrix = Matrix()
                        matrix.postRotate(rotation.toFloat(), width / 2f, height / 2f)
                        if (rotation == 90 || rotation == 270) {
                            // After rotating a WxH bitmap in place, the bounding box
                            // is HxW around the original center — shift so the top-
                            // left of the rotated frame aligns with the canvas origin.
                            matrix.postTranslate((height - width) / 2f, (width - height) / 2f)
                        }
                        canvas.drawBitmap(bitmap, matrix, null)
                    }
                } finally {
                    surface.unlockCanvasAndPost(canvas)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to render frame to texture surface", e)
                return
            }

            lastPushNanos = now
            framesPushed++
            // Advance from the previous deadline so the cadence does not drift,
            // but never schedule in the past: after a stall that would let a
            // burst through while it caught up.
            val base = if (nextPushDueNanos == 0L) now else nextPushDueNanos
            nextPushDueNanos = maxOf(now, base + minIntervalNanos)

            // Report arrivals alongside renders. Counting only what survived the
            // throttle made this line go silent on a wedged throttle exactly as
            // it does on a dead stream, so reading it could not tell the two
            // apart.
            if (framesPushed % 30 == 0 && lastTime != 0L) {
                val actualFPS = 1_000_000_000.0 / (now - lastTime)
                Log.d(
                        TAG,
                        "Texture path — arrived: $framesArrived, pushed: $framesPushed, " +
                                "target: $targetFPS, actual: ${"%.1f".format(actualFPS)} FPS"
                )
            }
        }
    }

    /**
     * Returns true if the post-rotation dimensions changed — caller should
     * push the new buffer size to the SurfaceTexture and re-emit the size
     * over the video-size event channel. Tracks rotated dims instead of
     * source dims so rotation changes (e.g. switching from a video feed to
     * a camera facing) also trigger a refresh.
     */
    fun needsBufferSizeUpdate(srcWidth: Int, srcHeight: Int): Boolean {
        val (tw, th) = targetDimensions(srcWidth, srcHeight)
        return tw != lastTargetWidth || th != lastTargetHeight
    }

    fun onSurfaceBufferSizeApplied(srcWidth: Int, srcHeight: Int) {
        val (tw, th) = targetDimensions(srcWidth, srcHeight)
        synchronized(lock) {
            lastTargetWidth = tw
            lastTargetHeight = th
        }
    }

    fun release() {
        released = true
        synchronized(lock) {
            reusableBitmap?.recycle()
            reusableBitmap = null
            reusableByteArray = null
            reusablePixelArray = null
            firstArrivalNanos = 0L
            lastArrivalNanos = 0L
            lastPushNanos = 0L
            nextPushDueNanos = 0L
            framesArrived = 0
            framesPushed = 0
            lastTargetWidth = 0
            lastTargetHeight = 0
            rotationDegrees = 0
        }
    }

    /**
     * Convert I420 (planar YUV) directly to an ARGB_8888 Bitmap — no JPEG intermediate step.
     * Uses BT.601 full-range coefficients with fixed-point integer math (scaled by 1024).
     * Reuses byte/pixel arrays across frames to avoid per-frame GC pressure.
     */
    private fun convertI420toArgbBitmap(buffer: ByteBuffer, width: Int, height: Int, bitmap: Bitmap) {
        val dataSize = buffer.remaining()
        var byteArray = reusableByteArray
        if (byteArray == null || byteArray.size < dataSize) {
            byteArray = ByteArray(dataSize)
            reusableByteArray = byteArray
        }
        val originalPosition = buffer.position()
        buffer.get(byteArray, 0, dataSize)
        buffer.position(originalPosition)

        val ySize = width * height
        val uvQuarter = ySize / 4
        var pixels = reusablePixelArray
        if (pixels == null || pixels.size < ySize) {
            pixels = IntArray(ySize)
            reusablePixelArray = pixels
        }

        for (j in 0 until height) {
            for (i in 0 until width) {
                val yIndex = j * width + i
                val uvIndex = (j / 2) * (width / 2) + (i / 2)

                val y = (byteArray[yIndex].toInt() and 0xFF)
                val u = (byteArray[ySize + uvIndex].toInt() and 0xFF) - 128
                val v = (byteArray[ySize + uvQuarter + uvIndex].toInt() and 0xFF) - 128

                var r = y + ((1404 * v) shr 10)
                var g = y - ((346 * u) shr 10) - ((715 * v) shr 10)
                var b = y + ((1774 * u) shr 10)

                r = r.coerceIn(0, 255)
                g = g.coerceIn(0, 255)
                b = b.coerceIn(0, 255)

                pixels[yIndex] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
            }
        }

        bitmap.setPixels(pixels, 0, width, 0, 0, width, height)
    }
}
