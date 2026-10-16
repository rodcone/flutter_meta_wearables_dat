#!/usr/bin/env python3
"""Collect only tagged JSON from an explicitly selected iPhone's app console.

No build/install, device discovery, lock, camera control or whole-device syslog.
Ctrl-C terminates the owned console process; relaunch normally after testing.
"""
import argparse
import json
import math
import re
import selectors
import subprocess
import time
from pathlib import Path


TAG = re.compile(r"\[MWDAT-TRACE(?P<source>-DART|-BRIDGE)?\] ")
MAX_LINE_BYTES = 64 * 1024


def parse_record(line):
    match = TAG.search(line)
    if not match:
        return None
    entry = json.loads(line[match.end():])
    if not isinstance(entry, dict):
        raise ValueError("Tagged record must be an object")
    if (not isinstance(entry.get("event"), str)
            or not isinstance(entry.get("runId"), str)
            or type(entry.get("seq")) is not int
            or not 1 <= entry["seq"] <= 2001):
        raise ValueError("Invalid trace identity or sequence")
    return {"source": (match["source"] or "native").lstrip("-").lower(),
            "record": entry}


class Capture:
    def __init__(self):
        self.groups = {}
        self.malformed = 0
        self.rejected_payloads = 0
        self.total = 0

    def consume(self, line):
        try:
            parsed = parse_record(line)
        except (ValueError, TypeError):
            self.malformed += 1
            return None
        if parsed is None:
            return None
        entry = parsed["record"]
        key = (parsed["source"], entry["runId"])
        self.groups.setdefault(key, []).append(entry)
        self.total += 1
        self.rejected_payloads += entry["event"] == "tracePayloadRejected"
        return parsed

    def report(self):
        groups = []
        for (source, run), entries in self.groups.items():
            seqs = [entry["seq"] for entry in entries]
            unique = set(seqs)
            groups.append({
                "source": source, "runId": run, "records": len(entries),
                "firstSequence": min(seqs), "lastSequence": max(seqs),
                "missingSequences": sorted(set(range(1, max(seqs) + 1)) - unique),
                "duplicateCount": len(seqs) - len(unique),
                "outOfOrder": seqs != sorted(seqs),
                "truncated": any(e["event"] == "traceLimitReached" for e in entries),
            })
        source_runs = {source: [key for key in self.groups if key[0] == source]
                       for source in ("native", "bridge", "dart")}
        clean = not (self.malformed or self.rejected_payloads) and all(
            not (g["missingSequences"] or g["duplicateCount"] or g["truncated"]
                 or g["outOfOrder"]) for g in groups)
        single_runs = all(len(runs) == 1 for runs in source_runs.values())
        ready = False
        if clean and single_runs:
            native = self.groups[source_runs["native"][0]]
            bridge = self.groups[source_runs["bridge"][0]]
            dart = self.groups[source_runs["dart"][0]]
            bridge_run = source_runs["bridge"][0][1]
            ready = (native[0]["event"] == "traceStarted"
                     and bridge[0]["event"] == "bridgeReady"
                     and dart[0]["event"] == "traceStarted"
                     and dart[0].get("sink") == "native"
                     and all(e.get("bridgeRunId") == bridge_run
                             and type(e.get("nativeReceiptUptimeUs")) is int
                             for e in dart))
        return {"captureReady": ready, "malformedRecords": self.malformed,
                "rejectedPayloads": self.rejected_payloads, "groups": groups,
                "limitation": "No sequence check can detect missing trailing records."}


def positive_seconds(value):
    seconds = float(value)
    if not math.isfinite(seconds) or seconds <= 0:
        raise argparse.ArgumentTypeError("Timeout must be finite and positive")
    return seconds


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True, help="Explicit iPhone UDID")
    parser.add_argument("--output", required=True, type=Path, help="New output directory")
    parser.add_argument("--preflight-timeout", type=positive_seconds, default=30)
    args = parser.parse_args()
    # Fail rather than overwrite an earlier trial.
    args.output.mkdir(parents=True, exist_ok=False)
    command = ["xcrun", "devicectl", "device", "process", "launch",
               "--device", args.device, "--terminate-existing", "--console",
               "--environment-variables", '{"MWDAT_INVESTIGATION":"1"}',
               "io.rodcone.flutterMetaWearablesDatExample", "--mwdat-investigation"]
    capture = Capture()
    process = None
    selector = selectors.DefaultSelector()
    started = time.monotonic()
    announced = False
    outcome = "consoleExited"
    returncode = None
    print("Starting opt-in capture; do not begin a lock trial until READY.", flush=True)
    try:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        selector.register(process.stdout, selectors.EVENT_READ)
        pending = b""
        discarding = False
        with (args.output / "records.jsonl").open("w", buffering=1) as output:
            while True:
                if not announced and time.monotonic() - started > args.preflight_timeout:
                    outcome = "preflightTimeout"
                    print("Capture NOT ready: startup markers missing or invalid. No lock test.", flush=True)
                    break
                if not selector.select(timeout=0.25):
                    if process.poll() is not None:
                        returncode = process.returncode
                        break
                    continue
                chunk = process.stdout.read1(65536)
                if not chunk:
                    if b"[MWDAT-TRACE" in pending or discarding:
                        capture.malformed += 1
                    returncode = process.wait(timeout=5)
                    break
                pending += chunk
                while b"\n" in pending:
                    line, pending = pending.split(b"\n", 1)
                    if discarding:
                        discarding = False
                        continue
                    if len(line) > MAX_LINE_BYTES:
                        if b"[MWDAT-TRACE" in line:
                            capture.malformed += 1
                        continue
                    parsed = capture.consume(line.decode(errors="replace"))
                    if parsed:
                        parsed["collectorReceiptMonotonicNs"] = time.monotonic_ns()
                        output.write(json.dumps(parsed, separators=(",", ":")) + "\n")
                if len(pending) > MAX_LINE_BYTES:
                    if b"[MWDAT-TRACE" in pending:
                        capture.malformed += 1
                    pending = b""
                    discarding = True
                if not announced and capture.report()["captureReady"]:
                    announced = True
                    print("READY: native + bridge + forwarded Dart startup verified. "
                          "Check foreground frame delivery separately before locking.", flush=True)
                elif announced and not capture.report()["captureReady"]:
                    outcome = "captureInvalid"
                    print("Capture became incomplete or invalid; stop the trial and inspect summary.json.", flush=True)
                    break
                if capture.total > 5000:
                    outcome = "captureLimitExceeded"
                    break
    except KeyboardInterrupt:
        outcome = "operatorStopped"
    except (OSError, subprocess.SubprocessError):
        outcome = "collectorError"
        print("Collector failed; inspect summary.json. No lock test.", flush=True)
    finally:
        selector.close()
        if process:
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=5)
            process.stdout.close()
        report = capture.report()
        report.update(outcome=outcome, startupVerified=announced,
                      consoleExitCode=returncode)
        (args.output / "summary.json").write_text(json.dumps(report, indent=2) + "\n")
        print(f"Capture ended: {outcome}. Summary: {args.output / 'summary.json'}", flush=True)
    return 0 if announced and report["captureReady"] and outcome == "operatorStopped" else 1


if __name__ == "__main__":
    raise SystemExit(main())
