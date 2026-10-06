# The shell never judges a package

Read before touching `ThemeRunner`, the `theme` capability, or a plugin view that applies, installs or previews a theme.

## The approach

Every theme action a plugin takes is one `vgshell theme` process, run by `shell/Core/ThemeRunner.qml` on a queue of one job at a time, or on the download lane for a wallpaper fetch. The process's JSON line is the answer whatever its exit code, and the last result lives in the core runner, so a closed panel loses nothing. A plugin view's decisions live in a pure JavaScript file with no QML object and no I/O, and a package changes only as a whole: the browser has no override layer ([D025](../decisions/D025-no-theme-override-layer.md)).

## Why

A hidden panel is destroyed, so any result it owned would vanish mid-apply. The judge is the runner's, so a plugin that judged a package itself would be a second judge that drifts. A download of tens of megabytes on the queue would hold an apply behind it.

## Rules

- Do run one queue job at a time; a write interrupts a running read, and the read runs again for its original callers. `scripts/qml-tests/tst_themerunner.qml` and `scripts/smoke/rows/themes.sh` pin it.
- Do run a wallpaper download on its own lane, never on the queue. `scripts/smoke/rows/theme-browse.sh` pins it with a queued-download control.
- Do take the runner's JSON line as the result on exit 1, 3 or 75 too; only a failed start or an unreadable line takes a failure shape. `scripts/smoke/rows/themes.sh` pins it.
- Do refuse at once only what `ThemeLogic` judges without the runner: a malformed name, scope, path, screen or options. `scripts/test-theme-logic.js` pins it.
- Do register every `done` callback in its instance's lifetime; a destroyed instance's callback is dropped and the job still completes into `last`. `scripts/smoke/rows/themes.sh` pins it.
- Do queue the follow from the guarded instance alone, on every `scanFinished`. `scripts/smoke/rows/themes.sh` pins it.
- Do wait on `Theme.revision`, not on `done`, for the new theme; `done` can run before `ThemeSource` reloads.
- Do keep a view's decisions in a pure file such as `shell/plugins/vgs.themes/BrowserLogic.js`; `scripts/test-themes-browser.js` pins it.
- Never add an "Add to theme", "Remove" or "Delete" to the browser; user images live in the user's folder, and a package changes only as a whole.

## The canonical example

`shell/plugins/vgs.themes/`: the first-party client, one `BrowserLogic.js` for every decision, every action through the capability, every result read from `last`. Copy it.

## Revisit when

Users need a local change that follows upstream updates of an installed package, or a target needs a per-user value no package can carry.

## Not governed

What the runner does with a verb, which is [themes.md](themes.md) and [theme-apply.md](theme-apply.md); the wallpaper state, which is [theme-backgrounds.md](theme-backgrounds.md).
