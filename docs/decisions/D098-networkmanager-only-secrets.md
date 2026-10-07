# D098: NetworkManager only, and a Wi-Fi secret stays in NetworkManager's store

[← Decision Index](INDEX.md)

**Date**: 2026-10-02
**Status**: Active
**Research**: the System plan attached to [VGS-697](https://linear.app/vanillagreen/issue/VGS-697)
**Refines**: [D061](D061-no-manual-commands.md)

**Decision**: The Network plugin uses NetworkManager through Quickshell's in-process API and a plugin helper for hidden and enterprise Wi-Fi. It never switches network stacks. It sends a Wi-Fi password straight to NetworkManager, which stores it. No VGS file, status, IPC or log holds a network secret.

**Why**: NetworkManager owns the profile and its password together, so a second VGS store would split ownership. Native calls and the helper's stdin keep the password off process arguments and VGS IPC. `scripts/test-network-logic.js` holds the plugin's judge.

**Rejected**: A VGS libsecret copy of the password under D061. It duplicates ownership of a secret NetworkManager already keeps.

**Revisit when**: Quickshell supports another backend with equivalent profile and secret ownership, or NetworkManager changes its secret-store contract.
