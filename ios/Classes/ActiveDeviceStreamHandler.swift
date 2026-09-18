import Flutter
import MWDATCore

/// Stream handler for active device availability updates from the DAT SDK.
class ActiveDeviceStreamHandler: NSObject, FlutterStreamHandler {
    private var activeDeviceTask: Task<Void, Never>?
    private var deviceSelector: AutoDeviceSelector?
    private var linkStateListenerToken: AnyListenerToken?

    func onListen(withArguments _: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        Task { @MainActor in
            // Create AutoDeviceSelector to monitor device availability
            self.deviceSelector = AutoDeviceSelector(wearables: Wearables.shared)

            // Helper function to check if device is actually active (connected)
            @MainActor
            func checkDeviceActive() {
                guard let deviceSelector = self.deviceSelector,
                      let deviceId = deviceSelector.activeDevice
                else {
                    NSLog("[MWDAT:ActiveDevice] checkDeviceActive — no selector or no active device, emitting false")
                    events(false)
                    return
                }

                if let device = Wearables.shared.deviceForIdentifier(deviceId) {
                    let isActive = device.linkState == .connected
                    NSLog("[MWDAT:ActiveDevice] checkDeviceActive — device=%@, linkState=%@, emitting %@", deviceId, "\(device.linkState)", isActive ? "true" : "false")
                    events(isActive)
                } else {
                    NSLog("[MWDAT:ActiveDevice] checkDeviceActive — device %@ not found in Wearables, emitting false", deviceId)
                    events(false)
                }
            }

            NSLog("[MWDAT:ActiveDevice] onListen — checking initial state")
            checkDeviceActive()

            // Listen to device availability changes
            guard let deviceSelector = self.deviceSelector else {
                return
            }

            self.activeDeviceTask = Task { @MainActor in
                for await deviceId in deviceSelector.activeDeviceStream() {
                    if let deviceId = deviceId,
                       let device = Wearables.shared.deviceForIdentifier(deviceId)
                    {
                        let isActive = device.linkState == .connected
                        NSLog("[MWDAT:ActiveDevice] activeDeviceStream — device=%@, linkState=%@, emitting %@", deviceId, "\(device.linkState)", isActive ? "true" : "false")
                        events(isActive)

                        await self.linkStateListenerToken?.cancel()
                        self.linkStateListenerToken = device.addLinkStateListener { [weak self] linkState in
                            Task { @MainActor in
                                let isActive = linkState == .connected
                                NSLog("[MWDAT:ActiveDevice] linkStateListener — device=%@, linkState=%@, emitting %@", deviceId, "\(linkState)", isActive ? "true" : "false")
                                events(isActive)
                            }
                        }
                    } else {
                        NSLog("[MWDAT:ActiveDevice] activeDeviceStream — deviceId=%@, emitting false", deviceId.map { $0 } ?? "nil")
                        await self.linkStateListenerToken?.cancel()
                        events(false)
                    }
                }
            }
        }

        return nil
    }

    func onCancel(withArguments _: Any?) -> FlutterError? {
        Task { @MainActor in
            self.activeDeviceTask?.cancel()
            self.activeDeviceTask = nil
            await self.linkStateListenerToken?.cancel()
            self.linkStateListenerToken = nil
            self.deviceSelector = nil
        }
        return nil
    }
}
