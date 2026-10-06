# A theme is one judged package

Read before touching a theme package, the package judge, a theme target, the apply, the follow or `vgshell theme reload`, an install verb, `themes/catalog/` or a wallpaper download, the wallpaper state or the background surface, `ThemeRunner` and the `theme` capability, or a plugin view that applies, installs or previews a theme.

## The approach

A theme is a directory: `theme.json` is the shell document, `terminal.json` holds the ANSI slots, `targets/` holds curated application files and `backgrounds/` holds images. One pure judge, `ThemeLogic.acceptPackage` in `shell/Commons/ThemeLogic.js`, decides from file text alone whether a package is accepted. The runner `bin/vgshell-theme-judge` does every read and write, and the shell reaches it only as `vgshell theme` processes. The shipped `vgs` package is the reserved revert no install can hide. An installed package has plugin trust: on a target whose files run code, its curated file is dropped and the template rendered instead ([D031](../decisions/D031-installed-themes-render-code-targets.md)). The install verbs share the plugin manager's git handling: no hook, submodule or package file runs, and a package is judged in a staging directory before it lands.

A target is declarative data: one `target.json` plus templates under `themes/targets/<name>/`, rendered by the pure renderer `bin/lib/theme-render.js` from the package's resolved tokens. The runner never runs code a target or a package carries. A landed file reaches its application through a managed form that proves itself: an include line matched as a whole line, a symlink whose target is exactly a file in `theme/`, or a copy whose bytes match a render ([D030](../decisions/D030-managed-copies-for-watched-theme-directories.md)). A `select` sets one theme key in the application's own settings file and never creates the file ([D024](../decisions/D024-theme-apply-sets-one-theme-key-in-an-application-settings-file.md)). A `setup` names a privileged helper the target waits for, installed by one click. A per-application fact, such as how it reloads or which file it reads first, is a comment at the target's template.

An apply lands whole or not at all. It renders every target into a stage beside its destination, swaps the stage over the state `theme/` directory under the theme lock, and writes the shell document last, so the shell never reads half a theme ([D021](../decisions/D021-theme-apply-writes-beside-each-destination.md), [D022](../decisions/D022-theme-apply-keeps-managed-links-in-application-directories.md)). A target that fails to render costs only itself: the apply is `partial`, exit 3, and that target keeps its last files. A target with a reload hook stays `reload-pending` until the hook succeeds, and `vgshell theme reload` retries the pending set. A package that changed after its apply reaches the theme file only through a follow, which never overwrites a hand-edited theme file.

The first-party catalog in `themes/catalog/` is a set of packages with one judged index. Each entry installs with no network as an ordinary installed package with a marker, so the catalog origin creates no trust rule of its own: the same judge and the same target rules hold ([D038](../decisions/D038-judged-theme-catalog.md)). Wallpapers stay out of git: an entry pins an archive by size and SHA-256, and the download verifies against the pin under its own lock.

The wallpaper state is one file, `backgrounds.json`, with one writer, `bin/lib/theme-backgrounds.js`, which holds its contract, and one reader, the `vgs.themes` plugin's `WallpaperState.qml`. It holds a current image and a per-screen map ([D039](../decisions/D039-per-screen-wallpaper-map.md)). The background surface exists only while an image is drawn, and the user's own images live in the user folder, never in a package.

The shell judges no package. `shell/Core/ThemeRunner.qml` runs every theme action a plugin takes as one `vgshell theme` process, on a queue of one job at a time or on the download lane for a wallpaper fetch. The process's JSON line is the answer whatever its exit code, and the last result lives in the core runner, so a closed panel loses nothing. A plugin view's decisions live in a pure JavaScript file with no QML object and no I/O, and a package changes only as a whole: no layer overrides it ([D025](../decisions/D025-no-theme-override-layer.md)).

## Why

A theme someone shared, or its update, must not run code in the user's editor or terminal, and a theme has no disabled-for-review step. A catalog package comes from VGS, but a VGS update changes it with no review step either, so it earns no more trust than any installed package. A judge with no I/O runs under node, so a script and the shell cannot disagree about a package, and a plugin that judged a package itself would be a second judge that drifts. Nothing infers light or dark from a name or a colour: the package states `scheme.mode`.

