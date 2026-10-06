# One package-manager table, and the shell never elevates for a package

Read before touching `shell/Core/PackageManagers.js`, `vgshell pkg`, an update check, or any step that installs or removes a package.

## The approach

`shell/Core/PackageManagers.js` is the one table every install, remove, upgrade and update check reads: one entry per manager with its argv steps, its queries, their exit statuses and a canned output for each parser. A package change runs only where the user answers the prompt, in a terminal through `vgshell pkg run`, and the shell process never elevates. The choice is [D034](../decisions/D034-one-package-manager-table.md).

## Why

A shell process that elevated would hold root with no one watching, and separate per-flow lists disagree on argv. The shell removes `VGSHELL_RUNNER_PID` only from the programs it opens for the user, so a plugin process never elevates and a user's own terminal is not refused. A query whose exit status the table does not list cannot be read, and a parser given a changed format must fail rather than miscount.

## Rules

- Never name an elevation command in a step or a picker, never refresh a pacman-family database without upgrading, and never pass `--noconfirm` or `-y`. `scripts/test-vgshell-pkg-table.js` plants each.
- Do refuse `run` in a process the shell started and without a terminal, and hand every step to the manager as argv, never through a shell string. `scripts/test-vgshell-pkg-run.sh` pins both.
- Do run steps and queries from `$HOME`, so a project's `mise.toml` cannot change what a check counted.
- Never add a query whose exit statuses the table does not list, and give every parser a canned output under `scripts/fixtures/pkg/`. The table suite's outcome and parser rows pin both.
- Do run one check at a time under the lock, and end a query past its timeout with its process group. The `check` rows of `scripts/test-vgshell-pkg-cli.js` pin both.
- Do give nix no steps and no check; a NixOS system changes through its configuration.

## The canonical example

The pacman entry of `shell/Core/PackageManagers.js`: steps as argv, an owner query with its listed exit statuses, and its fixture under `scripts/fixtures/pkg/`. Copy it for a new manager.

## Revisit when

A supported manager cannot be expressed as argv steps, or the shell must change a package with no terminal open.

## Not governed

Which commands a plugin needs, which is [requirements.md](requirements.md); the one elevation a shell process performs, the Chromium policy writer, which is [D029](../decisions/D029-chromium-policy-writer.md).
