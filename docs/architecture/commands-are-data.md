# Commands are data, and they run where the user sees them

Read before touching the `tui` capability, a manifest's `tui` or `systemSteps` key, `bin/vgshell-tui`, `shell/Core/PackageManagers.js`, `vgshell pkg`, `bin/vgshell-system`, `vgshell sudo grant`, a udev rule VGS ships, the Dev Tools catalog, the requirement notice's install, or any place a plugin's or a user's text could become a command or a flow could ask the user a question or a password.

## The approach

Text a plugin, a catalog or a user supplies never becomes shell code, and anything that asks the user or needs root runs in a terminal the user sees. A plugin declares its scripts as data in its manifest's `tui` key and opens them by name through `shell.tui`; the Dev Tools catalog stores argument arrays. `shell/Core/PluginLogic.js` makes every decision about what a plugin may open. One launcher, `bin/vgshell-tui`, runs the command as an argv list in a floating terminal that outlives the shell, and the core learns that a run ended by blocking on the run's own lock ([D043](../decisions/D043-tui-run-ends-by-lock-release.md)). Every install, remove, upgrade and update check reads the one table in `shell/Core/PackageManagers.js`, and a package change runs only through `vgshell pkg run` in that terminal. Every privileged one-time setup is one row of the closed table in `bin/vgshell-system`: a plugin names a row in its manifest's `systemSteps` and never supplies a root command. The shell process never elevates. The choices are [D033](../decisions/D033-floating-tuis-are-core.md), [D034](../decisions/D034-one-package-manager-table.md), [D081](../decisions/D081-system-steps-closed-core-table.md) and [D036](../decisions/D036-time-boxed-passwordless-sudo-grant.md).

## Why

A string that reaches a shell becomes code, and a plugin's or a catalog's text would then run outside the shell with the user's privileges. Reading the same data from a judged manifest keeps a launcher able to list other plugins' tools without naming those plugins ([D005](../decisions/D005-kinds-are-surfaces-no-dependencies.md)). A password typed into the shell process would be a secret in a QML field, a log or IPC, and a shell process that elevated would hold root with no one watching; a terminal the user sees is the one place a prompt can be answered. Separate per-flow package lists disagree on argv, and a query whose exit status the table does not list cannot be read. A plugin must never hold root commands the core did not judge, and a user-writable record could steer `undo` into disabling a unit VGS never touched.

## Rules

### Commands as data

- Do declare each script under the manifest's `tui` key, in the plugin's `tui/` directory, with capability `tui`; `PluginLogic.tuiError` refuses the rest, pinned by `scripts/test-plugin-logic.js`.
- Do ship each script as a regular file with its owner's execute bit, reached through no symbolic link; `bin/vgshell-scan` follows links when it publishes a snapshot, so a link would publish whatever it points at. `bin/lib/check-manifests.js` refuses one.
- Never open a script the manifest does not declare, from anything but the published snapshot ([D014](../decisions/D014-source-revisions-are-published-snapshots.md)), or while the plugin is disabled. `scripts/test-tui-logic.js` and `scripts/smoke/rows/tui.sh` pin it.
- Do key a core TUI `core/<name>` whatever its arguments, so one plugin update runs at a time, and answer a busy key by revealing the live window, never by a second terminal. `scripts/test-tui-logic.js` pins both.
- Never let a launcher that is `missing` start a process; answer `launcher-missing` and probe once. `scripts/smoke/rows/tui.sh` swaps the launcher for one that finds no terminal.
- Never hand a TUI command or a package step to a shell string; each is argv. `scripts/test-vgshell-tui.sh` pins the launcher with a control that runs `bash -c`, and `scripts/test-vgshell-pkg-run.sh` pins the package steps.

### Dev Tools catalog