A pure renderer makes a token path mean what it means to the shell, because the judge and the table are its arguments. A managed form that proves itself needs no marker file, and nothing the user placed is ever replaced. A CLI selects a theme by name in its own settings, so without the key the user sees nothing change, and the CLI's own default stands until the user has a settings file.

A rename in one directory is atomic, so the stage and the swap keep any reader from seeing half a theme. Writing the shell last keeps the displayed theme from running ahead of the applications. A written file changes nothing until its application re-reads it, so a target with a hook stays pending until the hook succeeds. A shipped package changes with a VGS update and an installed one with `vgshell theme update`; without a follow the theme file keeps stale bytes, and without the hash check a follow would overwrite a user's edit.

A wallpaper another program draws must not be covered by a bare background colour, so no image means no surface. An absent per-screen entry is the same-everywhere state, so nothing needs seeding. A download of tens of megabytes on the theme lock or the queue would hold every list and apply behind it. The pin, not the URL, is what makes downloaded bytes acceptable. A hidden panel is destroyed, so any result it owned would vanish mid-apply.

## Rules

### Packages

- Do judge a package through `ThemeLogic.acceptPackage` with file text only; the judge does no I/O. `scripts/test-theme-logic.js` pins each refusal.
- Never name an installed package `vgs`; the shipped `vgs` is always the revert. `scripts/test-vgshell.sh` pins the refusal.
- Never follow a symlink below a package directory; a linked `theme.json` or `terminal.json` refuses the package. `scripts/test-vgshell-package-links.sh` pins it.
- Do keep every shipped package passing the judge offline; `bin/vgshell-theme-judge packages` runs from `scripts/validate` for `themes/`.
- Do hold `theme.lock` for apply, follow, reload and every install verb; a second holder exits 75 `busy`. `scripts/test-vgshell.sh` pins it with a lockless control.
- Do clone into a staging directory beside `themes/` and judge there, so no list reads half a package; never let a git call inherit the lock descriptor. `scripts/test-vgshell.sh` pins both.
- Do ask before a git update, as a plugin update asks, because the follow applies files that applications run at once, and roll back a version the judge refuses. `scripts/test-vgshell.sh` pins both.
- Never remove a shipped package, a symlink or a file; remove deletes an installed directory only. `scripts/test-vgshell.sh` pins it.
- Do stage a file by `replaceFile` in `bin/lib/judge-files.js`: owner-only until full, then the kept mode. `scripts/test-judge-files.js` pins it.

### Targets

- Do mark every target `runsCode`, and never take an installed package's curated file on such a target: drop it, name it in `dropped`, render the template. `scripts/test-vgshell-targets.sh` pins both.
- Do render through `bin/lib/theme-render.js` with text in and text out; `scripts/test-theme-render.js` pins the renderer.
- Do name every placeholder from the token table or a terminal slot; an unknown one refuses the target, and `bin/vgshell-theme-judge packages` renders every shipped target offline.
- Do write a colour only through the target's encoder; no encoder writes `#`, the template does. `scripts/test-theme-render.js` pins it.
- Do give each destination a unique `<target>.<ext>`, so no two targets write one file. `scripts/test-theme-render.js` pins it.
- Never run a `detect` command; an entry is met by an executable in an absolute PATH directory. `scripts/test-vgshell.sh` pins it.
- Do render the template even when a curated file is taken, so a curated file never hides a bad placeholder, and take a `curatedKeys` file only when it is a JSON object holding one of the keys. `scripts/test-theme-render.js` and `scripts/test-vgshell-editor-entries.sh` pin both.
- Do match an include line as one whole line and place a sectioned line right after its section header, so TOML never declares a table twice. `scripts/test-theme-render.js` pins both.
- Never replace anything at an entry path that is not the managed form; skip it as `entry-occupied`, and use a copy where the application watches its directory. `scripts/test-vgshell-entries.sh` pins both.
- Never wire a profile a stale `profiles.ini` names; wire only existing profile directories. `scripts/test-vgshell-targets.sh` pins it.
- Never create an absent settings file for a `select`; skip the target as `selection-file-absent`, set the key on every landing apply, and leave every other byte. `scripts/test-vgshell-agents.sh` and `scripts/test-theme-select.js` pin both.
- Do skip a target whose `setup` command is absent as `setup-absent`, grant a privileged writer its narrowest argument grammar, and offer the install only while the application is found without the writer. `scripts/test-vgshell-browsers.sh`, `scripts/test-vgshell-browser-policy.sh` and `scripts/test-themes-setup.js` pin them.
- Do run a hook that asserts a desktop setting on every apply and set nothing when the value already holds; never set an icon theme that is not installed, and set `accent-color` only where `gsettings range` lists the value. `scripts/test-vgshell-toolkits.sh` pins each.
- Never let a hook link a shipped theme over anything but an absent name or a dangling link. `scripts/test-vgshell-toolkits.sh` pins it.
- Never source `gum.env`; the floating TUI parses it at each launch and refuses the whole file on a key outside its pattern. `scripts/test-theme-gum.js` pins it with a command-substitution control.
- Never add a Hyprland target; its colours come from the generated Hyprland layer.

