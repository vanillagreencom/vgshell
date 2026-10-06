# D070: Jarvis actions pass one typed policy gate

[← Decision Index](INDEX.md)

**Date**: 2026-09-30
**Status**: Active
**Research**: the Jarvis plan attached to [VGS-623](https://linear.app/vanillagreen/issue/VGS-623)
**Refines**: [D010](D010-facade-scope-not-sandbox.md)

**Decision**: `Policy.decide` is the one action judge: typed tool schemas, refined arguments, real resolved paths for denial, and turn taint that raises a changing action to confirmation and never lowers a physical approval.

**Why**: A model can pick an action from untrusted file, page or screen content, and a prose description gives no authority. Logical path prefixes cannot protect credentials once aliases and absent targets are considered. `scripts/test-jarvis-policy.js` holds the gate.

**Rejected**: Deny and confirmation regexes over prose, whose own security notes say the match is not authorization.

**Revisit when**: An executor cannot supply typed arguments or trusted target facts, or kernel confinement cannot mediate an operation.
