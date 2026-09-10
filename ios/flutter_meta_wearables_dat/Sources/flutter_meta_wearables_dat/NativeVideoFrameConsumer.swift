import AVFoundation
import Foundation

/// Receives raw DAT frames without copying their pixels through Flutter.
///
/// Consumers must not retain the sample buffer after this callback returns.
public protocol MetaWearablesDatNativeVideoFrameConsumer: AnyObject {
  func metaWearablesDatDidOutput(sampleBuffer: CMSampleBuffer)
}

/// Process-local registry used by optional sibling Flutter plugins.
public final class MetaWearablesDatNativeVideoFrameConsumers: NSObject {
  private static let lock = NSLock()
  private static let consumers = NSHashTable<AnyObject>.weakObjects()

  public static func add(_ consumer: MetaWearablesDatNativeVideoFrameConsumer) {
    lock.lock()
    consumers.add(consumer)
    lock.unlock()
  }

  public static func remove(_ consumer: MetaWearablesDatNativeVideoFrameConsumer) {
    lock.lock()
    consumers.remove(consumer)
    lock.unlock()
  }

  static func dispatch(_ sampleBuffer: CMSampleBuffer) {
    lock.lock()
    let snapshot = consumers.allObjects
    lock.unlock()
    snapshot.forEach {
      ($0 as? MetaWearablesDatNativeVideoFrameConsumer)?
        .metaWearablesDatDidOutput(sampleBuffer: sampleBuffer)
    }
  }
}
