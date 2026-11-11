import MWDATCore

public enum MotionSamplingRate { case hz5, hz10, hz15, hz24, hz30, hz60 }
public enum MotionState { case stopped, starting, started, stopping }
public enum MotionSource { case glasses, neuralBand, unknown }
public enum MotionError {
  case sensorUnavailable, capabilityClosed, deviceDisconnected
  public var description: String { String(describing: self) }
}
public struct Vector3 {
  public let x: Float, y: Float, z: Float
  public init(x: Float, y: Float, z: Float) { self.x = x; self.y = y; self.z = z }
}
public struct Quaternion {
  public let x: Float, y: Float, z: Float, w: Float
  public init(x: Float, y: Float, z: Float, w: Float) {
    self.x = x; self.y = y; self.z = z; self.w = w
  }
}
public struct MotionSample {
  public let timestampNs: Int64
  public let accelerometer: Vector3?, gyroscope: Vector3?, magnetometer: Vector3?
  public let orientation: Quaternion?
  public let source: MotionSource
  public init(timestampNs: Int64, accelerometer: Vector3? = nil,
              gyroscope: Vector3? = nil, magnetometer: Vector3? = nil,
              orientation: Quaternion? = nil, source: MotionSource = .unknown) {
    self.timestampNs = timestampNs; self.accelerometer = accelerometer
    self.gyroscope = gyroscope; self.magnetometer = magnetometer
    self.orientation = orientation; self.source = source
  }
}
public final class Motion {
  public var state = MotionState.stopped
  public let statePublisher = TestPublisher<MotionState>()
  public let errorPublisher = TestPublisher<MotionError>()
  public let samples: AsyncStream<MotionSample>
  public let continuation: AsyncStream<MotionSample>.Continuation
  public private(set) var starts = 0
  public private(set) var stops = 0
  public init() {
    (samples, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(256))
  }
  public func start() { starts += 1; state = .started; statePublisher.send(state) }
  public func stop() { stops += 1; state = .stopped; statePublisher.send(state) }
}
