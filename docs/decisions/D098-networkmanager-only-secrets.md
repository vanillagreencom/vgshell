# D098: NetworkManager only; secrets stay in NetworkManager's store

[← Decision Index](INDEX.md)

**Date**: 2026-10-02
**Status**: Active
**Research**: [System plan](https://linear.app/vanillagreen/issue/VGS-697)

**Context**: Wi-Fi joining needs a saved profile and a secret store. VGS must show a stopped or absent backend without replacing the owner's network service.

**Decision**: The Network plugin uses NetworkManager through Quickshell. It never switches network stacks. A masked field sends the Wi-Fi password directly to NetworkManager. NetworkManager stores the password. This is a scoped exception to [D061](D061-no-manual-commands.md)'s VGS libsecret storage rule.

**Rationale**:

- NetworkManager owns the profile and its password together. A second VGS secret store would duplicate their ownership.
- Quickshell's in-process API keeps the password off process arguments and VGS IPC.
- Omarchy's Network flyout at `basecamp/omarchy` commit `75250d37acdf19121efe2af85b3732b8cf248980` calls `connect()` first and reprompts after credentials fail. VGS uses the same recovery rule.
- Omarchy owns scanning in each panel instance. VGS owns scanning in one service because a pane and several flyouts can be open together. One view cannot stop another view's scanner.
- VGS reads the documented service-state and permission interfaces because Quickshell's constant backend identity cannot report installation state or authorization refusal. A failed probe stays unavailable.

**Revisit When**: Quickshell supports another backend with equivalent profile and secret ownership, or NetworkManager changes its secret-store contract.

**Saved-network sharing**: An explicit Share reads only the selected NetworkManager profile's secret. The view-owned helper feeds the escaped Wi-Fi payload to `qrencode` through stdin. Password and payload exist only in the owned processes and their private pipes. The encoded matrix exists only in the view. Closing the view clears its state, stops the helper and destroys the owner, collector and matrix. Nothing writes a password or matrix to VGS status, IPC, logs, files or configuration. This keeps NetworkManager as the sole persistent secret store. Omarchy's Wi-Fi QR plugin at `5c4da021469517449770579793b37ce26d0a0d48` supplies the format and encoder approach.

**Verification**: `scripts/test-network-logic.js`, `scripts/test-network-share.py`, `scripts/qml-tests/tst_qrmatrix.qml` and `scripts/smoke/rows/network.sh`.

**References**: [Network contract](../architecture/network.md), [Quickshell WifiNetwork](https://quickshell.org/docs/v0.3.1/types/Quickshell.Networking/WifiNetwork/), [Omarchy Network](https://github.com/basecamp/omarchy/tree/75250d37acdf19121efe2af85b3732b8cf248980/shell/plugins/panels/network).
