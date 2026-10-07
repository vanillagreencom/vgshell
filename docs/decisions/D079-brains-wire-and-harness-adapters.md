# D079: Jarvis brains are wire adapters or harness adapters, with no npm dependency

[← Decision Index](INDEX.md)

**Date**: 2026-09-30
**Status**: Active
**Research**: the Jarvis plan attached to [VGS-623](https://linear.app/vanillagreen/issue/VGS-623)
**Refines**: [D009](D009-one-manifest-judge-under-node.md), [D037](D037-plugin-status.md)

**Decision**: A brain is a wire adapter, the vendor's HTTP API over Node's `fetch` with a key from libsecret bound to its origin, or a harness adapter, the vendor's own program with its built-in tools off and the tool bridge as its only tool server. One OpenAI-compatible driver serves every provider that speaks that wire, and no adapter depends on an npm package.

**Why**: VGS ships no npm tree and has no install route for one. Vendor terms allow a subscription only through the vendor's unmodified program, so a harness is the only lawful subscription path, and a harness tool left on would bypass the policy gate. `scripts/test-jarvis-providers.js` and `scripts/test-jarvis-claude.js` hold the adapters.

**Rejected**: Vendor npm SDKs. No install route, and the subscription path must stay the unmodified program. The Copilot SDK speaks Copilot's own JSON-RPC to the CLI through an npm or pip package; VGS uses `copilot --acp`, which needs no package.

**Revisit when**: A provider speaks neither a compatible wire nor a harness program, VGS gains an npm route, or a vendor permits a subscription outside its own program.
