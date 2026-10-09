#!/usr/bin/env python3
"""Stand-in sidecar: the selected runtime's interpreter for LocalSpeech.js tests.

The suite installs this file as DATA/venv/bin/python. It speaks the sidecar wire
from shell/plugins/vgs.jarvis/backend/local-speech.py's header (2026-10-02),
written independently of LocalSpeech.js. DATA/scenario.json scripts it:
  start: "ready" | "held" | "not-ready" | "exit" | "deaf" | "garbage" | "foreign-id"
  utterances: per end, {final} | {failed} | {exit}; optional streaming:
    {partials:[{text,rev}], earlyFinal:text} answered on successive audio frames
  speech: per speak, {rate, samples, tone?, value?} | {failed} | {raw}
  wakes: per wake, {afterFrames} answered woke on that audio frame | {failed}
    answered on the first; with none left a wake waits for its abort
DATA/log.jsonl records what it observed: its start facts, then one line per
ended, aborted or spoken request. No model, device or network is touched.
"""
import ctypes
import importlib.machinery
import importlib.util
import json
import math
import os
from pathlib import Path
import struct
import signal as signals
import sys
import time

args = sys.argv[1:]
if args == ["--query-gpu=memory.free", "--format=csv,noheader,nounits"]:
    # This executable is copied to the private query PATH. Acknowledge that
    # the real admission owner started it before cancellation is tested.
    with (Path(__file__).resolve().parent.parent / "log.jsonl").open("a") as output:
        output.write(json.dumps({"query": {"pid": os.getpid(), "ppid": os.getppid()}}) + "\n")
        output.flush()
    signals.pause()
    sys.exit(0)
data = Path(args[args.index("--data") + 1])
scenario = json.loads((data / "scenario.json").read_text())
log = (data / "log.jsonl").open("a")


def record(value):
    log.write(json.dumps(value) + "\n")
    log.flush()


def send(header, payload=b""):
    head = json.dumps(header).encode()
    sys.stdout.buffer.write(struct.pack(">II", len(head), len(payload)) + head + payload)
    sys.stdout.buffer.flush()


def read(size):
    data = b""
    while len(data) < size:
        part = sys.stdin.buffer.read(size - len(data))
        if not part:
            return None
        data += part
    return data


signal = ctypes.c_int()
ctypes.CDLL(None, use_errno=True).prctl(2, ctypes.byref(signal))  # PR_GET_PDEATHSIG
record({"start": {"argv": args, "pid": os.getpid(), "env": sorted(os.environ), "ppid": os.getppid(),
                  "net": os.readlink("/proc/self/ns/net"), "pdeathsig": signal.value}})
start = scenario.get("start", "ready")
if start == "memory-query":
    loader = importlib.machinery.SourceFileLoader("query_owner", str(data / "measure-local"))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    judge = importlib.util.module_from_spec(spec)
    loader.exec_module(judge)
    os.environ["PATH"] = str(data / "query") + ":" + os.environ["PATH"]
    judge.available("gpu")
if start == "held":
    # A test-owned FIFO keeps the real loading order: read no PCM until
    # the test permits ready. No host clock determines the transition.
    with (data / "ready-gate").open("rb") as gate:
        gate.read(1)
if start in ("not-ready", "memory-refused", "memory-unavailable"):
    cause = {"not-ready": "runtime-not-ready",
        "memory-refused": "memory-insufficient resource=ram need=2048 free=1024",
        "memory-unavailable": "memory-unavailable resource=ram"}[start]
    send({"type": "failed", "cause": cause})
    sys.exit(77)
if start == "exit":
    print("Traceback: stand-in failed to load", file=sys.stderr)
    sys.exit(70)
if start == "deaf":
    # Reads nothing, so the daemon's writes back up; ends only when killed.
    send({"type": "ready"})
    while True:
        time.sleep(60)
if start == "silent":
    while True:
        time.sleep(60)
if start == "garbage":
    sys.stdout.buffer.write(struct.pack(">II", 2, 0) + b"[]")
    sys.stdout.buffer.flush()
    time.sleep(60)
