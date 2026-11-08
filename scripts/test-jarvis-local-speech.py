#!/usr/bin/env python3
"""Local speech sidecar contract: captions, turn end, the end marker, wire, readiness.

Voice activity, caption and voice doubles test the sidecar's own calls, not
model quality; scripts/check-jarvis-local-speech.sh runs the real models. The
suite runs inside the shared Jarvis world. Each control loads a disposable copy
of the sidecar with one planted defect and must turn its case red.
"""
from array import array
import fcntl
import importlib.machinery
import importlib.util
import io
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import unittest
import wave
from types import SimpleNamespace
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
PLUGIN = REPO / "shell/plugins/vgs.jarvis"
SOURCE = PLUGIN / "backend/local-speech.py"
# Loading the sidecar must leave no bytecode in the plugin tree.
sys.dont_write_bytecode = True


def namespace_entry():
    """Enter the existing environment owner rather than duplicate its rules."""
    if os.environ.get("JARVIS_TEST_ROOT"):
        return
    with tempfile.TemporaryDirectory(prefix="jarvis-local-speech-standins-") as name:
        result = subprocess.run(
            [str(REPO / "scripts/lib/jarvis-env.sh"), str(Path(name).resolve()), "--",
             sys.executable, str(Path(__file__).resolve())],
            env={"PATH": "/usr/bin:/bin", "LC_ALL": "C"}, check=False)
    raise SystemExit(result.returncode)


