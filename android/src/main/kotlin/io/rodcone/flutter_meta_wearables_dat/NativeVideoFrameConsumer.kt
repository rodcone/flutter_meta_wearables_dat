package io.rodcone.flutter_meta_wearables_dat

import java.nio.ByteBuffer
import java.util.concurrent.CopyOnWriteArraySet

/**
 * A synchronous, native-only view of a DAT video frame.
 *
 * Consumers must finish reading [buffer] before [onVideoFrame] returns. The
 * buffer is a read-only duplicate whose position is independent from DAT's
 * source buffer, but its backing memory is owned by the DAT SDK and may be
 * reused after the callback.
 */
public data class NativeVideoFrame(
        val buffer: ByteBuffer,
        val width: Int,
        val height: Int,
        val presentationTimeUs: Long,
        val isCompressed: Boolean,
)

/** Receives frames without routing their bytes through a Flutter event channel. */
public fun interface NativeVideoFrameConsumer {
    public fun onVideoFrame(frame: NativeVideoFrame)
}

/**
 * Process-local registry for optional native encoders, recorders, and vision
 * processors hosted by sibling Flutter plugins.
 */
public object NativeVideoFrameConsumers {
    private val consumers = CopyOnWriteArraySet<NativeVideoFrameConsumer>()

    @JvmStatic
    public fun add(consumer: NativeVideoFrameConsumer) {
        consumers.add(consumer)
    }

    @JvmStatic
    public fun remove(consumer: NativeVideoFrameConsumer) {
        consumers.remove(consumer)
    }

    internal fun dispatch(frame: com.meta.wearable.dat.camera.types.VideoFrame) {
        if (consumers.isEmpty()) return
        val nativeFrame =
                NativeVideoFrame(
                        buffer = frame.buffer.asReadOnlyBuffer(),
                        width = frame.width,
                        height = frame.height,
                        presentationTimeUs = frame.presentationTimeUs,
                        isCompressed = frame.isCompressed,
                )
        consumers.forEach { consumer -> consumer.onVideoFrame(nativeFrame) }
    }
}
