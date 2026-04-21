package io.rodcone.flutter_meta_wearables_dat

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Matrix
import android.util.Log
import android.view.Surface
import com.meta.wearable.dat.camera.types.VideoFrame
import java.nio.ByteBuffer

/**
 * Handles I420 → ARGB frame conversion, FPS throttling, and SurfaceTexture rendering.
 * Reuses byte/pixel arrays and bitmaps across frames to avoid per-frame GC pressure.
 */
internal class FrameProcessor {

    companion object {
        private const val TAG = "MetaWearablesDat"
    }

    private var targetFPS: Double = 30.0
    private var lastFrameSendTime: Long? = null
    private var frameCount: Int = 0
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

    fun configure(fps: Double) {
        targetFPS = fps
        frameCount = 0
        lastFrameSendTime = null
        released = false
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
        val minIntervalNanos = (1_000_000_000.0 / targetFPS).toLong()
        val now = System.nanoTime()
        val lastTime = lastFrameSendTime
        if (lastTime != null && (now - lastTime) < minIntervalNanos) {
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

            lastFrameSendTime = now
            frameCount++
            if (frameCount % 30 == 0 && lastTime != null) {
                val actualFPS = 1_000_000_000.0 / (now - lastTime)
                Log.d(
                        TAG,
                        "Texture path — $frameCount frames, " +
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
            lastFrameSendTime = null
            frameCount = 0
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
