# D127: A fixed handoff target for an action with one receiver

[← Decision Index](INDEX.md)

**Date**: 2026-11-06

**Status**: Active

**Research**: [VGS-2190](https://linear.app/vanillagreen/issue/VGS-2190)

**Decision**: A plugin may name a fixed handoff target when the user's action has exactly one meaningful receiver. Local Sync picks `handoff:vgs.automations/sync-job` and `handoff:vgs.agent-debug/diagnose` from `shell.handoff.targets` by key. Add opens Automations' editor on a sync draft. Remove of a VGS-created job opens that automation in Automations' own Remove confirmation. Send to agent opens Agent Debug's Diagnose draft filled with the job's facts. While its target is missing, Add or Send to agent is off and its `disabledReason` says why. Remove of a VGS-created job says why in the panel when the user presses it. Both receivers start nothing until the user presses Save, Remove or Run; Diagnose never starts an agent run on its own. A manifest `handoffs` entry may declare the optional `"kind": "action"` for a receiver that opens a plugin's own draft rather than a conversation. A conversation receiver opens an editable draft. An action receiver opens its own plugin's draft or confirmation of the handed facts. Every receiver preserves an occupied draft and starts no turn. An entry with no kind keeps its meaning as a conversation target, so Jarvis's manifest does not change. A consumer that lists conversation targets, such as Agent Debug's Agent select, skips targets of kind `action`.

**Why**: The owner's delegate Jarvis chose the rule on 2026-11-06 (directive 1794016163-2601843-24725) and added the receiver kind in answer 1794017148-4160132-15325. A handoff key is opaque and saved by the user's choice, but these three actions have no second receiver to choose. The handoff name pattern `^[a-z0-9][a-z0-9-]*$` in `shell/Core/ConfigLogic.js` requires `sync-job`, not `syncJob`. Local Sync reads the Automations store file, not `automations list --json`. That program lives in vgs.automations' own folder, and a plugin cannot require it, because a requirement is a command on the system, never another plugin ([D035](D035-manifest-requirements.md)). Running it would also start Automations' engine on every store change. `scripts/test-local-sync-logic.js` loads `AutomationsLogic.js`, so a change to the store format fails Local Sync's test.

**Rejected**: Two Settings selects where the user chooses each target. This keeps the overview's handoff rule to the letter, but Add and Send to agent stay off until setup, against [D075](D075-consumer-features-need-no-developer-setup.md). A new typed core route needs `shell/Core/*` files that other running lanes change, so Local Sync would ship without the actions. Agent Debug excluding the Automations target by name is brittle and names a second plugin.

**Revisit when**: A second plugin needs a fixed target with more than one meaningful receiver, or the core gains a typed route for these calls.
