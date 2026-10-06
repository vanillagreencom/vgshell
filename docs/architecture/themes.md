# A theme is one judged package

Read before touching a theme package, the package judge, the theme runner, or an install verb.

## The approach

A theme is a directory: `theme.json` is the shell document, `terminal.json` holds the ANSI slots, and `targets/` holds curated application files. One pure judge, `ThemeLogic.acceptPackage` in `shell/Commons/ThemeLogic.js`, decides from file text alone whether a package is accepted, and the runner `bin/vgshell-theme-judge` does every read and write. The shipped `vgs` package is the reserved revert no install can hide. An installed package has plugin trust: on a target whose files run code, its curated file is dropped and the template rendered instead ([D031](../decisions/D031-installed-themes-render-code-targets.md)). The install verbs share the plugin manager's git handling: no hook, submodule or package file runs, and a package is judged in a staging directory before it lands.

## Why

A theme someone shared, or its update, must not run code in the user's editor or terminal, and a theme has no disabled-for-review step. A judge with no I/O runs under node, so a script and the shell cannot disagree about a package. Nothing infers light or dark from a name or a colour: the package states `scheme.mode`.

## Rules

- Do judge a package through `ThemeLogic.acceptPackage` with file text only; the judge does no I/O. `scripts/test-theme-logic.js` pins each refusal.
- Never name an installed package `vgs`; the shipped `vgs` is always the revert. `scripts/test-vgshell.sh` pins the refusal.
- Do mark every target `runsCode`, and never take an installed package's curated file on such a target: drop it, name it in `dropped`, render the template. `scripts/test-vgshell-targets.sh` pins both.
- Never follow a symlink below a package directory; a linked `theme.json` or `terminal.json` refuses the package. `scripts/test-vgshell-package-links.sh` pins it.
- Do keep every shipped package passing the judge offline; `bin/vgshell-theme-judge packages` runs from `scripts/validate` for `themes/`.
- Do hold `theme.lock` for apply, follow, reload and every install verb; a second holder exits 75 `busy`. `scripts/test-vgshell.sh` pins it with a lockless control.
- Do clone into a staging directory beside `themes/` and judge there, so no list reads half a package; never let a git call inherit the lock descriptor. `scripts/test-vgshell.sh` pins both.
- Do ask before a git update, as a plugin update asks, because the follow applies files that applications run at once, and roll back a version the judge refuses. `scripts/test-vgshell.sh` pins both.
- Never remove a shipped package, a symlink or a file; remove deletes an installed directory only. `scripts/test-vgshell.sh` pins it.
- Do stage a file by `replaceFile` in `bin/lib/judge-files.js`: owner-only until full, then the kept mode. `scripts/test-judge-files.js` pins it.

## The canonical example

`themes/vgs/`: the shipped defaults, one `theme.json`, one `terminal.json`, and a curated file only where a target's own format has no template. Copy it.

## Revisit when

Packages carry signatures or a trusted-author list, or an installed theme needs a code file with no template.

## Not governed

How a package lands on the applications, which is [theme-apply.md](theme-apply.md); what a target is, which is [theme-targets.md](theme-targets.md); the first-party catalog, which is [theme-catalog.md](theme-catalog.md).
