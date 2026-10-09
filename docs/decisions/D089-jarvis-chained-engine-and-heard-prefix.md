# D089: One speech engine per conversation owns its turn loop and tells the brain the heard prefix

[← Decision Index](INDEX.md)

**Date**: 2026-10-01

**Status**: Active

**Research**: the Jarvis plan attached to [VGS-623](https://linear.app/vanillagreen/issue/VGS-623), [VGS-652](https://linear.app/vanillagreen/issue/VGS-652)

**Refines**: [D079](D079-brains-wire-and-harness-adapters.md), [D070](D070-jarvis-action-policy.md)

**Decision**: One engine object per conversation owns the brain, the release grants and the heard prefix, and ends them all when Session's generation changes. The daemon owns the local speech sidecar across conversations. After a barge-in, the next user turn carries a separate labelled item with the prefix Audio reports as heard, and a cancelled turn stays in history unanswered. A duplex conversation is the same owner over one OpenAI Realtime session, opened before its first capture and closed with the conversation. The voice has no tools: each transcribed user turn goes to the brain, and the voice reads the brain's released sentences aloud. Any server error or refused frame ends the conversation and no other voice takes over.

**Why**: One owner per conversation releases every resource together, so a provider or policy change cannot carry context or grants to a new recipient set. Audio's flush report is the only true heard account, and rewriting the reply would hide a cut reply from the brain. The Realtime session owns turn-taking, so the chained loop cannot host it. Its truncate event edits only the provider's own conversation, which holds none of the brain's replies, so it cannot replace the heard prefix. `scripts/test-jarvis-engine.js` and `scripts/test-jarvis-live.js` hold both engines.

**Rejected**: Truncating the reply at a length sized from bytes written, and a function the voice model calls to reach the brain, which would let the voice model write the request.

**Revisit when**: A speech provider reports played-frame timing, a brain offers its own truncation, the Realtime voice answers in the provider's own conversation, or the context bound needs a summary.