### Applying

- Do stage every file and swap by rename; never write into `theme/` in place. `scripts/test-vgshell.sh` pins it.
- Do write the theme file last and byte for byte; a re-serialised copy reports every apply as modified. `scripts/test-vgshell.sh` pins it with a re-serialising control.
- Do keep the include line, the managed entries and the selection key on every apply, unchanged bytes included, so a hand edit is repaired. `scripts/test-vgshell.sh` and `scripts/test-vgshell-agents.sh` pin it.
- Never create a file through a dangling symlink; resolve the link and replace the file it names by rename with its mode. `scripts/test-vgshell.sh` pins it with a link-replacing control.
- Do refuse the whole apply as `malformed` when either configuration layer is refused, since no target's enablement is then known. `scripts/test-vgshell.sh` pins it.
- Do record every due target as pending before the swap, so an apply that dies after the swap leaves it pending, and never run a hook on unchanged bytes unless the target says `reload.always`. `scripts/test-vgshell-reload.sh` pins both.
- Do give a hook `/dev/null` for its streams and no lock descriptor, kill it at its timeout, and leave the target pending. `scripts/test-vgshell-reload.sh` pins it.
- Never start a hook under `VGS_TEST_RUN` whose target directory, command path or any PATH entry lies outside the scratch root, or while a live session channel such as `WAYLAND_DISPLAY`, `TMUX` or `DBUS_SESSION_BUS_ADDRESS` is set, because a test that reached a shipped hook would signal the owner's live session. `scripts/test-vgshell-reload.sh` pins it, and `scripts/test-validate.sh` proves `scripts/validate` exports the marker.
- Do record the applied name, the theme file's hash and the package digest after the theme file lands, and never follow over a theme file whose hash is not the recorded one. `scripts/test-vgshell-follow.sh` pins both.
- Do digest `theme.json`, `terminal.json` and `targets/` only; `backgrounds/` holds no colours. `scripts/test-vgshell-follow.sh` pins it with a curated-out control.

### Catalog

