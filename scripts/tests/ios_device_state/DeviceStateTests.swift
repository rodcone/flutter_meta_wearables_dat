import Foundation
import MWDATCore

@MainActor
final class Fixture {
  let sdk = Wearables()
  let selector = AutoDeviceSelector()
  let a = Device()
  let b = Device()
  var values: [[String: Any]] = []
  lazy var handler = DeviceStateStreamHandler(deviceSelectorProvider: { self.selector })
  init() { Wearables.shared = sdk; sdk.devices = ["a": a, "b": b] }
  func listen() { _ = handler.onListen(withArguments: nil) { self.values.append($0 as! [String: Any]) } }
  var last: [String: Any] { values.last! }
  func stop() { handler.dispose() }
}

@main
struct Tests {
  @MainActor static func wait(_ condition: () -> Bool, _ message: String = "Timed out") async {
    for _ in 0..<500 {
      if condition() { return }
      try! await Task.sleep(nanoseconds: 1_000_000)
    }
    fatalError(message)
  }
  static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    if !value() { fatalError(message) }
  }
  @MainActor static func settle() async {
    for _ in 0..<8 { await Task.yield() }
    try! await Task.sleep(nanoseconds: 2_000_000)
  }

  @MainActor static func main() async {
    var passed = 0
    do {
      let f = Fixture(); defer { f.stop() }; f.listen()
      await wait({ f.last["batteryLevel"] as? Int == 72 })
      expect(f.last["deviceId"] as? String == "a", "identity")
      expect(f.last["linkState"] as? String == "connected", "link")
      expect(f.last["compatibility"] as? String == "compatible", "compatibility")
      expect(f.last["thermalLevel"] as? Int == 3, "thermal")
      expect(f.last["chargingState"] as? String == "notCharging", "charging")
      expect(f.last["donState"] as? String == "donned", "worn")
      expect(f.last["hingeState"] as? String == "open", "hinges")
      f.a.state.batteryLevel = 71; f.a.state.chargingState = .charging
      f.a.state.donState = .doffed; f.a.state.hingeState = .closed; f.a.emit()
      await wait({ f.last["batteryLevel"] as? Int == 71 })
      expect(f.last["chargingState"] as? String == "charging", "charging update")
      expect(f.last["donState"] as? String == "doffed", "wear update")
      expect(f.last["hingeState"] as? String == "closed", "hinge update")
      passed += 1
    }
    await settle()
    do {
      let f = Fixture(); defer { f.stop() }; f.listen()
      await wait({ f.last["batteryLevel"] as? Int == 72 })
      for battery: Int? in [nil, -1, 0, 1, 100, 101] {
        f.a.state.batteryLevel = battery; f.a.emit(); await settle()
        if let battery, (0...100).contains(battery) {
          expect(f.last["batteryLevel"] as? Int == battery, "valid battery including zero")
        } else { expect(f.last["batteryLevel"] is NSNull, "unknown battery") }
      }
      for (index, level) in ThermalLevel.allCases.enumerated() {
        f.a.state.thermalLevel = level; f.a.emit(); await settle()
        expect(f.last["thermalLevel"] as? Int == index, "thermal wire code")
      }
      f.a.state.chargingState = .unknown; f.a.state.donState = .unknown
      f.a.state.hingeState = .unknown; f.a.state.compatibility = .sdkUpdateRequired
      f.a.emit(); await settle()
      expect(f.last["chargingState"] as? String == "unknown", "unknown charge")
      expect(f.last["donState"] as? String == "unknown", "unknown worn")
      expect(f.last["hingeState"] as? String == "unknown", "unknown hinge")
      expect(f.last["compatibility"] as? String == "sdkUpdateRequired", "SDK compatibility")
      passed += 1
    }
    await settle()
    do {
      let f = Fixture(); defer { f.stop() }; f.selector.activeDevice = nil; f.listen()
      await wait({ !f.selector.continuations.isEmpty })
      expect(f.last["deviceId"] is NSNull, "empty initial state")
      f.sdk.devices.removeValue(forKey: "a"); f.selector.select("a"); await settle()
      expect(f.last["deviceId"] as? String == "a", "known ID with missing metadata")
      expect(f.last["batteryLevel"] is NSNull, "missing metadata remains unknown")
      f.sdk.devices["a"] = f.a; f.sdk.announceDevices()
      await wait({ f.last["batteryLevel"] as? Int == 72 })
      f.selector.select("a"); f.handler.restartMonitoring(); await settle()
      expect(f.a.listeners.count == 1, "same-device replay must not duplicate listeners")
      passed += 1
    }
    await settle()
    do {
      let f = Fixture(); defer { f.stop() }; f.listen()
      await wait({ f.last["batteryLevel"] as? Int == 72 })
      for link in [LinkState.connecting, .disconnected] {
        f.a.state.linkState = link; f.a.emit(); await settle()
        expect(f.last["deviceId"] as? String == "a", "disconnected identity")
        expect(f.last["batteryLevel"] is NSNull, "stale battery cleared")
        expect(f.last["thermalLevel"] as? Int == 0, "stale thermal cleared")
        expect(f.last["donState"] as? String == "unknown", "stale worn cleared")
      }
      f.selector.select(nil); await settle()
      expect(f.last["deviceId"] is NSNull, "selector loss")
      f.a.state.linkState = .connected; f.a.state.batteryLevel = 44
      f.selector.select("a"); await wait({ f.last["batteryLevel"] as? Int == 44 })
      passed += 1
    }
    await settle()
    do {
      let f = Fixture(); defer { f.stop() }; f.listen()
      await wait({ f.last["batteryLevel"] as? Int == 72 })
      f.b.state.batteryLevel = 30; f.selector.select("b")
      await wait({ f.last["deviceId"] as? String == "b" && f.last["batteryLevel"] as? Int == 30 })
      f.a.state.batteryLevel = 99; f.a.emit(); await settle()
      expect(f.last["batteryLevel"] as? Int == 30, "old-device callback rejected")
      _ = f.handler.onCancel(withArguments: nil); let count = f.values.count
      f.a.emit(); f.b.emit(); await settle()
      expect(f.values.count == count, "cancelled listener is quiet")
      f.listen(); await wait({ f.b.listeners.count == 2 }); await settle()
      let old = f.b.listeners[0]; var stale = DeviceState(); stale.batteryLevel = 98
      old(stale); await settle()
      expect(f.last["batteryLevel"] as? Int == 30, "old-listener callback rejected")
      passed += 1
    }
    await settle()
    do {
      let f = Fixture(); defer { f.stop() }; f.listen()
      await wait({ f.last["batteryLevel"] as? Int == 72 })
      f.sdk.devices.removeValue(forKey: "a"); f.sdk.announceDevices(); await settle()
      f.a.emit(); await settle()
      expect(f.last["deviceId"] is NSNull, "device removal clears pinned state")
      f.selector.select("a"); await settle()
      expect(f.last["deviceId"] is NSNull, "late selector replay cannot restore a removed device")
      f.a.state.batteryLevel = 23; f.sdk.devices["a"] = f.a; f.sdk.announceDevices()
      await wait({ f.last["batteryLevel"] as? Int == 23 }); passed += 1
    }
    await settle()
    do {
      let f = Fixture(); defer { f.stop() }; f.listen()
      await wait({ f.a.listeners.count == 1 }); await settle()
      let old = f.a.listeners[0]; f.a.state.batteryLevel = 21
      f.handler.restartMonitoring(force: true)
      await wait({ f.last["batteryLevel"] as? Int == 21 })
      old(DeviceState()); await settle()
      expect(f.last["batteryLevel"] as? Int == 21, "forced restart invalidates old listener")
      passed += 1
    }
    await settle()
    do {
      let f = Fixture(); defer { f.stop() }; f.sdk.registrationState = .available; f.listen()
      await wait({ !f.sdk.continuations.isEmpty })
      expect(f.a.listeners.isEmpty, "no observation before registration")
      f.sdk.registration(.registered); await wait({ f.last["batteryLevel"] as? Int == 72 })
      f.sdk.registration(.available); f.a.emit(); await settle()
      expect(f.last["deviceId"] is NSNull, "unregister clears stale state")
      expect(f.a.tokens[0].cancelled, "unregister cancels device listener")
      f.a.state.batteryLevel = 55; f.sdk.registration(.registered)
      await wait({ f.last["batteryLevel"] as? Int == 55 }); passed += 1
    }
    await settle()
    do {
      let f = Fixture(); f.listen(); await wait({ f.last["batteryLevel"] as? Int == 72 })
      f.handler.dispose(); let count = f.values.count
      f.a.emit(); f.selector.select("b"); f.listen(); f.handler.restartMonitoring(force: true)
      await settle(); expect(f.values.count == count, "dispose is terminal and quiet")
      expect(f.a.tokens[0].cancelled, "dispose cancels token"); passed += 1
    }
    await settle()
    do {
      let f = Fixture(); defer { f.stop() }; f.listen()
      await wait({ f.last["batteryLevel"] as? Int == 72 })
      f.selector.finish(); await settle()
      expect(f.last["deviceId"] is NSNull, "ended SDK selector clears readout")
      f.handler.restartMonitoring(); await wait({ f.a.listeners.count == 2 })
      await wait({ f.last["batteryLevel"] as? Int == 72 }); passed += 1
    }
    print("iOS Device State: \(passed) scenarios passed")
  }
}
