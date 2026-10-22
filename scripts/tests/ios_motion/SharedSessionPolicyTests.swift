@main
struct SharedSessionPolicyTests {
  static func main() {
    // A camera screen can clean itself up while standalone Motion is starting,
    // and vice versa. Neither idle stop may cancel or tear down that new session.
    precondition(SharedSessionPolicy.stopAdmission(
      stopping: .camera, starting: .motion, isAttached: false
    ) == .alreadyIdle)
    precondition(SharedSessionPolicy.stopAdmission(
      stopping: .motion, starting: .camera, isAttached: false
    ) == .alreadyIdle)

    // An attached capability must wait for its sibling's in-flight attachment:
    // otherwise its stop could mistake itself for the parent's last owner.
    precondition(SharedSessionPolicy.stopAdmission(
      stopping: .camera, starting: .motion, isAttached: true
    ) == .waitForSiblingStart)
    precondition(SharedSessionPolicy.stopAdmission(
      stopping: .motion, starting: .camera, isAttached: true
    ) == .waitForSiblingStart)

    // Once attachment finishes, the stop can proceed without cancelling a start.
    // A stop of the *same* capability must proceed while it starts, including
    // before the SDK has supplied its capability object.
    for capability in [SharedSessionPolicy.Capability.camera, .motion] {
      for isAttached in [false, true] {
        precondition(SharedSessionPolicy.stopAdmission(
          stopping: capability, starting: nil, isAttached: isAttached
        ) == .proceed)
        precondition(SharedSessionPolicy.stopAdmission(
          stopping: capability, starting: capability, isAttached: isAttached
        ) == .proceed)
      }
    }

    // Motion pinned A, then camera auto-selects: repeat camera starts must reuse A.
    precondition(SharedSessionPolicy.canReuseDevice(
      requestedId: nil, sessionDeviceId: "A", pinnedDeviceId: "A"
    ))
    // Motion auto-selected A, then camera explicitly selects A: repeat calls
    // must succeed even though the shared selector still has no explicit pin.
    precondition(SharedSessionPolicy.canReuseDevice(
      requestedId: "A", sessionDeviceId: "A", pinnedDeviceId: nil
    ))
    // Explicitly selecting B must never reuse the active session on A.
    precondition(!SharedSessionPolicy.canReuseDevice(
      requestedId: "B", sessionDeviceId: "A", pinnedDeviceId: nil
    ))
    // The actual device takes precedence over a stale selector pin.
    precondition(!SharedSessionPolicy.canReuseDevice(
      requestedId: "B", sessionDeviceId: "A", pinnedDeviceId: "B"
    ))
    precondition(SharedSessionPolicy.canReuseDevice(
      requestedId: "A", sessionDeviceId: nil, pinnedDeviceId: "A"
    ))
    precondition(!SharedSessionPolicy.canReuseDevice(
      requestedId: "A", sessionDeviceId: nil
    ))

    print("Shared session policy: idle sibling stops, pending attachment, own-start cancellation, and shared device reuse passed")
  }
}