- Never write a shell string in the catalog; `launch`, `postInstall.exec`, `postRemove.exec` and the mise steps are argv. `scripts/check-devtools-catalog.js` refuses one, and `scripts/test-check-devtools-catalog.js` plants each.
- Never use `sh -c`, `eval`, `python -c`, `node -e`, `env -S` or a versioned interpreter form, and never `@latest`; a bare name is the current version. `scripts/check-devtools-catalog.js` pins each.
- Do bind a catalog database port to `127.0.0.1`, use every `brand` key in `Appearance.js`, and name only `PackageManagers.js` ids in a package map. `scripts/check-devtools-catalog.js` pins each.

### Floating TUIs

- Do launch every flow that asks the user anything, a password or a y/N, through `bin/vgshell-tui`, and hand `present` everything it needs in argv. `scripts/test-vgshell-tui.sh` pins it.
- Do fork the terminal with `setsid -f`; Quickshell kills its children when the shell stops, and a restart during an install must not kill the install. `scripts/test-vgshell-tui.sh` pins it.
- Do run a plugin's script from a private copy of its whole published snapshot; a restart removes old snapshots while a script may still read its plugin's files. `scripts/test-vgshell-tui.sh` pins it.
- Do strip `VGSHELL_RUNNER_PID` from the terminal's environment; a single-instance terminal hands it to later windows, and `vgshell pkg run` refuses it. `scripts/test-vgshell-tui.sh` pins it.
- Never source `gum.env`; parse it, and one bad line exports nothing. Put the Done or Failed prompt on `/dev/tty`, not stdout. `scripts/test-vgshell-tui.sh` pins both.
- Do let the presenter, the only process that knows when the command ended, write the run's record whole under a hidden name and rename it; never rewrite one, a new state is a new file, and never let the command inherit the key lock or the run lock. `scripts/test-vgshell-tui.sh` pins each.
- Do treat the directory listing as the fast path and the wait on the run lock as the completion guarantee, since a single-instance terminal's launcher exit says nothing about the run and `FolderListModel` can miss a change under load; never start two waits for one run, and never poll a process. `scripts/qml-tests/tst_tui_records.qml` and `scripts/test-tui-logic.js` pin both.
- Do keep a key's last ended record across a shell restart. `scripts/test-vgshell-tui.sh` pins it.
- Do hold one sudo session per script; a nested session joins a live owner. `scripts/test-tui.sh` pins it with a stand-in `sudo`.
- Do pick a size class from `HyprlandLayer.TUI_WINDOWS` in `shell/Core/HyprlandLayer.js`, never a geometry. Whether a terminal floats depends only on its desktop entry's `X-TerminalArgAppId` key; VGS chooses no terminal.

### Packages

- Never name an elevation command in a step or a picker, never refresh a pacman-family database without upgrading, and never pass `--noconfirm` or `-y`. `scripts/test-vgshell-pkg-table.js` plants each.
- Do refuse `vgshell pkg run` in a process the shell started and without a terminal. The shell removes `VGSHELL_RUNNER_PID` only from the programs it opens for the user, so a plugin process never elevates and a user's own terminal is not refused. `scripts/test-vgshell-pkg-run.sh` pins it.
- Do run steps and queries from `$HOME`, so a project's `mise.toml` cannot change what a check counted.
- Never add a query whose exit statuses the table does not list, and give every parser a canned output under `scripts/fixtures/pkg/`, so a parser given a changed format fails rather than miscounts. `scripts/test-vgshell-pkg-table.js` pins both.
- Do run one check at a time under the lock, and end a query past its timeout with its process group. `scripts/test-vgshell-pkg-cli.js` pins both.
- Do give nix no steps and no check; a NixOS system changes through its configuration.

### System steps

