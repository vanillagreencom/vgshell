# A theme is one judged package

Read before changing a theme package, the package judge, a theme target, apply, follow or `vgshell theme reload`, a catalog install or wallpaper download, the wallpaper state or the background surface, `ThemeRunner` and the `theme` capability, or a plugin view that applies, installs or previews a theme.

## The approach

A theme is a package: a directory of data, never code. One pure judge, `ThemeLogic.acceptPackage` in `shell/Commons/ThemeLogic.js`, accepts or refuses a package from file text alone. The runner `bin/vgshell-theme-judge` does every read and write. The shell reaches it only as `vgshell theme` processes that `shell/Core/ThemeRunner.qml` starts for the `theme` capability.

A target is data too: one `target.json` and its templates under `themes/targets/<name>/`, which the pure renderer `bin/lib/theme-render.js` fills from the package's tokens. An installed package has plugin trust. On a target whose files run code, the runner drops the package's curated file and renders the template ([D031](../decisions/D031-installed-themes-render-code-targets.md)).

An apply lands whole or not at all. It stages every file beside its destination, swaps under the theme lock, and writes the shell's theme file last ([D021](../decisions/D021-theme-apply-writes-beside-each-destination.md)). A target that fails costs only itself and keeps its last files.

VGS never overwrites what the user placed. Application entries and selection keys follow [D022](../decisions/D022-theme-apply-keeps-managed-links-in-application-directories.md). A follow never replaces a hand-edited theme file. A package changes only as a whole, and no layer merges over it ([D025](../decisions/D025-no-theme-override-layer.md)).

A catalog package earns no trust of its own. The Catalog and Backgrounds rules below govern catalog installs and wallpaper state.

## Why

A theme someone shared, or its update, must not run code in the user's editor or terminal, and nothing reviews a theme before it applies. A VGS update changes a catalog package with no review step either, so the catalog gets the same rules.

A judge with no I/O runs under node and in the shell, so a script and the shell cannot disagree about a package. A plugin that judged a package itself would be a second judge that drifts.

A rename in one directory is atomic, so no reader sees half a theme. Writing the shell last keeps the displayed theme from running ahead of the applications.

A managed form proves itself, so the runner tells its own file from the user's with no marker file. Without the hash check, a follow would overwrite a user's edit.

A wallpaper another program draws must not be covered by a bare background colour, so no image means no surface. A download on the theme lock or the queue would hold every list and apply behind it. A hidden panel is destroyed, so a result it owned would vanish mid-apply.

## Rules

### Packages

- Do judge a package only through `ThemeLogic.acceptPackage`, from file text. `scripts/test-theme-logic.js` pins each refusal.
- Never infer light or dark from a package's name or colours; the package states `scheme.mode`. Review.
- Do keep every shipped package and target passing the judge offline. `scripts/validate` runs `bin/vgshell-theme-judge packages themes`.
- Never name an installed package `vgs`; the shipped `vgs` package is the revert. `scripts/test-vgshell.sh` pins the refusal.
- Never follow a symlink below a package directory. `scripts/test-vgshell-package-links.sh` pins it.
- Do clone an install or update into a staging directory and judge it there before it lands, with no git hook or submodule. `scripts/test-vgshell.sh` pins both.
- Do ask before an update and roll back a version the judge refuses. `scripts/test-vgshell.sh` pins both.
- Do hold the theme lock for apply, follow, reload, a background change and every install verb; a second holder is refused as busy, except that a follow first waits up to 10 s for the holder to end. `scripts/test-vgshell.sh` and `scripts/test-vgshell-follow.sh` pin it.
- Never remove a shipped package; remove deletes an installed directory only. `scripts/test-vgshell.sh` pins it.
- Do write every file through `replaceFile` in `bin/lib/judge-files.js`, so no reader sees a partial file. `scripts/test-judge-files.js` pins it.
- Never add a layer that merges over the applied package. Review.

### Targets

- Do keep a target as data rendered by `bin/lib/theme-render.js`, text in and text out. `scripts/test-theme-render.js` pins the renderer.
- Do declare `runsCode` on every target, and never take an installed package's curated file on a target that runs code. `scripts/test-vgshell-targets.sh` pins both.
- Never run a target's `detect` entry. `scripts/test-vgshell.sh` pins it.
- Never replace anything at an entry path that is not a managed form; skip the target as `entry-occupied`. `scripts/test-vgshell-entries.sh` pins it.
- Never create an absent settings file for a `select`, and never change a byte outside its declared theme selection keys. The one exception is an editor's settings file, which an editor writes only once a setting changes, so an editors target creates it. `scripts/test-vgshell-agents.sh`, `scripts/test-theme-select.js` and `scripts/test-vgshell-vscode.sh` pin all three.
- Do serve every editor of one family from one target: an `editors` target wires each editor whose own command is on PATH with one generated extension, its version made from its theme's bytes, registered in that editor's `extensions.json` and unmarked in its `.obsolete`, with every other version removed. `scripts/test-theme-render.js` and `scripts/test-vgshell-vscode.sh` pin it.
- Never prompt during an apply: skip a target whose privileged `setup` is absent, and give its writer the narrowest argument grammar ([D029](../decisions/D029-chromium-policy-writer.md)). `scripts/test-vgshell-browsers.sh`, `scripts/test-vgshell-browser-policy.sh` and `scripts/test-themes-setup.js` pin them.
- Do give a hook `/dev/null` for its streams and no lock descriptor, and kill it at its timeout. `scripts/test-vgshell-reload.sh` pins it.
- Never let a hook replace what the user set: link a shipped theme only over an absent name or a dangling link, set nothing that already holds, and set no value the system lacks. `scripts/test-vgshell-toolkits.sh` pins each.
- Never source `gum.env`; the floating TUI parses it. `scripts/test-theme-gum.js` pins it.
- Never add a Hyprland target; the theme reaches Hyprland through the generated layer ([D028](../decisions/D028-one-generated-hyprland-layer.md)). Review.

