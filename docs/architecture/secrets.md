# A secret reaches only the native call that needs it

Read before touching a password field, a stored token, a clipboard reader, a probe of a credential, or any text that could carry a secret.

## The approach

A secret the user types, a Wi-Fi password, a lock password, a polkit answer, reaches only the native call that needs it: no VGS IPC call, argv, status record, configuration file or log line. A stored secret, a Slack token, is looked up by account through `secret-tool` and never printed, logged or placed in argv or a file; its presence, never its value, enters status. A clipboard copy marked secret is never read, and a run with no `CLIPBOARD_STATE` is refused. A probe reads a credential's presence without unlocking the store. The choices are [D061](../decisions/D061-no-manual-commands.md), [D098](../decisions/D098-networkmanager-only-secrets.md) and [D037](../decisions/D037-plugin-status.md).

## Why

An argument sits in every process list, an IPC reply in the shell's log, a status value in every instance's memory, and a configuration file in the user's backups. Only `wl-paste` ties the secret mark to the data on stdin; without the variable, the next copy's types could pass for this one's. `secret-tool` reads a non-terminal stdin to its end, so the writer closes stdin after the secret.

## Rules

- Do send a Wi-Fi password straight to `WifiNetwork.connectWithPsk`; the IPC action carries the network identity alone. `scripts/smoke/rows/network.sh` reads the joined PSK absent from status, configuration and logs.
- Never put a shared profile's password in argv or a file; feed `qrencode` on stdin. `scripts/test-network-share.py` pins it with controls that put the secret in argv and in a file.
- Never log, publish or answer a lock or polkit password over IPC. `scripts/test-lock-model.js` and `scripts/test-polkit-model.js` pin it.
- Never put a secret on an argv, in a log line, a reply or a status value; it reaches `secret-tool` on stdin alone. `scripts/test-plugin-status.js` pins it with a copy that puts it on the argv.
- Never read a token in a probe; `secret-tool search` without `--unlock`, stdout to `/dev/null`. `scripts/test-notifications-token-status.sh` pins it, and a `secret-tool` failure names the account only.
- Do check both clipboard secret marks before reading any data, and refuse a run with no `CLIPBOARD_STATE`. `scripts/test-clipboard.py` and `scripts/smoke/rows/clipboard.sh` pin it.
- Never put copied data in a log line or an IPC refusal; print its length alone.
- Never log a Bluetooth code, passkey, PIN or answer; log an unknown prompt with every digit run as `#`. `scripts/test-bluetooth-agent.js` pins it.
- Never run a real PAM, polkit, sudo or keyring step in a test, and never read a secret from a credential store in a migration. `scripts/smoke/rows/auth-sentinel.sh` and `scripts/test-migration-slack-photos.sh` pin it.

## The canonical example

`shell/Core/SecretWriter.qml`: the one writer, the secret on stdin, stdin closed after it, the reply naming the account alone. Copy its shape for a new secret.

## Revisit when

A second secret store is needed, or a step needs an OAuth round trip no masked field can carry.

## Not governed

Where a setup step's button sits and what it may run, which is [status.md](status.md); NetworkManager's own store, which [D098](../decisions/D098-networkmanager-only-secrets.md) leaves to it.
