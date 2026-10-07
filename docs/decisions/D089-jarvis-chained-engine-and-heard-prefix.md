# D089: One speech engine per conversation owns its turn loop and tells the brain the heard prefix

[← Decision Index](INDEX.md)

**Date**: 2026-10-01
**Status**: Active
**Research**: the Jarvis plan attached to [VGS-623](https://linear.app/vanillagreen/issue/VGS-623), [VGS-652](https://linear.app/vanillagreen/issue/VGS-652)
**Refines**: [D079](D079-brains-wire-and-harness-adapters.md), [D070](D070-jarvis-action-policy.md)

**Decision**: One engine object per conversation owns the speech adapter, the brain, the release grants and the heard prefix, and ends them all when Session's generation changes. After a barge-in, the next user turn carries a separate labelled item with the prefix Audio reports as heard, and a cancelled turn stays in history unanswered. A duplex conversation is the same owner over one GPT-Live session, opened before its first capture and closed with the conversation; any server error or refused frame ends the conversation and no other voice takes over.

**Why**: One owner per conversation releases every resource together, so a provider or policy change cannot carry context or grants to a new recipient set. Audio's flush report is the only true heard account, and rewriting the reply would hide a cut reply from the brain. GPT-Live owns turn-taking and sends no output timing or truncate event, so the chained loop cannot host it. `scripts/test-jarvis-engine.js` and `scripts/test-jarvis-live.js` hold both engines.

**Rejected**: Truncating the reply at a length sized from bytes written, and GPT-Live's responses-mode delegation, which would reach the voice model without the policy gate.

**Revisit when**: A speech provider reports played-frame timing, a brain offers its own truncation, GPT-Live adds a truncate event or output timing, or the context bound needs a summary.
