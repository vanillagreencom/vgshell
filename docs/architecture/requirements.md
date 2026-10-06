# A requirement is a command, never a plugin

Read before touching a manifest's `requirements`, `config/requirements.json`, the scan's probe, the requirement notice, or the `requirements` and `doctor` capabilities.

## The approach

A manifest's `requirements` lists the external commands a plugin runs, each with its package per manager; `config/requirements.json` lists the core's. The scan probes each command once and reports the missing ones, and the one install path is a `vgshell pkg run` the user starts from the requirement notice, a TUI or the add command's terminal question. The core, not a plugin, owns the one centred notice surface. The choice is [D035](../decisions/D035-manifest-requirements.md).

## Why

A requirement is a fact about the system, so no plugin names another plugin and [D005](../decisions/D005-kinds-are-surfaces-no-dependencies.md) holds. The rescan confirms an install by probing the command, because a requirement is a command and not a package. A dotted lower-case command reads as a plugin id, so a command such as a filesystem tool is declared under an undotted name of the same package. NixOS changes through its own configuration, so nix gets `by-hand`.

## Rules

- Never name a plugin in `requirements`; `requires` and a dotted command are refused. `scripts/test-plugin-logic.js` pins both.
- Do keep `config/requirements.json` to core commands; each plugin owns its own, and a command only an extra runs sits under that extra's entry ([D075](../decisions/D075-consumer-features-need-no-developer-setup.md)). `scripts/test-plugin-logic.js` and `scripts/test-plugin-extras.js` pin it.
- Never install or elevate without the user; install is a `vgshell pkg run` in a terminal the user watches, and the manager never takes `--noconfirm`. `scripts/test-vgshell-requirements.sh` and `scripts/test-vgshell-pkg-table.js` pin both.
- Do ask a running shell to rescan after every package change, however it ends. `scripts/test-vgshell-requirements.sh` pins it.
- Do raise a notice only for commands its owner declares, never for optional commands alone, and keep the installing notice in front until one scan after its run ended. `scripts/test-notice-logic.js` pins each.
- Never bind a drawn property to a command line; a command sits behind "Show command" alone. `scripts/check-user-commands.py` refuses it under `drawn-command-line` ([D061](../decisions/D061-no-manual-commands.md)).
- Do rest a plugin's own offers after Not now, and never rest the user's own triggers. `scripts/test-notice-logic.js` pins it.

## The canonical example

`scripts/smoke/fixtures/plugins/acme.needs/`: a manifest that declares one missing command with its packages, and the notice the core raises for it. Copy it.

## Revisit when

A plugin needs a requirement that is not a command on PATH, or a real command cannot be declared under an undotted name.

## Not governed

The package-manager table the install runs through, which is [packages.md](packages.md); the setup steps a status row offers, which is [status.md](status.md).
