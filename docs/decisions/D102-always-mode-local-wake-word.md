# D102: Always mode listens only for a local wake word

[← Decision Index](INDEX.md)

**Date**: 2026-10-09

**Status**: Active

**Research**: [VGS-656](https://linear.app/vanillagreen/issue/VGS-656)

**Refines**: [D064](D064-jarvis-child-lease.md) and [D066](D066-pinned-local-speech-and-bounded-inputs.md): the daemon-owned sidecar also spots the wake word, with the wake model D066 pinned.

**Decision**: Always mode is opt-in and listens only for the wake word, spotted by the daemon-owned local sidecar. Its capture is armed only while Jarvis is otherwise idle and its indicator, the bubble's resting orb, is presented; it collects no utterance, starts no conversation and releases nothing. The word opens one utterance through the chained engine, and each later request needs the word or Talk again. Always mode with GPT-Live, or with any speech row that cannot spot the word on this computer, is refused with `speech=always-local-voice`; with the local runtime not set up its own cause offers Set up local voice. There is no continuous mode.

**Why**: A cloud voice would stream the room to a provider for as long as the microphone waits. The wake model is the sherpa-onnx keyword spotter `sherpa-onnx-kws-zipformer-gigaspeech-3.3M-2024-01-01`, Apache-2.0 by the README in its archive, which `artifacts.json` pins by SHA-256; setup downloads it at the user's request and VGS ships no model, which closes the plan's question Q5. A continuous mode needs a second always-running capture path, rescoped out by the owner on 2026-10-05. A wait can last all day, so the wake capture publishes no level and the resting orb shows no words and ticks no frame.

**Rejected**: Spotting with the cloud voice provider, and openWakeWord, whose models carry non-commercial terms.

**Revisit when**: A cloud provider offers on-device wake detection, the pinned wake model or its licence changes, or the owner asks for continuous listening.
