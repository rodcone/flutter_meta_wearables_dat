/// Decisions that keep camera and Motion operations scoped to their owner.
/// The caller applies these decisions on the main actor before mutating a
/// shared device session or cancelling a pending start.
enum SharedSessionPolicy {
  enum Capability {
    case camera
    case motion
  }

  enum StopAdmission {
    /// Continue with this capability's stop, including cancelling its own start.
    case proceed
    /// The requested capability is absent; leave the sibling's start untouched.
    case alreadyIdle
    /// Let the sibling finish attaching before deciding whether to end its parent.
    case waitForSiblingStart
  }

  static func stopAdmission(
    stopping: Capability,
    starting: Capability?,
    isAttached: Bool
  ) -> StopAdmission {
    guard let starting, starting != stopping else { return .proceed }
    return isAttached ? .waitForSiblingStart : .alreadyIdle
  }

  /// Auto-selection reuses an existing session. Explicit selection must match
  /// the actual device; the selector's pin is only a fallback before resolution.
  static func canReuseDevice(
    requestedId: String?,
    sessionDeviceId: String?,
    pinnedDeviceId: String? = nil
  ) -> Bool {
    guard let requestedId else { return true }
    return requestedId == (sessionDeviceId ?? pinnedDeviceId)
  }
}
