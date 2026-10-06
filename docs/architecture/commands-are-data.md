# A command a plugin or a catalog supplies is data

Read before touching the `tui` capability, a manifest's `tui` key, the Dev Tools catalog, or any place a plugin's or a user's text could become a command.

## The approach

A plugin declares its scripts as data in its manifest's `tui` key and opens them by name through `shell.tui`; it never hands the shell a command string, and the shell hands the terminal an argv list. The Dev Tools catalog stores argument arrays, and its judge refuses shell syntax and every interpreter-evaluation form. Every decision about what a plugin may open is made once in `shell/Core/PluginLogic.js`. The choice is [D033](../decisions/D033-floating-tuis-are-core.md).

## Why

A string that reaches a shell becomes code, and a plugin's or a catalog's text would then run outside the shell with the user's privileges. Reading the same data from a judged manifest keeps a launcher able to list other plugins' tools without naming those plugins ([D005](../decisions/D005-kinds-are-surfaces-no-dependencies.md)).

## Rules

- Do declare each script under the manifest's `tui` key, in the plugin's `tui/` directory, with capability `tui`; `PluginLogic.tuiError` refuses the rest, pinned by `scripts/test-plugin-logic.js` and run offline by `bin/lib/check-manifests.js`.
- Never open a script the manifest does not declare, from anything but the published snapshot, or while the plugin is disabled. `scripts/test-tui-logic.js` and `scripts/smoke/rows/tui.sh` pin it.
- Do key a core TUI `core/<name>` whatever its arguments, so one plugin update runs at a time, and answer a busy key by revealing the live window, never by a second terminal. `scripts/test-tui-logic.js` pins both.
- Never let a launcher that is `missing` start a process; answer `launcher-missing` and probe once. `scripts/smoke/rows/tui.sh` swaps the launcher for one that finds no terminal.
- Never write a shell string in the catalog; `launch`, `postInstall.exec`, `postRemove.exec` and the mise steps are argv. `scripts/check-devtools-catalog.js` refuses one, and `scripts/test-check-devtools-catalog.js` plants each.
- Never use `sh -c`, `eval`, `python -c`, `node -e`, `env -S` or a versioned interpreter form, and never `@latest`; a bare name is the current version. `scripts/check-devtools-catalog.js` pins each.
- Do bind a catalog database port to `127.0.0.1`, use every `brand` key in `Appearance.js`, and name only `PackageManagers.js` ids in a package map. `scripts/check-devtools-catalog.js` pins each.

## The canonical example

`scripts/smoke/fixtures/plugins/acme.tui/`: a fixture plugin with one declared script, opened by name. Copy it.

## Revisit when

A Flatpak presence and launch model exists for the catalog, or `xdg-terminal-exec` drops `--app-id`.

## Not governed

The terminal itself and the run's record, which is [tui.md](tui.md); the package table a step installs through, which is [packages.md](packages.md).
