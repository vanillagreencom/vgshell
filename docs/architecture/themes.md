# A theme is one judged package

Read before changing a theme package, the package judge, a theme target, apply, follow or `vgshell theme reload`, a catalog install or wallpaper download, the wallpaper state or the background surface, `ThemeRunner` and the `theme` capability, or a plugin view that applies, installs or previews a theme.

## The approach

A theme is a package: a directory of data, never code. One pure judge, `ThemeLogic.acceptPackage` in `shell/Commons/ThemeLogic.js`, accepts or refuses a package from file text alone. The runner `bin/vgshell-theme-judge` does every read and write. The shell reaches it only as `vgshell theme` processes that `shell/Core/ThemeRunner.qml` starts for the `theme` capability.

A target is data too: one `target.json` and its templates under `themes/targets/<name>/`, which the pure renderer `bin/lib/theme-render.js` fills from the package's tokens. An installed package has plugin trust. On a target whose files run code, the runner drops the package's curated file and renders the template ([D031](../decisions/D031-installed-themes-render-code-targets.md)).

An apply lands whole or not at all. It stages every file beside its destination, swaps under the theme lock, and writes the shell's theme file last ([D021](../decisions/D021-theme-apply-writes-beside-each-destination.md)). A target that fails costs only itself and keeps its last files.

An applied VGS theme replaces whatever theme the user had in each application VGS supports, with no confirmation; the owner ruled on 2026-10-10: "Users dont need to 'confirm' things like that." Application entries follow [D022](../decisions/D022-theme-apply-keeps-managed-links-in-application-directories.md). The Targets rules below govern edits to user settings. A follow applies a changed package over whatever the theme file holds. A package changes only as a whole, and no layer merges over it ([D025](../decisions/D025-no-theme-override-layer.md)) but the user's Appearance values. No target renders them except the terminal font, which no package states ([D104](../decisions/D104-appearance-values-over-the-theme.md)).

A catalog package earns no trust of its own. The Catalog and Backgrounds rules below govern catalog installs and wallpaper state.

## Why

A theme someone shared, or its update, must not run code in the user's editor or terminal, and nothing reviews a theme before it applies. A VGS update changes a catalog package with no review step either, so the catalog gets the same rules.

A judge with no I/O runs under node and in the shell, so a script and the shell cannot disagree about a package. A plugin that judged a package itself would be a second judge that drifts.

A rename in one directory is atomic, so no reader sees half a theme. Writing the shell last keeps the displayed theme from running ahead of the applications.

A managed form proves itself, so the runner tells its own file from the user's with no marker file, and disable removes only its own. A theme the user must confirm over their own file is a theme that silently fails to apply.

Keeping per-theme values in generated files lets terminal application settings stay unchanged on every theme switch after migration.

A wallpaper another program draws must not be covered by a bare background colour, so no image means no surface. The default theme `vgs` holds one image, Black, so applying it covers such a wallpaper as any theme with wallpapers does; a package with no image leaves it visible. A download on the theme lock or the queue would hold every list and apply behind it. A hidden panel is destroyed, so a result it owned would vanish mid-apply.

## Rules

### Packages

- Do judge a package only through `ThemeLogic.acceptPackage`, from file text. `scripts/test-theme-logic.js` pins each refusal.
- Never infer light or dark from a package's name or colours; the package states `scheme.mode`. Review.
- Do title a package in a view by the optional `displayName` string in its `theme.json`, else by its title-cased name, through `BrowserLogic.label` alone; `ThemeLogic.accept` refuses an empty or non-string one. `scripts/test-theme-logic.js` and `scripts/test-themes-browser.js` pin both.
- Do keep every shipped package and target passing the judge offline. `scripts/validate` runs `bin/vgshell-theme-judge packages themes`.
- Never name an installed package `vgs`; the shipped `vgs` package is the revert. `scripts/test-vgshell.sh` pins the refusal.
- Never follow a symlink below a package directory. `scripts/test-vgshell-package-links.sh` pins it.
- Do clone an install or update into a staging directory and judge it there before it lands, with no git hook or submodule. `scripts/test-vgshell.sh` pins both.
- Do ask before an update and roll back a version the judge refuses. `scripts/test-vgshell.sh` pins both.
- Do hold the theme lock for apply, follow, reload, a background change and every install verb; a second holder is refused as busy, except that follow and update first wait up to 10 s for the holder to end. `scripts/test-vgshell.sh` and `scripts/test-vgshell-follow.sh` pin it.
- Never remove a shipped package; remove deletes an installed directory only. `scripts/test-vgshell.sh` pins it.
- Do write every file through `replaceFile` in `bin/lib/judge-files.js`, so no reader sees a partial file. `scripts/test-judge-files.js` pins it.
- Never add a layer that merges over the applied package. The user's Appearance values are the one exception ([D104](../decisions/D104-appearance-values-over-the-theme.md)). Review.
- Never render an Appearance value in a target, except the terminal font: a target names it as `@{appearance.terminalFont}`, and a line that names it is written only while the user set one. `scripts/test-theme-render.js` pins the line, and `scripts/test-vgshell-targets.sh` the kitty and Ghostty files.