- Do judge every index entry and package through `ThemeLogic.acceptCatalogIndex` and `acceptCatalogEntry`; `bin/vgshell-theme-judge catalog-check` refuses a bad one, and `scripts/test-vgshell-theme-judge.js` runs it over the shipped catalog.
- Never ship a curated file on a `runsCode` target, a file no target writes, or a symlink in a catalog entry; `catalog-check` refuses each.
- Do install a catalog package as an ordinary installed package with a marker; `.git` wins over the marker for origin. `scripts/test-vgshell-catalog.sh` pins it.
- Never let install or update delete a package or its edits: an occupied name is refused, and a hand-edited install refuses update as `modified`. `scripts/test-vgshell-catalog.sh` pins both.
- Do run `recover` under the theme lock before any install verb changes anything. `scripts/test-vgshell-catalog.sh` pins it.
- Do keep `palette` and `mode` in the index equal to the package's resolved values, so a card draws without reading the package. `scripts/test-theme-logic.js` pins it.
- Do keep every shipped and catalog package readable at the floors `ThemeLogic.readabilityShortfalls` states, with the fix inside the package's own `theme.json`; a theme no fix makes readable is not listed. `scripts/check-theme-contrast.js` refuses a shortfall.
- Do accept download bytes by the pin, refuse another size or digest, leave no part, and require HTTPS for the URL and every redirect. `scripts/test-theme-download.js` pins each.
- Do hold `download.lock` for the fetch and the theme lock for the land only, and judge the install again at the land. `scripts/test-vgshell-wallpapers.sh` pins both.
- Do land only regular `backgrounds/<image>` members under the ceiling, and never take a `backgrounds/` the download did not place. `scripts/test-theme-download.js` and `scripts/test-vgshell-wallpapers.sh` pin both.

### Backgrounds

- Do make `bin/lib/theme-backgrounds.js` the only writer of the wallpaper state and `WallpaperState.qml` the only reader. `scripts/test-vgshell-backgrounds.sh` and `scripts/smoke/rows/themes.sh` pin both.
- Do draw each screen's own entry in the per-screen map, and the current image on a screen with no entry. `set --screen` sets one entry, `set --every-screen` clears them all, `next` and `previous` keep the map, and an apply clears it so the new package shows on every screen. `scripts/test-vgshell-backgrounds.sh` pins it.
- Do accept in `set` only an image `background list --all` names: one in an accepted package's `backgrounds/` or in the user folder. `scripts/test-vgshell-backgrounds.sh` pins it.
- Do count only `.png`, `.jpg` and `.jpeg` regular files, never a symlinked image or `backgrounds/` itself. `scripts/test-vgshell-backgrounds.sh` pins it.
- Do stamp an image by size and modification time, so a file replaced under its name reloads, and decode at the screen's device-pixel size. `scripts/smoke/rows/themes.sh` and `scripts/smoke/rows/hidpi.sh` pin both.
- Do watch the state file, not the `background` link; Qt's directory watcher follows a link to its target.
- Never map the background surface while no image is current, unreadable, or the state file is not the runner's. `scripts/smoke/rows/themes.sh` pins it.
- Never ask Hyprland whether an output exists; the judge checks the name's shape alone, so an entry can wait for a disconnected monitor.
- Do choose and read the image before anything moves, so an unreadable image refuses the apply before the theme file changes. `scripts/test-vgshell-backgrounds.sh` pins it.

### Runner boundary

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

`themes/vgs/`: the shipped defaults, one `theme.json`, one `terminal.json`, and a curated file only where a target's own format has no template. Copy it for a package. For a target, copy `themes/targets/kitty/`: one `target.json` with an include wiring, one template, and a reload hook that counts a stopped application as success. For a verb that writes, copy the order of the `apply` verb of `bin/vgshell-theme-judge`: stage, swap under the lock, wire, mark pending, write the theme file last, record the follow. For a client, copy `shell/plugins/vgs.themes/`: every decision in `BrowserLogic.js`, every action through the capability, every result read from `last`.

## Revisit when

Packages carry signatures or a trusted-author list, or an installed or catalog theme needs a code file with no template. An application reads its configuration through a hard link or watches its inode, needs its include line somewhere other than the first line, needs its theme key in a form the line edit refuses, or needs a privileged step a one-click helper cannot carry. Something needs `theme/` present at every instant. The catalog outgrows the repository, or a watched CLI cannot reload from an atomic copy. A screen needs a setting beyond its image, or an apply must keep a screen's own image. Users need a local change that follows upstream updates of an installed package, or a target needs a per-user value no package can carry.

## Not governed

The token table, the theme document's tiers and the readability floors' values, which are [design-system.md](design-system.md); where `theme.json` and the state directory live, which is [configuration.md](configuration.md); the list of shipped targets and each one's one-time step, which is `themes/targets/` and the `vgs.themes` README.
