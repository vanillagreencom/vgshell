# D073: Jarvis releases labelled content to one recipient set through one origin-bound door

[← Decision Index](INDEX.md)

**Date**: 2026-09-30
**Status**: Active
**Research**: the Jarvis plan attached to [VGS-623](https://linear.app/vanillagreen/issue/VGS-623)

**Decision**: Release is judged per labelled item against the whole immutable brain-plus-speech recipient set, a summary keeps every contributing label, and one network door attaches a key only to its exact stored origin and refuses every redirect.

**Why**: Speech can receive content first released to the brain, so a per-destination check leaks across providers. A redirect or a custom endpoint can hand a stored key to the wrong origin. `scripts/test-jarvis-release.js` and `scripts/test-jarvis-net.js` hold both.

**Rejected**: Consent per immediate destination. Speech receives what the brain already got.

**Revisit when**: A supported provider requires redirects, a new credential placement, or a transport the door cannot mediate.
