package io.rodcone.flutter_meta_wearables_dat

import io.flutter.plugin.common.EventChannel

internal class DeviceSessionStateStreamHandler : EventChannel.StreamHandler {
    private var sink: EventChannel.EventSink? = null
    private var state = "stopped"
    fun send(next: String) { state = next; sink?.success(next) }
    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
        events.success(state)
    }
    override fun onCancel(arguments: Any?) { sink = null }
}
