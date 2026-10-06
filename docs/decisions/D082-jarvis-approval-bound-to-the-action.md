# D082: Jarvis approval belongs to one immutable action

[← Decision Index](INDEX.md)

**Date**: 2026-10-01
**Status**: Active
**Research**: the Jarvis plan attached to [VGS-623](https://linear.app/vanillagreen/issue/VGS-623)
**Refines**: [D070](D070-jarvis-action-policy.md)

**Decision**: The router holds one immutable typed call behind a random id and a canonical digest. Session owns the confirmation's identity, timing and expiry, Policy rejudges fresh facts, and Audit must succeed before the action starts. The model has no confirmation API.

**Why**: File, page and model output can request synthetic input, so any confirmation the model could reach would let untrusted output release its own hold. A serial slot keeps a held action from starting a tool that presses its own key. `scripts/test-jarvis-router.js` and `scripts/test-jarvis-session.js` hold the hold.

**Rejected**: Model-supplied approval prose or a confirmation tool. Untrusted output would release the hold.

**Revisit when**: An action cannot fit a typed call, or must run while another waits for consent.
