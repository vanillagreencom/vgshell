# D102: Always mode listens only for a local wake word

[← Decision Index](INDEX.md)

**Date**: 2026-10-09

**Status**: Withdrawn

**Research**: [VGS-656](https://linear.app/vanillagreen/issue/VGS-656)

**Refines**: [D064](D064-jarvis-child-lease.md) and [D066](D066-pinned-local-speech-and-bounded-inputs.md): the daemon-owned sidecar also spots the wake word, with the wake model D066 pinned.

**Decision**: The withdrawn choice offered an Always mode that admitted capture only for a local wake word. A detected word opened one utterance; later requests needed the word or Talk again.

**Why**: The owner retired Always and wake-word listening in [VGS-2209](https://linear.app/vanillagreen/issue/VGS-2209). Talk opens and closes the conversation, and Hold to talk controls microphone admission. A prior Always preference migrates to unchecked unless a valid Hold to talk preference is already saved. The local microphone check may still use its keyword model; it is an explicit check, not a wake listener.

**Rejected**: Spotting with the cloud voice provider, and openWakeWord, whose models carry non-commercial terms.

**Revisit when**: The owner asks for a separate wake-word listener.