### Targets

- Do keep a target as data rendered by `bin/lib/theme-render.js`, text in and text out. `scripts/test-theme-render.js` pins the renderer.
- Do declare `runsCode` on every target, and never take an installed package's curated file on a target that runs code. `scripts/test-vgshell-targets.sh` pins both.
- Never run a target's `detect` entry. `scripts/test-vgshell.sh` pins it.
- Do keep Ghostty, Neovim and Pi colour values in generated theme files. Their user configuration receives only a stable include, bridge or theme selection. That selection stays the same across themes. A second apply leaves the user configuration byte for byte unchanged. `scripts/test-vgshell-targets.sh` checks these boundaries.
- Do use `last` wiring for Ghostty's generated include. Ghostty loads includes after the parent file, in include order. Keeping the VGS include last prevents a local include from replacing its generated colours. `scripts/test-vgshell-targets.sh` checks precedence.
- Do restore Neovim's generated colours after `VimEnter` and `ColorScheme`. Defer the restore until synchronous event callbacks finish, so local startup plugins and later colour-scheme loads do not leave another palette. A running editor reads a newly generated theme on restart. `scripts/test-vgshell-targets.sh` checks event precedence.
- Do apply Pi's generated account palette through its personal extension at `session_start`, using Pi's public theme API. Select the account file directly, so project settings and a project theme with the same name cannot replace it. Discover accounts through the shared account rule in `shell/Commons/AccountDirectories.js`. Preserve project settings. A fresh interactive Pi process with extensions enabled loads the extension and palette. `scripts/test-vgshell-targets.sh` checks selection and project-file preservation.
- Do replace whatever stands at an entry path with its managed form by rename, a file, a foreign link or an edited copy, and never delete a directory there; the target fails instead. `scripts/test-vgshell-entries.sh` pins it.
- Do write per-theme colour values only into files VGS generates. After colour migration, VGS adds at most a stable selector to user-owned Starship, fastfetch, Yazi, bat and television files. That selector is identical for every theme. `scripts/test-vgshell-targets.sh` checks that theme switches leave those tracked files unchanged.
- Do confine a `select` edit to its declared theme selection and the migration of local colours. Preserve layout, glyphs, attributes, matching rules and commands. Preserve bytes outside migrated theme content. Move local colour overrides into the generated theme where the app supports it. `scripts/test-theme-select.js` and `scripts/test-vgshell-targets.sh` check these edits.
- Do use stable ANSI colour references when an app cannot read an external colour palette. Starship and fastfetch use this route, following Omarchy. Convert literal and custom-palette colours once; generated terminal palettes supply per-theme values. Remove Starship's VGS palette table and its palette selection in that migration.
- Do map converted colours to the nearest of the 16 ANSI slots in `bin/lib/theme-select.js::ANSI_REFERENCE` through `nearestAnsi`. Use squared Euclidean distance in 8-bit sRGB. Break ties with the lowest slot. Preserve existing ANSI names and codes. `scripts/test-theme-select.js` checks the conversion.
- Never create an absent settings file for a `select`, except for an app that does not write that file itself until a user changes a setting or creates the file. Create only the managed selection, and only while the app's command is on PATH. Editors and bat use this exception. `scripts/test-theme-select.js` and `scripts/test-vgshell-vscode.sh` check creation and detection.
- Do keep Yazi's colours and local style and icon rules in generated `vgs.yazi` flavors for the normal and scratchpad configurations. The user files keep only stable flavor selectors. Preserve local glyphs, attributes and matching rules in the generated flavors. `scripts/test-vgshell-targets.sh` checks both paths.
- Do select bat through its native configuration and rebuild its theme cache after the theme file lands. Shell and channel environment overrides remain external inputs; this target writes no environment. `scripts/test-vgshell-targets.sh` checks selection and the cache hook.
- Do select television's generated VGS theme through its stable native selection. Remove local theme colour overrides during migration so the generated theme supplies every colour. The sesh picker uses the global television configuration through its ad-hoc source and preview commands. Source and preview ANSI output keeps its own styling. `scripts/test-vgshell-targets.sh` checks the selection and override removal.
- Do skip Copilot CLI custom themes. Its [documented palettes](https://docs.github.com/en/enterprise-cloud@latest/copilot/how-tos/copilot-cli/customize-copilot/change-settings) are `default`, `github`, `dim`, `high-contrast` and `colorblind`. The documented interface supplies no custom palette file for VGS.
- Do limit the Claude Desktop target to its own `themes.d/vgs.json` and the `activeTheme` key in each existing profile's `claude-desktop-extra.jsonc`. Both mode blocks use the applied VGS palette. The app's [theme contract](https://github.com/patrickjaja/claude-desktop-extra/blob/master/docs/themes.md) lets `themeOverlay` replace that palette. A local `themes.vgs` definition takes precedence over the theme file. [Custom CSS](https://github.com/patrickjaja/claude-desktop-extra/blob/master/themes/README.md#custom-css-raw-rules) can override the resulting colours through `customCss`. Preserve those keys. Dots or Jarvis removes conflicting user colour overrides on the user side. VGS owns only the colours it writes. The app derives its desktop and console colour layers from the theme tokens. Its [token reference](https://github.com/patrickjaja/claude-desktop-extra/blob/master/themes/README.md#the-other-token-layers-handled-for-you) leaves raw console greys, white switch and slider handles, and the yellow warning fill at stock values. Review holds that ownership boundary.
- Do serve every editor of one family from one target: an `editors` target wires each editor whose own command is on PATH, one editor at a time, with one generated extension. Its id and its one theme's id are made from its theme's bytes. The selector names that generated extension and changes when its theme's bytes change. A fixed id would need a window reload. The extension is registered in that editor's `extensions.json` and unmarked in its `.obsolete`, then the editor's settings select its theme, then every other extension the target made is unregistered and removed. The one exception is the extension whose theme the settings selected before; the next apply removes it. An open window adds an extension whose id it does not hold and applies a changed selection, so each apply re-themes it with no reload. A window whose shown theme leaves its theme list falls back to the default theme and saves that choice, so an apply never removes the shown theme. A failure in one editor leaves the others to finish. The unstamped `local.vgs-theme` of earlier releases, selected as `vgs`, takes the same path. `scripts/test-theme-render.js` and `scripts/test-vgshell-vscode.sh` pin it.
- Never prompt during an apply: skip a target whose privileged `setup` is absent, and give its writer the narrowest argument grammar ([D029](../decisions/D029-chromium-policy-writer.md)). `scripts/test-vgshell-browsers.sh`, `scripts/test-vgshell-browser-policy.sh` and `scripts/test-themes-setup.js` pin them.
- Do give a hook `/dev/null` for its streams and no lock descriptor, and kill it at its timeout. `scripts/test-vgshell-reload.sh` pins it.
- Never let a hook replace what the user set: link a shipped theme only over an absent name or a dangling link, set nothing that already holds, and set no value the system lacks. `scripts/test-vgshell-toolkits.sh` pins each.
- Never source `gum.env`; the floating TUI parses it. `scripts/test-theme-gum.js` pins it.
- Do turn on RGB and set `CLAUDE_CODE_TMUX_TRUECOLOR` in the tmux include, so Claude Code draws truecolor inside tmux instead of the 256 colours it drops to whenever `TMUX` is set. Set `PROMPT_TOOLKIT_COLOR_DEPTH=DEPTH_24_BIT` there for Hermes' classic CLI. The variables reach panes opened after the include loads; an existing pane keeps its environment when an application restarts. RGB reaches a client that attaches after the include loads. `scripts/test-theme-tmux.js` checks both variables and RGB.
- Never add a Hyprland target; the theme reaches Hyprland through the generated layer ([D028](../decisions/D028-one-generated-hyprland-layer.md)). Review.
- Do mix the page 0.13 toward the text for the Claude Code user-message and bash bands. Claude Code drops to 256 colours inside tmux unless `CLAUDE_CODE_TMUX_TRUECOLOR` is set. A tinted colour near the page then becomes a tinted palette entry: Flexoki Light's old band `#f3f0e5` showed as `#ffffd7`, which is almost the page. The mixed band holds at least 1.2:1 on the page as written, and its 256-colour form holds at least 1.05:1 on the page. Flexoki Light's band is now `#e0ddd3`, which shows as the neutral grey `#d7d7d7`. `scripts/test-theme-render.js` pins both floors.
- Do solve Claude Code's word-highlight colours through `ThemeLogic` so code text keeps at least 4.5:1 contrast. Claude Code uses those same colours for change counts on its inset panel. Counts must reach 3:1 where both floors can hold. Otherwise, use the highest count contrast that keeps the code-text floor. `scripts/test-theme-render.js` pins both rules for every catalog theme.

### Applying

- Do stage every file and swap by rename; never write into `theme/` in place. `scripts/test-vgshell.sh` pins it.
- Do write the theme file last and byte for byte. `scripts/test-vgshell.sh` pins it.
- Do repair the include line, the managed entries and the selection key on every apply. `scripts/test-vgshell.sh` and `scripts/test-vgshell-agents.sh` pin it.
- Do reload btop after each apply, including a selection-only repair. SIGUSR2 reloads its settings from disk before applying the theme, so its later save on exit keeps the new selection. Copy Omarchy's stable theme name, managed link and SIGUSR2 reload; preserve unrelated settings instead of installing its complete btop.conf. `scripts/test-theme-render.js` pins the selection and the always-due reload.
- Do keep the include line of a `last` wiring after every line of the user's own, moving it there on each apply and changing no other line. The tmux target sets `last`, with `~/.tmux.conf` as its fallback, and a linked file is written through its link. The tmux theme owns colours, not layout or content. It sets the colour options and removes whole colour-bearing inline style spans from formats, including other attributes within those spans. It keeps colour-free options byte for byte, `#(...)` command calls and every status-format row, including an empty row. `scripts/test-theme-tmux.js` and `scripts/test-vgshell-chat-tools.sh` pin it.
- Never create a file through a dangling symlink. `scripts/test-vgshell.sh` pins it.
- Do refuse the whole apply when a configuration layer is refused. `scripts/test-vgshell.sh` pins it.
- Do record every due target as pending before the swap, so `vgshell theme reload` can retry it. `scripts/test-vgshell-reload.sh` pins it.
- Do run due hooks in target name order, with every hook whose reload declares `last` after the rest, in an apply and in a reload. The colour-scheme target declares it. Chromium through M152, which Slack 4.52 runs, has two writers of the colour scheme it gives web content, the portal's `color-scheme` and the GTK theme's background colour, and the later one wins (Chromium commits 2c9938b8f5b5 and 81e85eb2603a). A GTK or icon theme change after the colour scheme turns such an app dark again after a light apply. `scripts/test-vgshell-reload.sh`, `scripts/test-vgshell-toolkits.sh` and `scripts/smoke/rows/portal-accent.sh` pin it.
- Do follow a changed package, shipped target definition or template, or terminal font whatever the theme file holds, and write nothing when none changed. `scripts/test-vgshell-follow.sh` pins it.
- Do keep the background state through a follow that renders an unchanged package again, as for a new terminal font. `scripts/test-vgshell-backgrounds.sh` pins it.

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
- Do name package wallpapers only through the optional `backgrounds` map in `theme.json`, from image file name to one or two words; `ThemeLogic.accept` judges the names, and `acceptPackage` refuses a missing named file only for a shipped package. `scripts/test-theme-logic.js` pins it.
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

Packages carry signatures or a trusted-author list, a theme needs a code file with no template, the catalog outgrows the repository, a screen needs more than an image, apply must keep a screen's image, or an application supports neither an external colour file nor ANSI references. Other cases follow the revisit condition of D021, D022 or D025.

## Not governed

The token table and the readability floors, which are `shell/Commons/Tokens.js` and `ThemeLogic.readabilityShortfalls`, and the rules for drawing with them, which are [design-system.md](design-system.md); where `theme.json` and the state directory live, which is [configuration.md](configuration.md); the list of shipped targets and each one's one-time step, which is `themes/targets/` and the `vgs.themes` README.
