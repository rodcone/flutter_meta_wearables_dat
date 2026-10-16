import importlib.util
import io
import json
import pathlib
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

SCRIPT = pathlib.Path(__file__).resolve().parents[1] / "capture_stream_investigation.py"
spec = importlib.util.spec_from_file_location("capture", SCRIPT)
capture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(capture)


def line(source, **fields):
    return f'prefix [MWDAT-TRACE{source}] ' + json.dumps(fields)


class CaptureTest(unittest.TestCase):
    def ready_capture(self):
        result = capture.Capture()
        result.consume(line("", event="traceStarted", seq=1, runId="n"))
        result.consume(line("-BRIDGE", event="bridgeReady", seq=1, runId="b"))
        result.consume(line("-DART", event="traceStarted", seq=1, runId="d",
                            bridgeRunId="b", sink="native", nativeReceiptUptimeUs=100))
        return result

    def test_missing_dart_is_not_ready(self):
        result = capture.Capture()
        result.consume(line("", event="traceStarted", seq=1, runId="n"))
        self.assertFalse(result.report()["captureReady"])

    def test_complete_single_run_capture(self):
        result = self.ready_capture()
        self.assertTrue(result.report()["captureReady"])
        self.assertIsNone(result.consume("unrelated device output"))
        self.assertEqual(result.total, 3)

    def test_fallback_console_cannot_pass_native_gate(self):
        result = self.ready_capture()
        result.groups[("dart", "d")][0].pop("nativeReceiptUptimeUs")
        self.assertFalse(result.report()["captureReady"])

    def test_mismatched_bridge_and_multiple_runs_are_rejected(self):
        result = self.ready_capture()
        result.groups[("dart", "d")][0]["bridgeRunId"] = "other"
        self.assertFalse(result.report()["captureReady"])
        result = self.ready_capture()
        result.consume(line("", event="traceStarted", seq=1, runId="another"))
        self.assertFalse(result.report()["captureReady"])

    def test_gaps_duplicates_and_truncation(self):
        result = self.ready_capture()
        for seq in [3, 3, 4]:
            result.consume(line("", event="traceLimitReached" if seq == 4 else "tick",
                                seq=seq, runId="n"))
        report = result.report()
        self.assertFalse(report["captureReady"])
        native = next(g for g in report["groups"] if g["source"] == "native")
        self.assertEqual(native["missingSequences"], [2])
        self.assertEqual(native["duplicateCount"], 1)
        self.assertTrue(native["truncated"])

    def test_malformed_payload_and_large_sequence_are_rejected(self):
        result = self.ready_capture()
        for suffix in ["{", "[]", '{"event":"e","seq":true,"runId":"n"}',
                       '{"event":"e","seq":999999999999,"runId":"n"}']:
            self.assertIsNone(result.consume("[MWDAT-TRACE] " + suffix))
        self.assertEqual(result.report()["malformedRecords"], 4)
        self.assertFalse(result.report()["captureReady"])

    def test_payload_rejection_invalidates_capture(self):
        result = self.ready_capture()
        result.consume(line("-DART", event="tracePayloadRejected", seq=2, runId="d",
                            bridgeRunId="b", nativeReceiptUptimeUs=200))
        self.assertEqual(result.report()["rejectedPayloads"], 1)
        self.assertFalse(result.report()["captureReady"])

    def test_timeout_must_be_finite_and_positive(self):
        for value in ["nan", "inf", "0", "-1"]:
            with self.assertRaises(capture.argparse.ArgumentTypeError):
                capture.positive_seconds(value)

    def run_fake_console(self, source, timeout="1"):
        real_popen = subprocess.Popen
        children = []

        def spawn(command, **kwargs):
            self.assertEqual(command[:3], ["xcrun", "devicectl", "device"])
            self.assertIn("fixture-device", command)
            child = real_popen([sys.executable, "-u", "-c", source], **kwargs)
            children.append(child)
            return child

        with tempfile.TemporaryDirectory() as directory:
            output = pathlib.Path(directory) / "trial"
            argv = [str(SCRIPT), "--device", "fixture-device", "--output", str(output),
                    "--preflight-timeout", timeout]
            with mock.patch.object(sys, "argv", argv), \
                    mock.patch.object(capture.subprocess, "Popen", side_effect=spawn), \
                    mock.patch.object(sys, "stdout", io.StringIO()):
                status = capture.main()
            report = json.loads((output / "summary.json").read_text())
            records = (output / "records.jsonl").read_text()
        self.assertIsNotNone(children[0].poll(), "Owned child must be stopped")
        return status, report, records

    def test_timeout_stops_owned_console_without_device_calls(self):
        status, report, records = self.run_fake_console(
            "import time; print('unrelated private output'); time.sleep(60)", timeout="0.05")
        self.assertEqual(status, 1)
        self.assertEqual(report["outcome"], "preflightTimeout")
        self.assertFalse(report["startupVerified"])
        self.assertEqual(records, "")

    def test_cli_reads_both_sources_but_flags_unexpected_console_exit(self):
        lines = [line("", event="traceStarted", seq=1, runId="n"),
                 line("-BRIDGE", event="bridgeReady", seq=1, runId="b"),
                 line("-DART", event="traceStarted", seq=1, runId="d",
                      bridgeRunId="b", sink="native", nativeReceiptUptimeUs=100)]
        source = "print('unrelated private output'); " + "; ".join(
            "print(" + repr(item) + ")" for item in lines)
        status, report, records = self.run_fake_console(source)
        self.assertEqual(status, 1)
        self.assertTrue(report["startupVerified"])
        self.assertEqual(report["outcome"], "consoleExited")
        self.assertEqual(len(records.splitlines()), 3)
        self.assertNotIn("private output", records)

    def test_existing_output_cannot_be_overwritten(self):
        with tempfile.TemporaryDirectory() as directory:
            with mock.patch.object(sys, "argv", [str(SCRIPT), "--device", "fixture",
                                                "--output", directory]), \
                    mock.patch.object(capture.subprocess, "Popen") as spawn:
                with self.assertRaises(FileExistsError):
                    capture.main()
                spawn.assert_not_called()

    def test_partial_tagged_line_at_eof_is_incomplete(self):
        status, report, records = self.run_fake_console(
            "import sys; sys.stdout.write('[MWDAT-TRACE] {')")
        self.assertEqual(status, 1)
        self.assertEqual(report["malformedRecords"], 1)
        self.assertEqual(records, "")

    def test_integrity_failure_after_ready_stops_capture(self):
        lines = [line("", event="traceStarted", seq=1, runId="n"),
                 line("-BRIDGE", event="bridgeReady", seq=1, runId="b"),
                 line("-DART", event="traceStarted", seq=1, runId="d",
                      bridgeRunId="b", sink="native", nativeReceiptUptimeUs=100)]
        source = "import time; " + "; ".join("print(" + repr(item) + ")" for item in lines)
        source += "; time.sleep(0.1); print(" + repr(
            line("", event="tick", seq=3, runId="n")) + "); time.sleep(60)"
        status, report, _ = self.run_fake_console(source)
        self.assertEqual(status, 1)
        self.assertTrue(report["startupVerified"])
        self.assertEqual(report["outcome"], "captureInvalid")


if __name__ == "__main__":
    unittest.main()
