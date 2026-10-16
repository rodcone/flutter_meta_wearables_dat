import Foundation
import MWDATCore

let device = Device()
var observer = InvestigationDeviceObserver(device: device, parentId: "parent-fixture")
if StreamInvestigationTrace.enabled {
  precondition(observer != nil)
  device.linkCallback?(.disconnected)
  var state = DeviceState()
  state.donState = .doffed
  state.hingeState = .closed
  device.stateCallback?(state)
  let fields = InvestigationDeviceObserver.errorFields(
    .unexpectedError(description: "Device unavailable"), parentId: "parent-fixture",
    origin: "errorStream", sessionState: .starting)
  precondition(fields["unexpectedDescription"] as? String == "Device unavailable")
  precondition(fields["unexpectedDescriptionTruncated"] as? Bool == false)
  StreamInvestigationTrace.record("deviceErrorReceived", fields)
  let large = InvestigationDeviceObserver.errorFields(
    .unexpectedError(description: String(repeating: "📷", count: 400)),
    parentId: nil, origin: "ensureSessionStarted", sessionState: nil)
  precondition((large["sdkDescription"] as! String).utf8.count <= 1_024)
  precondition(large["sdkDescriptionTruncated"] as? Bool == true)
  precondition(large["parentId"] is NSNull)
  let boundary = StreamInvestigationTrace.boundedText(
    String(repeating: "x", count: 1_023) + "📷", key: "text")
  precondition((boundary["text"] as! String).utf8.count == 1_023)
  precondition(boundary["textTruncated"] as? Bool == true)
  precondition(StreamInvestigationTrace.boundedText(String(repeating: "x", count: 1_024),
    key: "text")["textTruncated"] as? Bool == false)
  let typed = InvestigationDeviceObserver.errorFields(.noEligibleDevice,
    parentId: nil, origin: "addCamera", sessionState: .stopped)
  precondition(typed["unexpectedDescription"] == nil)
  observer?.stop()
  observer?.stop()
  // Simulate callbacks already queued by the SDK when cancellation began.
  device.linkCallback?(.connected)
  device.stateCallback?(DeviceState())
  observer = nil
  let deadline = Date().addingTimeInterval(2)
  while (device.linkToken.cancellations == 0 || device.stateToken.cancellations == 0), Date() < deadline {
    Thread.sleep(forTimeInterval: 0.001)
  }
  precondition(device.linkToken.cancellations == 1 && device.stateToken.cancellations == 1)
  let releasedDevice = Device()
  var releasedObserver = InvestigationDeviceObserver(device: releasedDevice, parentId: "released")
  precondition(releasedObserver != nil)
  releasedObserver = nil
  releasedDevice.linkCallback?(.disconnected)
  let releaseDeadline = Date().addingTimeInterval(2)
  while (releasedDevice.linkToken.cancellations == 0 || releasedDevice.stateToken.cancellations == 0), Date() < releaseDeadline {
    Thread.sleep(forTimeInterval: 0.001)
  }
  precondition(releasedDevice.linkToken.cancellations == 1 && releasedDevice.stateToken.cancellations == 1)
  precondition(InvestigationDeviceObserver(device: nil, parentId: "missing") == nil)
} else {
  precondition(observer == nil)
  precondition(device.linkCallback == nil && device.stateCallback == nil)
}