- Never add a root action outside the table in `bin/vgshell-system`; a manifest's `systemSteps` names table rows only. `scripts/test-vgshell-system.sh` reads `PluginLogic.SYSTEM_STEPS` against the script's table, and `scripts/test-plugin-logic.js` pins the manifest rule.
- Do write the record, root-owned under `/var/lib/vgshell/system/`, before the commands, so a partial failure is on record, and undo only the recorded change, for the caller's uid, in the boot that made it. `scripts/test-vgshell-system.sh` pins both.
- Do probe real access, never a file's presence; a probe that cannot answer reads `unknown`, never `ready`. `scripts/test-vgshell-system.sh` pins the `unknown` state.
- Never overwrite a destination VGS did not write; refuse a symlink destination and a foreign file as `foreign`. `scripts/test-vgshell-system.sh` pins it.
- Do grant a device by `uaccess` alone, in a rule that sorts before `73-seat-late.rules`, which applies the tag; a `GROUP` or `MODE` grant reaches SSH and other-seat sessions.
- Never start greetd from inside a session, enable it only, and refuse the greeter step unless the install tree is root's and writable by no one else, since the greeter account runs where every password is typed ([D101](../decisions/D101-greeter-host-and-greeter-system-step.md)). `scripts/test-vgshell-system.sh` pins both.
- Do resolve every command of the sudo grant's root half in the system directories alone, drop the sudo credential before and after each verb, and run the root half under `bash -p` with `PATH`, `LC_ALL` and `SUDO_UID` alone. `scripts/test-vgshell-sudo-grant.sh` pins each under `unshare -r`.
- Do publish a grant by rename only after its expiry timer is armed and the boot cleanup is in place, with a `NOTAFTER` rule sudo ends itself. `scripts/test-vgshell-sudo-grant.sh` pins it.
- Do write nothing and run no sudo on NixOS; print the configuration snippet instead, for the grant the `security.sudo.extraRules` snippet. `scripts/test-vgshell-sudo-grant.sh` and `scripts/test-vgshell-system.sh` pin the `nixos` state.
- Never let a step reach the host's devices, units or sudo in the sandbox. `scripts/smoke/rows/system-steps.sh` and `scripts/smoke/rows/auth-sentinel.sh` pin it.

### Consent

- Do start every install, root change and plugin or theme change from the user's own press, and show what runs before it runs: a system step prints every root command by its path and asks one question `VGS_TUI_UNATTENDED` never answers, then runs only the plan shown. `scripts/test-vgshell-system.sh` and `scripts/test-vgshell-sudo-grant.sh` pin it.
- Do let the package manager ask for root in the floating terminal, never in the shell: the requirement notice's Install opens the core TUI `core/requirements-install`, one manager per press. Which requirements a notice lists, and when a plugin's offer rests, are [overview.md](overview.md)'s.
- Do keep the question a command asks on its terminal: a core TUI that adds, updates or removes a plugin or a theme runs without `--yes`, and the prompted theme add asks before it applies the new theme ([D007](../decisions/D007-install-runs-no-plugin-code.md)).
- Do open the requirement notice instead of a plugin's script while a command the script needs is missing. `scripts/test-tui-logic.js` pins it.

## The canonical example

`scripts/smoke/fixtures/plugins/acme.tui/`: a fixture plugin with one declared script, opened by name. Copy it. For a root setup, `scripts/smoke/fixtures/plugins/acme.system/` names a step in a status action and nothing else; the step itself is a row in `bin/vgshell-system`.

## Revisit when

`xdg-terminal-exec` drops `--app-id`, gum changes its environment names, a TUI needs a geometry no size class covers, a supported package manager cannot be expressed as argv steps, the shell must change a package with no terminal open, a step needs a privilege a sudo command cannot give, a distribution ships these grants itself, or a Flatpak presence and launch model exists for the catalog.

## Not governed

Which commands a plugin needs and the requirement notice's queue, which are [overview.md](overview.md); the functions of the presentation library, which `bin/lib/tui.sh` lists in its header; the one elevation a shell process performs, the Chromium policy writer, which is [D029](../decisions/D029-chromium-policy-writer.md); the greeter host's own rules, which are [D101](../decisions/D101-greeter-host-and-greeter-system-step.md) and the `vgs.greeter` README.
