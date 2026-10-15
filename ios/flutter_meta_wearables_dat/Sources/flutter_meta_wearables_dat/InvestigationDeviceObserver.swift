import Foundation
import MWDATCore

/// Optional trace ownership only; never changes SDK state or awaits cancellation
/// in the session/recovery path. Parent IDs are trace UUIDs, not device IDs.
final class InvestigationDeviceObserver: @unchecked Sendable {
  private let lock = NSLock()
  private var active = true
  private var tokens: [any AnyListenerToken] = []
  private let parentId: String

  init?(device: Device?, parentId: String) {
    guard StreamInvestigationTrace.enabled else { return nil }
    self.parentId = parentId
    guard let device else {
      StreamInvestigationTrace.record("deviceObservationUnavailable", ["parentId": parentId])
      return nil
    }
    StreamInvestigationTrace.record("deviceSnapshot", [
      "parentId": parentId,
      "linkState": String(describing: device.linkState),
      "donState": String(describing: device.donState),
      "hingeState": String(describing: device.hingeState),
      "compatibility": String(describing: device.compatibility()),
      "batteryLevel": device.batteryLevel as Any? ?? NSNull(),
      "thermalLevel": String(describing: device.thermalLevel)
    ])
    tokens.append(device.addLinkStateListener { [weak self] state in
      self?.record("deviceLinkChanged", ["linkState": String(describing: state)])
    })
    tokens.append(device.addDeviceStateListener { [weak self] state in
      self?.record("deviceSnapshot", [
        "linkState": String(describing: state.linkState),
        "donState": String(describing: state.donState),
        "hingeState": String(describing: state.hingeState),
        "compatibility": String(describing: state.compatibility),
        "batteryLevel": state.batteryLevel as Any? ?? NSNull(),
        "thermalLevel": String(describing: state.thermalLevel)
      ])
    })
  }

  private func record(_ event: String, _ fields: [String: Any]) {
    lock.lock()
    defer { lock.unlock() }
    guard active else { return }
    var fields = fields
    fields["parentId"] = parentId
    StreamInvestigationTrace.record(event, fields)
  }

  func stop() {
    lock.lock()
    guard active else { lock.unlock(); return }
    active = false
    let oldTokens = tokens
    tokens = []
    lock.unlock()
    // Invalidate first: cancel() is asynchronous and can have queued callbacks.
    Task { for token in oldTokens { await token.cancel() } }
  }

  deinit { stop() }

  static func errorFields(
    _ error: DeviceSessionError, parentId: String?, origin: String,
    sessionState: DeviceSessionState?
  ) -> [String: Any] {
    var fields: [String: Any] = [
      "parentId": parentId as Any? ?? NSNull(), "errorOrigin": origin,
      "deviceSessionState": sessionState.map { String(describing: $0) } as Any? ?? NSNull()
    ]
    fields.merge(StreamInvestigationTrace.boundedText(error.description, key: "sdkDescription")) { _, new in new }
    if case .unexpectedError(let description) = error {
      fields.merge(StreamInvestigationTrace.boundedText(description, key: "unexpectedDescription")) { _, new in new }
    }
    return fields
  }
}
