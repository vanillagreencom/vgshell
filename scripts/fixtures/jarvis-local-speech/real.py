"""Actual-model consumer of the speech sidecar. No model or network stand-ins.

Each CPU tier's microphone check, voice activity, caption, turn and voice models
run the bundled clip through the sidecar's own wire: a keyword check, an utterance whose
end says voice activity heard speech, and synthesis. The utterance's words are
the core's dictation recording's, so no recognizer runs. A missing input exits
77 through the artifact judge; it never makes a smaller passing test.
"""
from array import array
import importlib.machinery
import importlib.util
import io
import json
from pathlib import Path
import struct
import sys

repo, models = map(Path, sys.argv[1:])
plugin = repo / "shell/plugins/vgs.jarvis"


def module(name, path):
    loader = importlib.machinery.SourceFileLoader(name, str(path))
    spec = importlib.util.spec_from_loader(loader.name, loader)
    value = importlib.util.module_from_spec(spec)
    loader.exec_module(value)
    return value


judge = module("jarvis_measure", plugin / "measure-local")
sidecar = module("jarvis_local_speech", plugin / "backend/local-speech.py")


def frame(header, payload=b""):
    head = json.dumps(header).encode()
    return struct.pack(">II", len(head), len(payload)) + head + payload


def answers(data):
    out, offset = [], 0
    while offset < len(data):
        head, size = struct.unpack(">II", data[offset:offset + 8])
        out.append((json.loads(data[offset + 8:offset + 8 + head]), data[offset + 8 + head:offset + 8 + head + size]))
        offset += 8 + head + size
    return out


try:
    value = judge.manifest(plugin / "artifacts.json")
    import numpy as np
    import sherpa_onnx as sherpa
    raw, text = judge.clip(value)
    clip = array("f", (np.frombuffer(raw, dtype="<i2").astype(np.float32) / 32768).tobytes())
    for tier in ("small", "medium"):
        row = value["tiers"][tier]
        by_id = {a["id"]: a for a in value["artifacts"]}
        chosen = sidecar.roles([by_id[name] for name in row["artifacts"]], tier)
        judge.verify(value, models, list(chosen.values()))
        loaded = {role: judge.load(a, models, row["provider"], np, sherpa) for role, a in chosen.items()}
        speech = sidecar.Speech(loaded["vad"], loaded["tts"], chosen["tts"]["outputSampleRate"],
                                [speaker["name"] for speaker in chosen["tts"]["speakers"]], lambda samples: np.frombuffer(samples, dtype=np.float32), loaded["captions"],
                                lambda samples: judge.infer(chosen["turn"], loaded["turn"], np.frombuffer(samples, dtype=np.float32),
                                                            "", value, np)["probability"],
                                loaded["wake"], value["fixture"]["wakeTokens"])
        def audio_frames(ident, samples):
            payload = sidecar.little(array("f", samples)).tobytes()
            return b"".join(frame({"type": "audio", "id": ident}, payload[at:at + sidecar.PAYLOAD_BYTES])
                            for at in range(0, len(payload), sidecar.PAYLOAD_BYTES))
        # The clip contains the check phrase. Other keywords must not pass the
        # microphone check.
        voiced = loaded["tts"].generate("Play music. Alexa. Hello world.", sid=0, speed=1)
        others = np.asarray(voiced.samples, dtype=np.float32)
        others = np.interp(np.arange(len(others) * sidecar.RATE // voiced.sample_rate) * voiced.sample_rate / sidecar.RATE,
                           np.arange(len(others)), others).astype(np.float32)
        others = np.concatenate([others, np.zeros(sidecar.RATE, dtype=np.float32)])
        stream = frame({"type": "check", "id": 1}) + audio_frames(1, clip) + frame({"type": "end", "id": 1})
        stream += frame({"type": "check", "id": 2}) + audio_frames(2, others) + frame({"type": "end", "id": 2})
        stream += frame({"type": "listen", "id": 3, "detect": False}) + audio_frames(3, clip)
        # The last declared speaker: the table's sid order reaches the real voice.
        stream += frame({"type": "end", "id": 3}) + frame({"type": "speak", "id": 4, "speaker": chosen["tts"]["speakers"][-1]["name"]},
                                                          text.encode())
        output = io.BytesIO()
        sidecar.serve(io.BytesIO(stream), output, speech)
        replies = answers(output.getvalue())
        ended = [h for h, _ in replies if h["type"] == "ended"]
        spoken = [h for h, _ in replies if h["type"] == "spoken"]
        audio = sum(len(p) for h, p in replies if h["type"] == "audio")
        checked = [h for h, _ in replies if h["id"] in (1, 2)]
        if checked != [{"type": "checked", "id": 1, "result": "ready"}, {"type": "checked", "id": 2, "result": "not-heard"}]:
            raise RuntimeError(f"check-mismatch {tier}: {checked}")
        if ended != [{"type": "ended", "id": 3, "speech": True}] or spoken != [{"type": "spoken", "id": 4, "rate": chosen["tts"]["outputSampleRate"]}] or audio < 4 * spoken[0]["rate"]:
            raise RuntimeError(f"wire-mismatch {tier}: {[h for h, _ in replies][-3:]} audio={audio}")
        print(json.dumps({"tier": tier, "spoken_bytes": audio}), flush=True)
        del loaded, speech
except judge.Unavailable as error:
    print(f"jarvis-local-speech: status=not-measured {error}", file=sys.stderr)
    sys.exit(77)
except sidecar.Failed as error:
    print(f"jarvis-local-speech: failed={error}", file=sys.stderr)
    sys.exit(1)
print("jarvis-local-speech: actual-models=ok", flush=True)
