# A secret reaches only the native call that needs it

Read before touching a password field, a stored token, a clipboard reader, a credential probe or text that could carry a secret.

## The approach

A typed secret reaches only the native call that needs it. A stored secret is looked up by account and never printed, logged or placed in argv or a file. Status carries presence alone. Probes do not unlock the store. Clipboard readers refuse secret-marked data and a run without `CLIPBOARD_STATE`.

The authority boundaries are [D061](../decisions/D061-no-manual-commands.md), [D098](../decisions/D098-networkmanager-only-secrets.md) and [D037](../decisions/D037-plugin-status.md).

## Why

Process arguments, IPC, status and configuration expose values beyond the operation that needs them. Closing stdin after a secret is also part of delivery: a non-terminal reader can wait for EOF before acting.

## Rules

- Send personal Wi-Fi passwords directly to `WifiNetwork.connectWithPsk`; hidden and enterprise Wi-Fi use the helper's stdin. IPC carries network identity alone. `scripts/smoke/rows/network.sh` checks secret isolation.
- Send VPN prompt passwords through the local `VpnLogic.submitConnect` call to nmcli's stdin, then close it. Never carry the password through IPC. `scripts/test-vpn-logic.js` checks transport.
- Feed shared-profile passwords to `qrencode` on stdin. `scripts/test-network-share.py` checks this boundary.
- Never log, publish or return lock or polkit passwords through IPC. `scripts/test-lock-model.js` and `scripts/test-polkit-model.js` check their models.
- Send stored secrets to `secret-tool` on stdin alone. `scripts/test-plugin-status.js` checks that no secret enters argv, replies, logs or status.
- Probe presence with `secret-tool search` without `--unlock`, with stdout sent to `/dev/null`. A failure names only the account. `scripts/test-notifications-token-status.sh` checks the probe.
- Check both clipboard secret marks before reading data. Refuse a missing `CLIPBOARD_STATE`. `scripts/test-clipboard.py` checks these conditions.
- Never include copied data in logs or IPC refusals; report length alone. Review holds this rule; no check reads those outputs for copied data.
- Mask credentials in package failure output through `PackageReview.failureLines`, and never echo prompt passwords in the producing step. `scripts/fixtures/pkg-review/failure-test.js` checks recognized forms. Arbitrary passwords have no general masking pattern; review holds that limit.
- Never log Bluetooth codes, passkeys, PINs or answers. Mask digit runs in unknown prompts. `scripts/test-bluetooth-agent.js` checks this boundary.
- Never run real PAM, polkit, sudo or keyring actions in tests. The sole exception is the stored key read by the [Jarvis self-test](validation.md#jarvis-self-test). `scripts/smoke/rows/auth-sentinel.sh` checks isolation.

## The canonical example

Copy `shell/Core/SecretWriter.qml` for a masked-field writer. For OAuth, follow `shell/plugins/vgs.google-drive/bin/google-drive`: authorization output goes to `secret-tool store` through stdin. `scripts/test-google-drive-runner.js` checks that transport.

## Revisit when

A second secret store is needed, or an OAuth round trip cannot use the existing writer.

## Not governed

Setup placement and execution belong to [commands-are-data.md](commands-are-data.md) and the vgs-plugin [API reference](../../.agents/skills/vgs-plugin/references/api.md). NetworkManager owns its secret store under [D098](../decisions/D098-networkmanager-only-secrets.md).
