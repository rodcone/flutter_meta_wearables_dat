import Foundation

var checks = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
  precondition(condition(), message); checks += 1
}
var now = 100.0
func tracker() -> StreamDiagnosticsTracker { StreamDiagnosticsTracker(clock: { now }) }
let t = tracker()
now += 30
check(!t.pollFirstFrame(), "Starting is not eligible")
t.stateChanged(streaming: true)
for _ in 0..<9 { now += 1; check(!t.pollFirstFrame(), "No early timeout") }
// Repeated reads must not alter the deadline.
for _ in 0..<10 { _ = t.snapshot() }
now += 1
check(t.pollFirstFrame(), "Deadline at ten eligible seconds")
check(!t.pollFirstFrame(), "No duplicate")
t.stateChanged(streaming: false); now += 20; t.stateChanged(streaming: true)
now += 1
check(!t.pollFirstFrame(), "Pause/resume does not duplicate")
t.noteArrival()
check(t.snapshot()["stallReason"] == nil, "Late frame clears first-frame stall")
check(t.snapshot()["waitingForFirstFrame"] as? Bool == false, "Late frame disarms wait")
let p = tracker(); p.stateChanged(streaming: true)
for _ in 0..<4 { now += 1; _ = p.pollFirstFrame() }
p.stateChanged(streaming: false); now += 100
check(!p.pollFirstFrame(), "Paused time excluded")
p.stateChanged(streaming: true)
now += 50; check(!p.pollFirstFrame(), "Suspension gap excluded")
for _ in 0..<5 { now += 1; check(!p.pollFirstFrame(), "Remaining wait") }
now += 1; check(p.pollFirstFrame(), "Resumes remaining wait")
let r = tracker(); r.stateChanged(streaming: true)
for _ in 0..<4 { now += 0.5; r.noteArrival(); r.noteSubmission(); check(!r.pollFirstFrame(), "2fps healthy") }
check(r.snapshot()["framesReceived"] as? Int == 4, "Arrival count")
check(r.snapshot()["framesSubmitted"] as? Int == 4, "Submission count")
now += 3
check(r.snapshot()["receivedFps"] as? Double == 0, "Rates decay without arrivals")
let age = r.snapshot()["timeSinceLastSubmissionUs"] as? Int
r.resumeGrace()
check(r.snapshot()["timeSinceLastSubmissionUs"] as? Int == age, "Grace does not fake submissions")
r.setStallReason("textureSubmissionsStopped"); r.noteArrival()
check(r.snapshot()["stallReason"] as? String == "textureSubmissionsStopped", "Arrival cannot clear submission fault")
r.noteSubmission(); check(r.snapshot()["stallReason"] == nil, "Submission recovers")
let replacement = tracker()
r.noteArrival()
check(replacement.sessionId != r.sessionId, "New identity")
check(replacement.snapshot()["framesReceived"] as? Int == 0, "Old callback isolated")
check(StreamDiagnosticsTracker.deliveryStall(sinceArrival: 1.5, sinceSubmission: 6, background: false) == nil, "Exact boundaries healthy")
check(StreamDiagnosticsTracker.deliveryStall(sinceArrival: 1.501, sinceSubmission: 0, background: false) == "sdkFramesStopped", "SDK gap")
check(StreamDiagnosticsTracker.deliveryStall(sinceArrival: 0.5, sinceSubmission: 6.001, background: false) == "textureSubmissionsStopped", "Texture gap")
check(StreamDiagnosticsTracker.deliveryStall(sinceArrival: 0.5, sinceSubmission: 100, background: true) == nil, "Background requires no texture")
check(StreamDiagnosticsTracker.deliveryStall(sinceArrival: 2, sinceSubmission: 100, background: true) == "sdkFramesStopped", "Background still requires arrivals")
let g = tracker(); g.stateChanged(streaming: true)
for _ in 0..<9 { now += 1; _ = g.pollFirstFrame() }
g.resumeGrace()
now += 1; check(!g.pollFirstFrame(), "Foreground grace excluded")
check(g.snapshot()["firstFrameWaitUs"] as? Int == 9_000_000, "Grace preserves wait")
now += 1; check(!g.pollFirstFrame(), "Only half a second eligible after grace")
now += 0.5; check(g.pollFirstFrame(), "Deadline after grace")
print("Stream diagnostics: \(checks) assertions passed")
