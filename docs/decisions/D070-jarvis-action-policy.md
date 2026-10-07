# D070: Jarvis actions pass one typed policy gate

[← Decision Index](INDEX.md)

**Date**: 2026-09-30
**Status**: Active
**Research**: the Jarvis plan attached to [VGS-623](https://linear.app/vanillagreen/issue/VGS-623)
**Refines**: [D010](D010-facade-scope-not-sandbox.md)

**Decision**: `Policy.decide` is the one action judge: typed tool schemas, refined arguments, real resolved paths for denial, and turn taint that raises a changing action to confirmation and never lowers a physical approval. The router holds one immutable typed call behind a random id and a canonical digest. Session owns confirmation identity, timing and expiry. Policy rejudges fresh facts, and Audit must succeed before the action starts. The model has no confirmation API, and the serial action slot stays held while consent is pending.

**Why**: A model can pick an action from untrusted file, page or screen content, and a prose description gives no authority. Logical path prefixes cannot protect credentials once aliases and absent targets are considered. A confirmation the model could reach would let untrusted output release its own hold. Binding consent to one immutable call prevents substitution, and a serial slot stops a held action from starting a tool that presses its own approval key.

**Rejected**: Deny and confirmation regexes over prose, model-supplied approval prose and a confirmation tool. Text matching grants no authority, and untrusted output could release its own hold.

**Revisit when**: An executor cannot supply typed arguments or trusted target facts, kernel confinement cannot mediate an operation, an action cannot fit a typed call, or an action must run while another waits for consent.
