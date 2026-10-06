# D085: The Bluetooth agent is a core-lent exclusive capability over bluetoothctl

[← Decision Index](INDEX.md)

**Date**: 2026-10-01
**Status**: Active
**Research**: the System plan attached to [VGS-697](https://linear.app/vanillagreen/issue/VGS-697)
**Refines**: [D012](D012-core-owns-lent-objects.md)

**Decision**: The core lends an exclusive `bluetoothAgent` capability. The first lease starts one `bluetoothctl --agent KeyboardDisplay` child and the last release ends it, so the shell claims BlueZ's default agent only while a holder pairs or waits. Every line the core writes starts with 17 spaces.

**Why**: Quickshell 0.3.1 has no agent type and cannot export a D-Bus object, so BlueZ's own client is the only agent, and the default agent is a session-wide role D012 gives the core. bluetoothctl prints device names raw with line breaks, so a nearby device can forge any output line, and a held prompt takes the next stdin line whatever it says; the padding keeps a core-written command from ever reading as a PIN. `scripts/test-bluetooth-agent.js` replays transcripts.

**Rejected**: `bt-agent -c NoInputNoOutput` in a user unit. It accepts every pairing without asking the user.

**Revisit when**: Quickshell ships a BlueZ agent type, BlueZ changes its default-agent stack, or bluetoothctl changes its prompt text.