### Applying

- Do stage every file and swap by rename; never write into `theme/` in place. `scripts/test-vgshell.sh` pins it.
- Do write the theme file last and byte for byte. `scripts/test-vgshell.sh` pins it.
- Do repair the include line, the managed entries and the selection key on every apply. `scripts/test-vgshell.sh` and `scripts/test-vgshell-agents.sh` pin it.
- Never create a file through a dangling symlink. `scripts/test-vgshell.sh` pins it.
- Do refuse the whole apply when a configuration layer is refused. `scripts/test-vgshell.sh` pins it.
- Do record every due target as pending before the swap, so `vgshell theme reload` can retry it. `scripts/test-vgshell-reload.sh` pins it.
- Never follow over a theme file whose hash is not the one the apply recorded. `scripts/test-vgshell-follow.sh` pins it.

### Catalog

- Do keep first-party catalog data in `themes/catalog/`, with one index judged by `ThemeLogic`. `bin/vgshell-theme-judge catalog-check` refuses a bad index or package, and `scripts/test-vgshell-theme-judge.js` runs it over the shipped catalog.
- Never ship a curated file on a target that runs code, a file no target writes, or a symlink in a catalog package. `catalog-check` refuses each.
- Do install a catalog package on demand as an ordinary installed package with a marker. `scripts/test-vgshell-catalog.sh` pins it. Shipping it as an applied package would grant curated code trust and remove install-on-demand.
- Never let install or update delete a package or its edits. `scripts/test-vgshell-catalog.sh` pins it.
- Do run `recover` under the theme lock before any install verb changes anything. `scripts/test-vgshell-catalog.sh` pins it.
- Do keep every shipped and catalog package readable, with any fix in the package's own `theme.json` or `terminal.json`. `scripts/check-theme-contrast.js` refuses a shortfall, and `scripts/test-check-theme-contrast.js` runs it over `themes/`.
- Do fetch wallpapers on demand from the release archive pinned in the catalog index, over HTTPS. `scripts/test-theme-download.js` pins the accepted bytes.
- Do hold the download lock for the fetch and the theme lock only for the land, and judge the package again at the land. `scripts/test-vgshell-wallpapers.sh` pins both.

### Backgrounds

- Do keep `bin/lib/theme-backgrounds.js` the only writer of the wallpaper state and the `vgs.themes` plugin's `WallpaperState.qml` the only reader. `scripts/test-vgshell-backgrounds.sh` and `scripts/smoke/rows/themes.sh` pin both.
- Do keep per-output images in the optional `screens` map of `backgrounds.json`, overriding `current` for those outputs. An absent entry uses `current`; use no separate mode flag or seeded map. Theme apply clears the map, and `set` accepts only an image the `list --all` result names. `scripts/test-vgshell-backgrounds.sh` pins the state and writer; `scripts/test-theme-logic.js` pins the screen argument grammar.
- Never map the background surface while no image is current. `scripts/smoke/rows/themes.sh` pins it.
- Never put a user image into a package, and never give the wallpaper browser an add, remove or delete action; user images live in the user folder. Review.

### Runner boundary

- Do run every theme change a plugin makes through the `theme` capability, and never judge a package in the shell. Review.
- Do keep the last result in `ThemeRunner`, outside every plugin instance. `scripts/smoke/rows/themes.sh` pins it.
- Do run a wallpaper download on its own lane, never on the queue. `scripts/smoke/rows/theme-browse.sh` pins it.
- Do keep a view's decisions in a pure file with no QML object and no I/O, such as `shell/plugins/vgs.themes/BrowserLogic.js`. `scripts/test-themes-browser.js` pins it.

## The canonical example

`themes/targets/kitty/`: one `target.json` with an include wiring and a reload hook, and one template. Copy it for a target, and copy `themes/vgs/` for a package.

## Revisit when

Packages carry signatures or a trusted-author list, a theme needs a code file with no template, the catalog outgrows the repository, a screen needs more than an image, or apply must keep a screen's image. Other cases follow the revisit condition of D021, D022 or D025.

## Not governed

The token table and the readability floors, which are `shell/Commons/Tokens.js` and `ThemeLogic.readabilityShortfalls`, and the rules for drawing with them, which are [design-system.md](design-system.md); where `theme.json` and the state directory live, which is [configuration.md](configuration.md); the list of shipped targets and each one's one-time step, which is `themes/targets/` and the `vgs.themes` README.
