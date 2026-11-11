// Host-only SDK doubles. Real SDK signatures are checked by the iOS build.
public protocol AnyListenerToken: Sendable {
  func cancel() async
}

public final class TestToken: AnyListenerToken, @unchecked Sendable {
  let cancelBody: () -> Void
  public init(_ body: @escaping () -> Void) { cancelBody = body }
  public func cancel() async { cancelBody() }
}

public final class TestPublisher<Value>: @unchecked Sendable {
  private var callbacks: [Int: @Sendable (Value) -> Void] = [:]
  private var nextId = 0
  public init() {}
  public func listen(_ callback: @escaping @Sendable (Value) -> Void) -> any AnyListenerToken {
    nextId += 1
    let id = nextId
    callbacks[id] = callback
    return TestToken { self.callbacks[id] = nil }
  }
  public func send(_ value: Value) {
    for callback in callbacks.values { callback(value) }
  }
}
