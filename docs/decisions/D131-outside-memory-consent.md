# D131: The owner chooses consent for memory notes from outside content

[← Decision Index](INDEX.md)

**Date**: 2026-11-10

**Status**: Active

**Research**: [VGS-2391](https://linear.app/vanillagreen/issue/VGS-2391), owner Slack message 1794173973.230529; approved by the owner's delegate Jarvis carrying out that directive, answer 1794335399

**Refines**: [D070](D070-jarvis-action-policy.md), only the confirmation rule for tainted `memory.propose` and `memory.replace`

**Decision**: The Jarvis manifest owns the Safety setting Outside memory notes, with the full name Memory notes from outside content in its tooltip. Ask first is the default and holds tainted memory writes in the inbox for the owner's Confirm or Discard. Save without asking writes new tainted notes at once, with their host origin labels and receipts. Existing inbox entries keep waiting. `Memory.js::writeOrInbox` reads the live setting for each write; only explicit Save without asking bypasses the inbox. `Policy.decide` keeps its memory-write exception: under Save without asking no confirmation holds a tainted memory write, an explicit exception to D070's taint rule. The model gets no confirmation tool or setting access. Both choices keep secret, hash, link, size and `MEMORY.md` safeguards. Stored origin labels survive `memory.read`, so outside content still taints later turns.

**Why**: The owner asks, "what is this 'memory note' feature? Approving memories that are added? Is this a user setting to warn and approve these things? Its fine as long as user can customize auto add/approve or not." The choice leaves the safe hold on by default and lets the owner accept that instructions planted in outside content can become saved memory without another approval.

**Rejected**: No setting, because the owner cannot choose automatic saving. A model confirmation tool, because outside content could release its own hold rather than the owner choosing the policy.

**Revisit when**: Memory gains another writer, stored origins no longer preserve later-turn taint, or the owner needs consent scoped more narrowly than all outside-content memory writes.
