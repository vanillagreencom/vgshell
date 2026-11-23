# D139: Jarvis Always allow saves a standing grant for any permission card

[← Decision Index](INDEX.md)

**Date**: 2026-11-22

**Status**: Active

**Research**: [VGS-2728](https://linear.app/vanillagreen/issue/VGS-2728), owner Slack 1795391848.147359 ("Yes, I want an always allow option on any safety blocks/prompts.")

**Supersedes**: [D070](D070-jarvis-action-policy.md), in part: that a physical approval, and a confirmation turn taint raises, wait for the user each time. Taint still never lowers either; a saved key the user chose does.

**Decision**: Every Jarvis Voice permission card offers Always allow: physical confirms, confirms raised in a tainted turn, external confirms the Trusted profile still asks for, and release questions, clipboard text included. A Yes with the box checked saves the request's key in the `vgs.jarvis` setting `alwaysAllow`, and a call whose key is saved runs with no card, in any turn. A key names one kind of request: the tool, its effect, its input target and every path the gate judged, each part by its field, a coding task's agent and account, or a release label and its remote recipients. The card shows the line Policy builds from the same parts. Policy alone names and matches keys; the router and the engine save one only after the rejudge and the audit row. `fleet.forward` takes no key, since its consent record must cite one accepted confirmation ([D134](D134-live-session-forwarding-consent.md)).

**Why**: The owner decided it: a question he must answer again every time teaches him to stop reading it. A key that names its target and paths keeps the grant to the kind he allowed, and the audit row still records each action with the key's kind.

**Rejected**: Withholding the box from physical, tainted-turn and external cards. The owner asked for it on every prompt.

**Revisit when**: The owner narrows the grant, a tainted turn's saved key is abused by outside content, or the Jarvis package accepts a standing grant in a forward's consent record.