def load(text=None):
    """The sidecar module, or a disposable copy of it holding text."""
    path = SOURCE
    if text is not None:
        folder = Path(tempfile.mkdtemp(prefix="local-speech-mutant-"))
        (folder / "backend").mkdir()
        path = folder / "backend/local-speech.py"
        path.write_text(text)
    loader = importlib.machinery.SourceFileLoader("local_speech_" + str(abs(hash(str(path)))), str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    value = importlib.util.module_from_spec(spec)
    loader.exec_module(value)
    return value


def mutant(needle, replacement):
    text = SOURCE.read_text()
    if text.count(needle) != 1:
        raise AssertionError("control needle must match once: " + needle)
    changed = text.replace(needle, replacement)
    if changed == text:
        raise AssertionError("control changed nothing: " + needle)
    return load(changed)


class Vad:
    """Reports the scripted segments after the whole input was offered."""

    def __init__(self, segments):
        self.segments = list(segments)
        self.offered = 0
        self.queue = []

    def reset(self):
        self.offered = 0
        self.queue = []

    def accept_waveform(self, window):
        if len(window) != 512:
            raise AssertionError("the VAD takes whole 512-sample windows")
        self.offered += len(window)

    def is_speech_detected(self):
        return False

    def flush(self):
        self.queue = [type("Segment", (), {"start": s, "samples": [0.0] * n})() for s, n in self.segments]

    def empty(self):
        return not self.queue

    @property
    def front(self):
        return self.queue[0]

    def pop(self):
        self.queue.pop(0)


class Voice:
    def __init__(self, rate=22050, samples=None, error=None):
        self.rate, self.samples, self.error = rate, samples, error
        self.sids = []

    def generate(self, text, sid, speed):
        self.sids.append(sid)
        if self.error is not None:
            raise self.error
        samples = self.samples if self.samples is not None else [0.25] * 2205
        return type("Audio", (), {"sample_rate": self.rate, "samples": samples})()


class Captions:
    """Cached-stream API double. Each feed makes one scripted decode ready."""

    def __init__(self, texts=()):
        self.texts = iter(texts)
        self.streams = []

    def create_stream(self):
        owner = self

        class Stream:
            ready = False
            text = ""
            samples = 0

            def set_option(self, key, value):
                if (key, value) != ("language", "en"):
                    raise AssertionError("caption language")

            def accept_waveform(self, rate, samples):
                if rate != 16000:
                    raise AssertionError("caption rate")
                self.samples += len(samples)
                self.ready = True

        stream = Stream()
        owner.streams.append(stream)
        return stream

    def is_ready(self, stream):
        return stream.ready

    def decode_stream(self, stream):
        stream.ready = False
        stream.text = next(self.texts, stream.text)

    def get_result(self, stream):
        return stream.text


class Spotter:
    """Keyword-stream API double: the keyword ends once AT samples were fed,
    one ready decode per feed; None for keywords it cannot encode."""

    def __init__(self, at=None, encodes=True):
        self.at, self.encodes = at, encodes
        self.streams = []

    def create_stream(self, keywords):
        if not self.encodes:
            return None

        class Stream:
            samples = 0
            ready = False
            decoded = 0

            def accept_waveform(self, rate, samples):
                if rate != 16000:
                    raise AssertionError("spotter rate")
                self.samples += len(samples)
                self.ready = True

        stream = Stream()
        stream.keywords = keywords
        self.streams.append(stream)
        return stream

    def is_ready(self, stream):
        return stream.ready

    def decode_stream(self, stream):
        stream.ready = False
        stream.decoded = stream.samples

    def get_result(self, stream):
        return "HEY_JARVIS" if self.at is not None and stream.decoded >= self.at else ""


KEYWORDS = json.loads((PLUGIN / "artifacts.json").read_text())["fixture"]["wakeTokens"]


def speech(m, segments, voice=None, rate=22050, captions=None, turn=lambda s: 1.0, spotter=None):
    # Two named speakers, so the second one's sid is 1.
    return m.Speech(Vad(segments), voice or Voice(rate), rate, ["one", "two"], lambda s: s,
                    captions or Captions(), turn, spotter or Spotter(), KEYWORDS)


def frame(header, payload=b""):
    head = json.dumps(header).encode()
    return struct.pack(">II", len(head), len(payload)) + head + payload


def floats(count, value=0.5):
    return (array("f", [value]) * count).tobytes()


def answers(data):
    out, offset = [], 0
    while offset < len(data):
        head, size = struct.unpack(">II", data[offset:offset + 8])
        header = json.loads(data[offset + 8:offset + 8 + head])
        out.append((header, data[offset + 8 + head:offset + 8 + head + size]))
        offset += 8 + head + size
    return out


def serve(m, messages, model):
    output = io.BytesIO()
    explicit = []
    highest = 0
    for message in messages:
        header = message[0]
        if header["id"] > highest and header["type"] not in ("listen", "speak", "check"):
            explicit.append(({"type": "listen", "id": header["id"], "detect": False},))
        highest = max(highest, header["id"])
        explicit.append(message)
    m.serve(io.BytesIO(b"".join(frame(*message) for message in explicit)), output, model)
    return answers(output.getvalue())


def wire_cases(m):
    # A dictation utterance's end: the marker alone, from voice activity that
    # closes the open segment over every sample, the last window padded. No
    # decode runs: the captions keep their one stream and its samples.
    captions = Captions(["draft"])
    model = speech(m, [(0, 16000)], captions=captions)
    out = serve(m, [({"type": "audio", "id": 1}, floats(8000)), ({"type": "audio", "id": 1}, floats(8000)),
                    ({"type": "end", "id": 1},)], model)
    if [h for h, _ in out] != [{"type": "partial", "id": 1, "text": "draft", "rev": 1},
                               {"type": "ended", "id": 1, "speech": True}] or model.vad.offered != 16384:
        raise AssertionError(f"utterance {out} {model.vad.offered}")
    if len(captions.streams) != 1 or captions.streams[0].samples != 16000:
        raise AssertionError("the end decoded the utterance again")
    # An abort drops the utterance; its later frames crossed the abort.
    out = serve(m, [({"type": "audio", "id": 2}, floats(4)), ({"type": "abort", "id": 2},),
                    ({"type": "audio", "id": 2}, floats(4)), ({"type": "end", "id": 2},),
                    ({"type": "end", "id": 3},)], speech(m, []))
    if [h for h, _ in out] != [{"type": "ended", "id": 3, "speech": False}]:
        raise AssertionError(f"abort {out}")
    out = serve(m, [({"type": "speak", "id": 4, "speaker": "one"}, "Hello.".encode())], model)
    audio = b"".join(p for h, p in out if h["type"] == "audio")
    if out[-1][0] != {"type": "spoken", "id": 4, "rate": 22050} or array("f", audio).tolist() != [0.25] * 2205:
        raise AssertionError(f"speak {[h for h, _ in out]}")
    # The request's speaker is the voice's sid.
    serve(m, [({"type": "speak", "id": 5, "speaker": "two"}, "Hello.".encode())], model)
    if model.tts.sids != [0, 1]:
        raise AssertionError(f"speaker sids {model.tts.sids}")
    # A name the loaded voice lacks, such as another tier's voice, fails the
    # sentence and leaves the sidecar serving.
    out = serve(m, [({"type": "speak", "id": 6, "speaker": "af_heart"}, "Hello.".encode()),
                    ({"type": "speak", "id": 7, "speaker": "one"}, "Hello.".encode())], model)
    if [h for h, _ in out][0] != {"type": "failed", "id": 6, "cause": "speaker-unknown"} or out[-1][0]["type"] != "spoken":
        raise AssertionError(f"unknown speaker {[h for h, _ in out]}")
    out = serve(m, [({"type": "speak", "id": 5, "speaker": "one"}, "Hello.".encode())],
                speech(m, [], voice=Voice(error=RuntimeError("voice"))))
    if [h for h, _ in out] != [{"type": "failed", "id": 5, "cause": "synthesis-failed"}]:
        raise AssertionError(f"synthesis failure {out}")
    for name, voice, cause in [("rate", Voice(rate=16000), "synthesis-rate value=16000"),
                               ("silent", Voice(samples=[0.0] * 10), "synthesis-empty")]:
        out = serve(m, [({"type": "speak", "id": 6, "speaker": "one"}, "Hi.".encode())], speech(m, [], voice=voice))
        if [h for h, _ in out] != [{"type": "failed", "id": 6, "cause": cause}]:
            raise AssertionError(f"{name}: {out}")


class LiveVad(Vad):
    """Active speech, then a completed segment; also tests forced splits."""

    def __init__(self, active_after_segment=False):
        super().__init__([(0, 16000)])
        self.active_after_segment = active_after_segment

    def accept_waveform(self, window):
        before = self.offered
        super().accept_waveform(window)
        if before < 16000 <= self.offered:
            self.queue.append(type("Segment", (), {"start": 0, "samples": [0.0] * 16000})())

    def is_speech_detected(self):
        return self.active_after_segment or self.offered < 16000


def streaming_cases(m):
    for mode, active in [(False, False), (True, False), (True, True)]:
        captions = Captions(["draft", "revised draft", "revised draft"])
        turns = []

        def completion(samples):
            turns.append(len(samples))
            return 0.2 if len(turns) == 1 else 0.8

        model = speech(m, [], captions=captions, turn=completion)
        model.vad = LiveVad(active)
        output = io.BytesIO()
        messages = [({"type": "listen", "id": 1, "detect": mode},)]
        # Complete VAD windows let the second block expose its ended segment.
        messages += [({"type": "audio", "id": 1}, floats(8192)) for _ in range(3)]
        prefix = b"".join(frame(*message) for message in messages)
        # The input yields its final end frame only after observing the output
        # already drawn during capture. This proves partials precede key up.
        class Reader(io.BytesIO):
            def read(self, size=-1):
                if self.tell() == len(prefix):
                    observed = [h for h, _ in answers(output.getvalue())]
                    expected = [{"type": "partial", "id": 1, "text": "draft", "rev": 1},
                                {"type": "partial", "id": 1, "text": "revised draft", "rev": 2}]
                    if mode and not active:
                        expected.append({"type": "ended", "id": 1, "speech": True})
                    if observed != expected:
                        raise AssertionError(f"before end {mode, active}: {observed}")
                return super().read(size)

        m.serve(Reader(prefix + frame({"type": "end", "id": 1})), output, model)
        headers = [h for h, _ in answers(output.getvalue())]
        if headers[-1] != {"type": "ended", "id": 1, "speech": True}:
            raise AssertionError(f"end marker: {headers}")
        if len(captions.streams) != 1 or captions.streams[0].samples != 24576:
            raise AssertionError("captions must use one cached stream with every sample once")
        if turns != ([16384, 24576] if mode and not active else []):
            raise AssertionError(f"semantic detector {mode, active}: {turns}")
    model = speech(m, [])
    output = serve(m, [({"type": "listen", "id": 1, "detect": True},),
                       ({"type": "audio", "id": 1}, floats(8000)), ({"type": "end", "id": 1},)], model)
    if [h for h, _ in output] != [{"type": "ended", "id": 1, "speech": False}]:
        raise AssertionError(f"silence {output}")


def bound_case(m):
    m.UTTERANCE_SAMPLES = 10
    out = serve(m, [({"type": "audio", "id": 1}, floats(8)), ({"type": "audio", "id": 1}, floats(8)),
                    ({"type": "end", "id": 1},)], speech(m, [(0, 16)]))
    if [h for h, _ in out] != [{"type": "failed", "id": 1, "cause": "utterance-too-long"}]:
        raise AssertionError(f"utterance bound {out}")


def quiet_case(m):
    # Captured sample counts drive the production cache. No elapsed time or
    # model runtime is needed to cover listening beyond the utterance bound.
    captions = Captions()
    model = speech(m, [], captions=captions)
    utterance = m.Utterance(model, True)
    samples = array("f", [0.0]) * m.RATE
    for _ in range(125):
        partial, ended = utterance.push(samples)
        if partial is not None or ended:
            raise AssertionError("quiet capture produced a turn")
        if len(utterance.samples) > 9 * m.RATE:
            raise AssertionError("leading quiet capture grew beyond the retained window and current block")
    if utterance.heard() or captions.streams[0].samples != 125 * m.RATE:
        raise AssertionError("quiet capture must stay silent and consume every captured sample")
    # The bound still applies once voice activity is in progress.
    active = speech(m, [])
    active.vad.is_speech_detected = lambda: True
    utterance = m.Utterance(active, False)
    try:
        for _ in range(121):
            utterance.push(array("f", [0.5]) * m.RATE)
    except m.Failed as error:
        if str(error) != "utterance-too-long":
            raise
    else:
        raise AssertionError("active speech escaped the utterance bound")


def microphone_cases(m):
    for name, amplitude, wakes, expected in [("silence", 0, None, "silent"),
            ("not detected", 0.5, None, "not-heard"), ("detected", 0.5, 1, "ready")]:
        spotter = Spotter(at=wakes)
        model = speech(m, [], spotter=spotter)
        out = serve(m, [({"type": "check", "id": 1},), ({"type": "audio", "id": 1}, floats(16000, amplitude)),
            ({"type": "audio", "id": 1}, floats(16000, amplitude)),
            ({"type": "audio", "id": 1}, floats(16000, amplitude)), ({"type": "end", "id": 1},)], model)
        if [h for h, _ in out] != [{"type": "checked", "id": 1, "result": expected}]:
            raise AssertionError(f"{name}: {out}")
        if spotter.streams[0].keywords != KEYWORDS or model.captions.streams:
            raise AssertionError("the check must use the wake detector, without captions")

    out = serve(m, [({"type": "check", "id": 1},), ({"type": "audio", "id": 1}, floats(4)),
                    ({"type": "listen", "id": 2, "detect": False},), ({"type": "end", "id": 2},)],
                speech(m, [], spotter=Spotter(encodes=False)))
    if [h for h, _ in out] != [{"type": "failed", "id": 1, "cause": "wake-keywords"},
                               {"type": "ended", "id": 2, "speech": False}]:
        raise AssertionError(f"unencodable check keywords {out}")


# Wire violations: each frame list must end the sidecar with this protocol key.
VIOLATIONS = [
    ("unknown type", [frame({"type": "hello", "id": 1})], "message=invalid type=hello"),
    ("extra key", [frame({"type": "end", "id": 1, "text": "x"})], "message=invalid type=end"),
    ("payload on end", [frame({"type": "end", "id": 1}, b"abcd")], "message=invalid type=end"),
    ("audio without payload", [frame({"type": "audio", "id": 1})], "message=invalid type=audio"),
    ("boolean id", [frame({"type": "end", "id": True})], "id=invalid"),
    ("reused speak id", [frame({"type": "listen", "id": 3, "detect": False}), frame({"type": "end", "id": 3}),
                         frame({"type": "speak", "id": 3, "speaker": "one"}, b"a")], "speak=invalid"),
    ("blank sentence", [frame({"type": "speak", "id": 1, "speaker": "one"}, b" ")], "speak=invalid"),
    ("sentence not UTF-8", [frame({"type": "speak", "id": 1, "speaker": "one"}, b"\xff")], "speak=invalid"),
    ("speak without speaker", [frame({"type": "speak", "id": 1}, b"a")], "message=invalid type=speak"),
    ("number speaker", [frame({"type": "speak", "id": 1, "speaker": 1}, b"a")], "speak=speaker"),
    ("null speaker", [frame({"type": "speak", "id": 1, "speaker": None}, b"a")], "speak=speaker"),
    ("partial sample", [frame({"type": "listen", "id": 1, "detect": False}),
                        frame({"type": "audio", "id": 1}, b"abc")], "audio=partial-sample"),
    ("oversized header", [struct.pack(">II", 4097, 0) + b"{" * 4097], "frame=too-large"),
    ("oversized payload", [struct.pack(">II", 2, 65537) + b"{}" + bytes(65537)], "frame=too-large"),
    ("truncated", [frame({"type": "end", "id": 1})[:-1]], "frame=truncated"),
    ("non-object header", [struct.pack(">II", 2, 0) + b"[]"], "header=invalid"),
    ("audio before listen", [frame({"type": "audio", "id": 1}, floats(2))], "utterance=unstarted"),
    ("invalid detection", [frame({"type": "listen", "id": 1, "detect": "toggle"})], "listen=invalid"),
    ("overlapping captures", [frame({"type": "listen", "id": 1, "detect": True}),
                              frame({"type": "listen", "id": 2, "detect": True})], "listen=invalid"),
    ("check beside a capture", [frame({"type": "listen", "id": 1, "detect": True}),
                                frame({"type": "check", "id": 2})], "check=invalid"),
    ("capture beside a check", [frame({"type": "check", "id": 1}),
                                frame({"type": "listen", "id": 2, "detect": True})], "listen=invalid"),
    ("reused check id", [frame({"type": "check", "id": 2}), frame({"type": "abort", "id": 2}),
                         frame({"type": "check", "id": 2})], "check=invalid"),
]


def violation_cases(m):
    for name, data, key in VIOLATIONS:
        try:
            m.serve(io.BytesIO(b"".join(data)), io.BytesIO(), speech(m, []))
        except m.Protocol as error:
            if str(error) != key:
                raise AssertionError(f"{name}: {error}")
        else:
            raise AssertionError(f"{name}: accepted")


def setup_local():
    """The shipped setup-local module, for its names, its locks and its row."""
    loader = importlib.machinery.SourceFileLoader("setup_local_names", str(PLUGIN / "setup-local"))
    value = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
    loader.exec_module(value)
    return value


SETUP = setup_local()


class Setup:
    """setup-local's surface the sidecar uses, answering a fixed status; its
    clone judge reads ready only while the recording exists and the tier
    verdict it is handed holds, as the shipped judge does among its other
    rules."""

    def __init__(self, tone):
        self.tone = tone
        self.HERE = PLUGIN
        for name in ("CLONE", "CLONE_LOCK", "CLONE_MARKER", "CLONE_PROVIDER", "REFERENCE", "shared", "clone_row"):
            setattr(self, name, getattr(SETUP, name))

    def measurement(self):
        return None

    def status(self, judge, state, data):
        return {"tone": self.tone}

    def clone_status(self, judge, state, data, tier):
        return {"tone": "ok" if tier is True and (state / self.REFERENCE).is_file() else "info"}


def readiness_cases(m):
    with tempfile.TemporaryDirectory() as name:
        state = Path(name)
        try:
            m.load(Setup("warning"), state, state)
        except m.NotReady as error:
            if str(error) != "runtime-not-ready":
                raise
        else:
            raise AssertionError("a not-ready runtime loaded")
        with (state / "local-setup.lock").open("a") as setup:
            fcntl.flock(setup, fcntl.LOCK_EX)
            try:
                m.hold(state).close()
            except m.NotReady as error:
                if str(error) != "setup-busy":
                    raise
            else:
                raise AssertionError("the sidecar started while setup ran")


def admission_case(m):
    """The sidecar asks the real admission owner before any vendor model load."""
    with tempfile.TemporaryDirectory() as name:
        state = Path(name)
        (state / "models").mkdir()
        (state / "local-ready.json").write_text(json.dumps({"tier": "small", "memory": {"ram": 2048, "gpu": None}}))
        judge = m.module("admission_measure", PLUGIN / "measure-local")
        loaded = []
        def locked():
            with (state / "local-load.lock").open("a") as other:
                try:
                    fcntl.flock(other, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    return
                raise AssertionError("memory reading or model load ran without the load lock")
        def reading(resource):
            locked()
            return 1024
        judge.available = reading
        def model(artifact, *args):
            locked()
            loaded.append(artifact["id"])
            return object()
        judge.load = model
        setup = Setup("ok")
        setup.measurement = lambda: judge
        setup.selected = lambda value, tier: ([a for a in value["artifacts"]
            if a["id"] in value["tiers"][tier]["artifacts"]], value["tiers"][tier]["provider"])
        with patch.dict(sys.modules, {"numpy": SimpleNamespace(), "sherpa_onnx": SimpleNamespace()}):
            try:
                m.load(setup, state, state)
            except m.NotReady as error:
                if str(error) != "memory-insufficient resource=ram need=2048 free=1024" or loaded:
                    raise AssertionError(f"memory refusal loaded models: {error} {loaded}")
            else:
                raise AssertionError("the sidecar loaded despite insufficient free memory")
            def enough(resource):
                locked()
                return 2048
            judge.available = enough
            value = m.load(setup, state, state)
            tier = json.loads((PLUGIN / "artifacts.json").read_text())["tiers"]["small"]["artifacts"]
            if not isinstance(value, m.Speech) or sorted(loaded) != sorted(tier):
                raise AssertionError(f"admitted model roles: {loaded}")
            if value.speakers != ["ljspeech"]:
                raise AssertionError(f"the small tier's Piper voice has one speaker, got {value.speakers}")
        with judge.loading(state / "models"):
            # The returned Speech has released the load lock for the next
            # load. Setup's separate shared lock covers its whole lifetime.
            pass


CLONE_STANDIN = REPO / "scripts/fixtures/jarvis-local-speech/clone-standin.py"


def clone_cases(m):
    """The cloned voice speaks a sentence only with a reference and its judge
    ready; otherwise the tier's voice does. A stand-in child speaks the
    recording's own samples, so the case reads which voice spoke."""
    voice = Voice(24000, [0.5] * 2400)
    with tempfile.TemporaryDirectory() as name:
        state = Path(name)
        (state / "models").mkdir()
        (state / "local-ready.json").write_text(json.dumps({"tier": "large", "memory": {"ram": 2048, "gpu": 1024}}))
        (state / "clone-ready.json").write_text(json.dumps({"memory": {"ram": 4096, "gpu": 8192}}))
        clone = state / "clone"
        (clone / "venv/bin").mkdir(parents=True)
        (clone / "venv/bin/python").write_bytes(CLONE_STANDIN.read_bytes())
        (clone / "venv/bin/python").chmod(0o700)
        reference = state / "voice-reference.wav"
        recorded = [0.25, -0.25] * 1200
        judge = m.module("clone_measure", PLUGIN / "measure-local")
        admitted, loaded = [], []
        judge.available = lambda resource: 2 ** 40
        judge.admit = lambda need, provider: admitted.append(need)
        def model(artifact, *args):
            # The tier's loads run with the clone lock free: a removal or a
            # clone setup waits only for the clone's own load.
            with (state / "clone-setup.lock").open("a") as lock:
                try:
                    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    raise AssertionError("a tier model loads under the clone lock") from None
            loaded.append(artifact["id"])
            return voice if artifact["engine"] == "kokoro" else object()
        judge.load = model
        setup = Setup("ok")
        setup.measurement = lambda: judge
        setup.selected = lambda value, tier: ([a for a in value["artifacts"]
            if a["id"] in value["tiers"][tier]["artifacts"]], value["tiers"][tier]["provider"])

        def speak(with_reference, scenario=None):
            (clone / "scenario.json").write_text(json.dumps(scenario or {}))
            del admitted[:], loaded[:]
            speech = m.load(setup, state, state, reference if with_reference else None)
            try:
                return speech.speak("Hello.", "af_alloy"), speech
            finally:
                speech.close()

        with patch.dict(sys.modules, {"numpy": SimpleNamespace(), "sherpa_onnx": SimpleNamespace()}):
            # No recording: the judge reads not ready, so the tier speaks.
            (rate, samples), _ = speak(True)
            if (rate, list(samples)) != (24000, [0.5] * 2400) or "kokoro" not in loaded:
                raise AssertionError(f"without a recording the tier's voice speaks: {rate} {list(samples)[:3]}")
            with wave.open(str(reference), "wb") as out:
                out.setnchannels(1)
                out.setsampwidth(2)
                out.setframerate(24000)
                out.writeframes(struct.pack("<%dh" % len(recorded), *(round(v * 32768) for v in recorded)))
            # The setting off: no reference reaches the sidecar.
            (rate, samples), _ = speak(False)
            if list(samples) != [0.5] * 2400 or admitted != [{"ram": 2048, "gpu": 1024}]:
                raise AssertionError(f"with the setting off the tier's voice speaks: {admitted}")
            # The setting on and the judge ready: the clone speaks the
            # recording, the tier's voice stays unloaded, and both needs are admitted.
            (rate, samples), speech = speak(True)
            if (rate, list(samples)) != (24000, recorded):
                raise AssertionError(f"the cloned voice speaks from the recording: {rate} {list(samples)[:3]}")
            if "kokoro" in loaded or admitted != [{"ram": 2048 + 4096, "gpu": 1024 + 8192}]:
                raise AssertionError(f"cloned load: {loaded} {admitted}")
            # A tier off the graphics card: the clone judge reads its verdict
            # from the tier the sidecar verified, and the tier speaks.
            (state / "local-ready.json").write_text(json.dumps({"tier": "medium", "memory": {"ram": 2048, "gpu": None}}))
            (rate, samples), _ = speak(True)
            if list(samples) != [0.5] * 2400:
                raise AssertionError("beside a CPU tier the tier's voice speaks")
            (state / "local-ready.json").write_text(json.dumps({"tier": "large", "memory": {"ram": 2048, "gpu": 1024}}))
            child = speech.tts.child
            if child.returncode is None:
                raise AssertionError("closing the sidecar's voice reaps its child")
            started = [json.loads(line) for line in (clone / "log.jsonl").read_text().splitlines()][-1]
            if started["argv"][started["argv"].index("--reference") + 1] != str(reference) or started["ppid"] != os.getpid():
                raise AssertionError(f"clone argv: {started}")
            # A child that ends, or answers another request, ends the sidecar.
            for scenario, cause in (({"speak": "end"}, "clone-ended"), ({"speak": "foreign"}, "clone-protocol")):
                try:
                    speak(True, scenario)
                except m.CloneEnded as error:
                    if str(error) != cause:
                        raise
                else:
                    raise AssertionError(f"{scenario}: the sidecar kept serving")
            try:
                speak(True, {"start": "failed"})
            except m.NotReady as error:
                if str(error) != "clone-not-ready":
                    raise
            else:
                raise AssertionError("a clone child that failed its load was served")


CLONE_CHILD = PLUGIN / "backend/clone-speech.py"


def clone_child(text=None):
    """The cloned voice's child module, or a disposable copy holding text."""
    path = CLONE_CHILD
    if text is not None:
        folder = Path(tempfile.mkdtemp(prefix="clone-speech-mutant-"))
        (folder / "backend").mkdir()
        for name in ("local-speech.py", "clone-speech.py"):
            (folder / "backend" / name).write_bytes((PLUGIN / "backend" / name).read_bytes())
        (folder / "measure-local").write_bytes((PLUGIN / "measure-local").read_bytes())
        path = folder / "backend/clone-speech.py"
        path.write_text(text)
    loader = importlib.machinery.SourceFileLoader("clone_speech_" + str(abs(hash(str(path)))), str(path))
    value = importlib.util.module_from_spec(importlib.util.spec_from_loader(loader.name, loader))
    loader.exec_module(value)
    return value


class Samples(list):
    """The float32 sentence a voice returns, as the child reads it."""

    def astype(self, kind):
        if kind != "<f4":
            raise AssertionError("the wire carries little-endian float32")
        return SimpleNamespace(tobytes=lambda: struct.pack("<%df" % len(self), *self))


ARRAYS = SimpleNamespace(isfinite=lambda s: SimpleNamespace(all=lambda: all(v == v and abs(v) != float("inf") for v in s)),
                         any=lambda s: any(s))


class ClonedVoice:
    RATE = 24000

    def __init__(self, sentences):
        self.sentences = list(sentences)
        self.texts = []

    def generate(self, text):
        self.texts.append(text)
        result = self.sentences.pop(0)
        if isinstance(result, Exception):
            raise result
        return Samples(result)


def clone_child_cases(c):
    """The child speaks each sentence, fails one sentence alone, and ends on
    a message outside its wire."""
    voice = ClonedVoice([[0.25] * 20000, RuntimeError("onnxruntime"), [0.0] * 10, [0.5] * 4])
    output = io.BytesIO()
    c.serve(io.BytesIO(b"".join(frame({"type": "speak", "id": ident}, b"Hello.") for ident in (1, 2, 3, 4))),
            output, voice, ARRAYS)
    out = answers(output.getvalue())
    audio = b"".join(p for h, p in out if h == {"type": "audio", "id": 1})
    if array("f", audio).tolist() != [0.25] * 20000 or any(len(p) > 64 * 1024 for _, p in out):
        raise AssertionError("one sentence's samples, in bounded frames")
    if [h for h, _ in out if h["type"] != "audio"] != [
            {"type": "spoken", "id": 1, "rate": 24000}, {"type": "failed", "id": 2, "cause": "synthesis-failed"},
            {"type": "failed", "id": 3, "cause": "synthesis-failed"}, {"type": "spoken", "id": 4, "rate": 24000}]:
        raise AssertionError(f"clone answers: {[h for h, _ in out if h['type'] != 'audio']}")
    if voice.texts != ["Hello."] * 4:
        raise AssertionError(f"sentences: {voice.texts}")
    for header in ({"type": "listen", "id": 5}, {"type": "speak", "id": 5, "speaker": "one"}, {"type": "speak", "id": True}):
        try:
            c.serve(io.BytesIO(frame(header, b"Hi.")), io.BytesIO(), ClonedVoice([[0.5]]), ARRAYS)
        except c.wire.Protocol:
            continue
        raise AssertionError(f"accepted {header}")


def roles_case(m):
    value = json.loads((PLUGIN / "artifacts.json").read_text())
    by_id = {a["id"]: a for a in value["artifacts"]}
    if "small" not in value["tiers"]:
        raise AssertionError("tier discovery is broken: no small tier")
    for tier, row in value["tiers"].items():
        chosen = m.roles([by_id[n] for n in row["artifacts"]], tier)
        if set(chosen) != {"tts", "vad", "captions", "turn", "wake"} or chosen["wake"]["id"] != "wake":
            raise AssertionError(f"{tier}: {chosen}")
    try:
        m.roles([by_id["kokoro"], by_id["piper"], by_id["silero"]], "x")
    except RuntimeError as error:
        if str(error) != "tier=duplicate-role role=tts tier=x":
            raise
    else:
        raise AssertionError("two voices accepted")
    try:
        m.roles([by_id[n] for n in value["tiers"]["small"]["artifacts"] if n != "wake"], "small")
    except RuntimeError as error:
        if str(error) != "tier=missing-role tier=small":
            raise
    else:
        raise AssertionError("a tier without its wake model accepted")
    # A copy of the manifest with a final recognizer back in a tier: the
    # sidecar would never load it, so the tier is refused.
    changed = json.loads(json.dumps(value))
    changed["artifacts"].append({"id": "parakeet", "engine": "parakeet"})
    changed["tiers"]["small"]["artifacts"].insert(0, "parakeet")
    by_id = {a["id"]: a for a in changed["artifacts"]}
    try:
        m.roles([by_id[n] for n in changed["tiers"]["small"]["artifacts"]], "small")
    except RuntimeError as error:
        if str(error) != "tier=unknown-role engine=parakeet tier=small":
            raise
    else:
        raise AssertionError("a recognizer no role loads was accepted")


def run(program, parent, state):
    return subprocess.run([sys.executable, "-I", str(program), "--state", str(state), "--data", str(state),
                           "--parent", str(parent)], env={"PATH": os.environ["PATH"], "LC_ALL": "C"},
                          capture_output=True, check=False)


def main_cases(source):
    """The real entry point: not ready exits 77 with a keyed frame; a foreign parent exits 1."""
    with tempfile.TemporaryDirectory() as name:
        root = Path(name)
        program = root / "backend/local-speech.py"
        program.parent.mkdir()
        program.write_text(source)
        for file in ("setup-local", "measure-local", "artifacts.json"):
            (root / file).write_bytes((PLUGIN / file).read_bytes())
        (root / "fixtures").mkdir()
        for file in ("probe.wav", "probe.txt"):
            (root / "fixtures" / file).write_bytes((PLUGIN / "fixtures" / file).read_bytes())
        state = root / "state"
        state.mkdir()
        result = run(program, os.getpid(), state)
        if result.returncode != 77 or answers(result.stdout) != [({"type": "failed", "cause": "runtime-not-ready"}, b"")]:
            raise AssertionError(f"not ready: {result.returncode} {result.stdout!r} {result.stderr!r}")
        result = run(program, os.getpid() + 1, state)
        if result.returncode != 1 or b"parent=ended" not in result.stderr or result.stdout:
            raise AssertionError(f"foreign parent: {result.returncode} {result.stderr!r}")


# Controls: name, needle, replacement, the case that must turn red.
CONTROLS = [
    ("check follows detector", 'return "ready" if self.heard else "not-heard" if self.sound else "silent"',
     'return "ready"', microphone_cases),
    ("check detects silence", "self.sound = self.sound or any(received)", "self.sound = True", microphone_cases),
    ("check records detector wake", "self.heard = True", "self.heard = False", microphone_cases),
    ("captions during capture", 'if partial is not None:', 'if False:', streaming_cases),
    ("cached captions", 'speech.captions.decode_stream(self.stream)',
     'self.stream = speech.captions.create_stream(); speech.captions.decode_stream(self.stream)', streaming_cases),
    ("semantic end", 'ended = probability >= 0.5', 'ended = True', streaming_cases),
    ("hold mode", 'if self.detect_turn and self.has_segment', 'if self.has_segment', streaming_cases),
    ("active speech", 'and not speech.vad.is_speech_detected()', '', streaming_cases),
    ("turn end answers a transcript", '                    send(writer, {"type": "ended", "id": ident, "speech": True})',
     '                    send(writer, {"type": "final", "id": ident, "text": "draft"})', streaming_cases),
    ("end decodes the utterance", '            send(writer, {"type": "ended", "id": ident, "speech": utterances.pop(ident).heard()})',
     '            done = utterances.pop(ident)\n            stream = speech.captions.create_stream()\n'
     '            stream.accept_waveform(RATE, speech.waveform(done.samples))\n            speech.captions.decode_stream(stream)\n'
     '            send(writer, {"type": "ended", "id": ident, "speech": done.heard()})', wire_cases),
    ("end leaves the segment open", "            vad.flush()\n            self.has_segment = not vad.empty()",
     "            self.has_segment = False", wire_cases),
    ("end drops the last window", "            vad.accept_waveform(self.speech.waveform(window))\n", "", wire_cases),
    ("crossed message", "if ident not in utterances:\n            continue", "if False:\n            continue",
     wire_cases),
    ("synthesis empty", "if not samples or not all(math.isfinite(v) for v in samples) or not any(samples):",
     "if False:", wire_cases),
    ("quiet cache retained", "discard = max(0, len(self.samples) - 8 * RATE)", "discard = 0", quiet_case),
    ("utterance bound", "if len(self.samples) + len(received) > UTTERANCE_SAMPLES:", "if False:", bound_case),
    ("message shape", "or set(header) != SHAPES[kind][0] ", "", violation_cases),
    ("speaker type", "if type(speaker) is not str:", "if False:", violation_cases),
    ("speaker known", '        if speaker not in self.speakers:\n            raise Failed("speaker-unknown")\n', "", wire_cases),
    ("speaker sid", "sid=self.speakers.index(speaker)", "sid=0",
     wire_cases),
    ("frame bound", "if not 0 < head <= HEADER_BYTES or size > PAYLOAD_BYTES:", "if not 0 < head:",
     violation_cases),
    ("readiness", 'if setup.status(judge, state, data)["tone"] != "ok":', "if False:", readiness_cases),
    ("setup lock", "fcntl.flock(lock, fcntl.LOCK_SH | fcntl.LOCK_NB)", "fcntl.flock(lock, fcntl.LOCK_UN)",
     readiness_cases),
    ("one role each", "if role in found:", "if False:", roles_case),
    ("every role", "if set(found) != set(ROLES.values()):", "if False:", roles_case),
    ("wake role", '"smart-turn": "turn", "wake": "wake"}', '"smart-turn": "turn"}', roles_case),
    ("unknown engine refused", 'raise RuntimeError(f"tier=unknown-role engine={artifact[\'engine\']} tier={tier}")', "continue",
     roles_case),
    ("spotter fed", "self.stream.accept_waveform(RATE, self.speech.waveform(received))", "pass", microphone_cases),
    ("keyword encoded", 'raise Failed("wake-keywords")', "pass", microphone_cases),
    ("check alone", '            if not fresh or utterances:\n                raise Protocol("check=invalid")',
     '            if not fresh:\n                raise Protocol("check=invalid")', violation_cases),
    ("memory admission", 'judge.admit(need, provider)', 'False and judge.admit(need, provider)', admission_case),
    ("load serialization", 'with judge.loading(data / "models"):', 'if True:', admission_case),
    ("clone readiness", '\n                      and setup.clone_status(judge, state, data, provider == setup.CLONE_PROVIDER)["tone"] == "ok")', ')', clone_cases),
    ("clone tier verdict", 'provider == setup.CLONE_PROVIDER)["tone"]', 'True)["tone"]', clone_cases),
    ("clone admission", 'need = {resource: need[resource] + extra[resource] for resource in ("ram", "gpu")}', 'pass', clone_cases),
    ("clone setting", 'cloned = (reference is not None and held', 'cloned = (held', clone_cases),
    ("clone end ends the sidecar", 'except StopIteration:\n            raise CloneEnded("clone-ended") from None',
     'except StopIteration:\n            return {"type": "ready"}, b""', clone_cases),
    ("clone answer of another id", 'if ident != self.last:', 'if False:', clone_cases),
    ("clone child reaped", "        self.child.kill()\n        self.child.wait()\n", "", clone_cases),
]


RUNNER = REPO / "scripts/check-jarvis-local-speech.sh"
GUARD = 'if [[ -z $models || -z $python || ! -x $python || ! -d $models ]]; then'


def runner_case(source):
    """The real-model row: 77 without prepared inputs; resolved paths and the
    consumer's status pass through. A stand-in world owner and interpreter."""
    with tempfile.TemporaryDirectory() as name:
        root = Path(name).resolve()
        (root / "scripts/lib").mkdir(parents=True)
        runner = root / "scripts/check-jarvis-local-speech.sh"
        runner.write_text(source)
        (root / "scripts/lib/jarvis-env.sh").write_text('#!/bin/bash\nshift 2\nexec "$@"\n')
        (root / "prepared/models").mkdir(parents=True)
        (root / "prepared/venv/bin").mkdir(parents=True)
        (root / "prepared/interpreter").write_text('#!/bin/bash\nprintf "%s\\n" "$0" "$@" > "$(dirname "$0")/../../argv"\nexit 3\n')
        (root / "prepared/venv/bin/python").symlink_to(root / "prepared/interpreter")
        for path in (runner, root / "scripts/lib/jarvis-env.sh", root / "prepared/interpreter"):
            path.chmod(0o755)
        # validate runs this row on the host, outside the world, so it gets the
        # system tools; the stand-ins above reach no model, device or network.
        env = {"PATH": "/usr/bin:/bin", "LC_ALL": "C", "HOME": str(root)}
        result = subprocess.run([str(runner)], cwd=root, env=env, capture_output=True, text=True, check=False)
        if result.returncode != 77 or "reason=prepared-inputs-unavailable" not in result.stdout:
            raise AssertionError(f"no inputs: {result.returncode} {result.stdout!r}")
        env.update(JARVIS_LOCAL_MODELS="prepared/models", JARVIS_LOCAL_PYTHON="prepared/venv/bin/python")
        result = subprocess.run([str(runner)], cwd=root, env=env, capture_output=True, text=True, check=False)
        argv = (root / "prepared/argv").read_text().splitlines() if (root / "prepared/argv").exists() else []
        if result.returncode != 3 or argv != [str(root / "prepared/venv/bin/python"),
                                               str(root / "scripts/fixtures/jarvis-local-speech/real.py"),
                                               str(root), str(root / "prepared/models")]:
            raise AssertionError(f"prepared inputs: {result.returncode} {argv} {result.stderr!r}")
        env["JARVIS_LOCAL_MODELS"] = "prepared/missing"
        result = subprocess.run([str(runner)], cwd=root, env=env, capture_output=True, text=True, check=False)
        if result.returncode != 77:
            raise AssertionError(f"missing models: {result.returncode}")


class LocalSpeech(unittest.TestCase):
    def test_streaming(self):
        streaming_cases(load())

    def test_wire(self):
        m = load()
        wire_cases(m)
        violation_cases(m)
        bound_case(load())
        microphone_cases(load())
        quiet_case(load())

    def test_readiness(self):
        m = load()
        readiness_cases(m)
        roles_case(m)

    def test_admission(self):
        admission_case(load())

    def test_clone(self):
        clone_cases(load())

    def test_clone_child(self):
        clone_child_cases(clone_child())
        source = CLONE_CHILD.read_text()
        for name, needle, replacement in (
                ("silent sentence spoken", 'raise ValueError("synthesis=empty")', "pass"),
                ("message unjudged", 'if set(header) != {"type", "id"} or header["type"] != "speak" or type(header["id"]) is not int:',
                 "if False:"),
                ("a failed sentence ends the child", "            continue\n        data =", "            raise\n        data =")):
            with self.subTest(control=name):
                self.assertEqual(source.count(needle), 1, needle)
                with self.assertRaises(Exception, msg="must-fail control stayed green: " + name):
                    clone_child_cases(clone_child(source.replace(needle, replacement)))
        # The real entry point refuses an ended parent before it loads.
        result = subprocess.run([sys.executable, "-I", str(CLONE_CHILD), "--models", "/nonexistent", "--reference",
                                 "/nonexistent", "--parent", str(os.getpid() + 1)],
                                env={"PATH": os.environ["PATH"], "LC_ALL": "C"}, capture_output=True, check=False)
        self.assertEqual(result.returncode, 1)
        self.assertIn(b"parent=ended", result.stderr)
        self.assertEqual(result.stdout, b"")

    def test_entry_point(self):
        main_cases(SOURCE.read_text())

    def test_runner(self):
        runner_case(RUNNER.read_text())

    def test_controls(self):
        for name, needle, replacement, case in CONTROLS:
            with self.subTest(control=name):
                # The copy loads first, so only the planted defect can redden the case.
                copy = mutant(needle, replacement)
                with self.assertRaises(Exception, msg="must-fail control stayed green: " + name):
                    case(copy)
        text = SOURCE.read_text()
        with self.assertRaises(AssertionError, msg="must-fail control stayed green: parent check"):
            main_cases(text.replace("if os.getppid() != args.parent:", "if False:", 1))
        source = RUNNER.read_text()
        for needle, replacement in ((GUARD, "if false; then"),
                                    ('models="$(cd -- "$models" && pwd -P)"', 'models="$models"'),
                                    ('python="$python_dir/$(basename -- "$python")"', 'python="$(readlink -f -- "$python")"')):
            self.assertEqual(source.count(needle), 1, needle)
            with self.assertRaises(AssertionError, msg="must-fail control stayed green: " + needle):
                runner_case(source.replace(needle, replacement))
        print(f"jarvis-local-speech: controls={len(CONTROLS) + 4}", flush=True)


if __name__ == "__main__":
    namespace_entry()
    unittest.main(verbosity=1)