send({"type": "ready"})
record({"ready": True})
if start == "foreign-id":
    send({"type": "final", "id": 99, "text": "never asked"})

utterances = list(scenario.get("utterances", []))
speech = list(scenario.get("speech", []))
wakes = list(scenario.get("wakes", []))
received = {}
listening = {}
spotting = {}
while True:
    prefix = read(8)
    if prefix is None:
        record({"eof": True})
        sys.exit(0)
    head, size = struct.unpack(">II", prefix)
    body = read(head + size)
    header, payload = json.loads(body[:head]), body[head:]
    kind, ident = header["type"], header["id"]
    if kind == "listen":
        record({"listen": ident, "detect": header["detect"]})
        listening[ident] = {"detect": header["detect"], "count": 0}
    elif kind == "wake":
        record({"wake": ident})
        spotting[ident] = 0
    elif kind == "audio" and ident in spotting:
        received.setdefault(ident, []).extend(v for (v,) in struct.iter_unpack("<f", payload))
        spotting[ident] += 1
        action = wakes[0] if wakes else {}
        if "failed" in action:
            wakes.pop(0)
            del spotting[ident]
            send({"type": "failed", "id": ident, "cause": action["failed"]})
        elif "afterFrames" in action and spotting[ident] >= action["afterFrames"]:
            wakes.pop(0)
            del spotting[ident]
            samples = received.pop(ident)
            record({"woke": ident, "samples": len(samples),
                    "rms": math.sqrt(sum(v * v for v in samples) / len(samples))})
            send({"type": "woke", "id": ident})
    elif kind == "audio":
        received.setdefault(ident, []).extend(v for (v,) in struct.iter_unpack("<f", payload))
        live = listening.get(ident)
        if live is not None and utterances:
            action = utterances[0]
            partials = action.get("partials", [])
            at = live["count"]
            live["count"] += 1
            if at < len(partials):
                send({"type": "partial", "id": ident, **partials[at]})
                record({"partial": ident, **partials[at]})
            elif live["detect"] and "earlyFinal" in action:
                send({"type": "final", "id": ident, "text": action["earlyFinal"]})
                record({"final": ident})
                del listening[ident]
                utterances.pop(0)
    elif kind == "abort":
        spotting.pop(ident, None)
        record({"abort": ident, "samples": len(received.pop(ident, []))})
    elif kind == "end":
        if ident not in listening:
            record({"crossed-end": ident})
            continue
        del listening[ident]
        samples = received.pop(ident, [])
        crossings = sum(1 for a, b in zip(samples, samples[1:]) if (a < 0) != (b < 0))
        rms = math.sqrt(sum(v * v for v in samples) / len(samples)) if samples else 0.0
        record({"end": ident, "samples": len(samples), "crossings": crossings, "rms": rms})
        action = utterances.pop(0)
        if action.get("stall"):
            continue
        if "exit" in action:
            sys.exit(action["exit"])
        if "final" in action:
            send({"type": "final", "id": ident, "text": action["final"]})
        else:
            send({"type": "failed", "id": ident, "cause": action["failed"]})
    elif kind == "speak":
        record({"speak": ident, "text": payload.decode()})
        action = speech.pop(0)
        if action.get("stall"):
            continue
        if "failed" in action:
            send({"type": "failed", "id": ident, "cause": action["failed"]})
            continue
        if "raw" in action:
            sys.stdout.buffer.write(bytes.fromhex(action["raw"]))
            sys.stdout.buffer.flush()
            continue
        rate = action["rate"]
        values = [action.get("value", 0.5) * (math.sin(2 * math.pi * action["tone"] * i / rate) if "tone" in action else 1)
                  for i in range(action["samples"])]
        raw = b"".join(struct.pack("<f", v) for v in values)
        for offset in range(0, len(raw), 65536):
            send({"type": "audio", "id": ident}, raw[offset:offset + 65536])
        send({"type": "spoken", "id": ident, "rate": rate})
    else:
        record({"unknown": header})
