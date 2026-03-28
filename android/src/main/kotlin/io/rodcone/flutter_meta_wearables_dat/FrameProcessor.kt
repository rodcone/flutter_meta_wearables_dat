package io.rodcone.flutter_meta_wearables_dat

import android.graphics.Bitmap
import android.graphics.Canvas
import android.util.Log
import android.view.Surface
import com.meta.wearable.dat.camera.types.VideoFrame
import java.io.ByteArrayOutputStream
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

    fun configure(fps: Double) {
        targetFPS = fps
        frameCount = 0
        lastFrameSendTime = null
    }

    /**
     * Process a video frame: throttle by FPS, convert I420 → ARGB, render to surface.
     */
    fun processFrame(videoFrame: VideoFrame, surface: Surface) {
        // FPS throttling
        val minIntervalNanos = (1_000_000_000.0 / targetFPS).toLong()
        val now = System.nanoTime()
        val lastTime = lastFrameSendTime
        if (lastTime != null && (now - lastTime) < minIntervalNanos) {
            return
        }

        if (!surface.isValid) return

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
                canvas.drawBitmap(bitmap, 0f, 0f, null)
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

    /**
     * Returns true if the frame dimensions changed (caller should update SurfaceTexture buffer size).
     */
    fun needsBufferSizeUpdate(width: Int, height: Int): Boolean {
        val bmp = reusableBitmap
        return bmp == null || bmp.width != width || bmp.height != height
    }

    @Synchronized
    fun copyAsJpegBytes(quality: Int = 70): ByteArray? {
        val bmp = reusableBitmap ?: return null
        val stream = ByteArrayOutputStream()
        bmp.compress(Bitmap.CompressFormat.JPEG, quality, stream)

        return stream.toByteArray()
    }

    fun release() {
        reusableBitmap?.recycle()
        reusableBitmap = null
        reusableByteArray = null
        reusablePixelArray = null
        lastFrameSendTime = null
        frameCount = 0
    }

    /**
     * Convert I420 (planar YUV) directly to an ARGB_8888 Bitmap — no JPEG intermediate step.
     * Uses BT.601 full-range coefficients with fixed-point integer math (scaled by 1024).
     * Reuses byte/pixel arrays across frames to avoid per-frame GC pressure.
     */
    private fun convertI420toArgbBitmap(
        buffer: ByteBuffer,
        width: Int,
        height: Int,
        bitmap: Bitmap
    ) {
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
