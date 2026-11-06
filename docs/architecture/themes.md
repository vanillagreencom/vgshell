# A theme is one judged package

Read before changing theme packages, their judge or targets, apply, follow, reload, catalog installation, wallpaper downloads or state, backgrounds, ThemeRunner or theme views.

## The approach

Themes and targets are data. `ThemeLogic.acceptPackage` judges package text; `bin/vgshell-theme-judge` owns I/O. The shell uses `vgshell theme` through `ThemeRunner` and capability `theme`. Targets under `themes/targets/` render through the pure `bin/lib/theme-render.js`.

Installed and catalog packages have plugin trust. On code-running targets, render the shipped template instead of a package's curated file ([D031](../decisions/D031-installed-themes-render-code-targets.md)). Stage writes beside destinations, swap under one theme lock and write the shell theme last ([D021](../decisions/D021-theme-apply-writes-beside-each-destination.md)). A refused target keeps its last files without blocking other targets.

Apply replaces the selected application theme without confirmation (owner, 2026-10-10). Managed application entries follow [D022](../decisions/D022-theme-apply-keeps-managed-links-in-application-directories.md). A package changes as a whole with no override layer ([D025](../decisions/D025-no-theme-override-layer.md)), except Appearance values ([D104](../decisions/D104-appearance-values-over-the-theme.md)). Only terminal font reaches targets from Appearance.

## Why

Shared themes must not execute code. One judge prevents shell and CLI disagreement. Atomic replacement protects readers from partial files, while writing the shell last keeps its drawing behind completed application writes. Stable native selectors keep ordinary user configuration independent of theme changes.

## Rules

### Packages

- Judge only through `ThemeLogic.acceptPackage`. Keep shipped packages and targets valid offline; `scripts/validate` runs the package judge. Never infer mode from name or colours. `scripts/test-theme-logic.js` checks the judge.
- Use `BrowserLogic.label` for display names and `ThemeLogic.accept` for their validity. `scripts/test-themes-browser.js` checks labeling.
- Reserve `vgs` for the shipped revert package. Remove only installed packages. Never follow a symlink below a package directory. `scripts/test-vgshell.sh` and `scripts/test-vgshell-package-links.sh` check these boundaries.
- Stage clones without hooks or submodules and judge before landing. Ask before updates and roll back refused versions. `scripts/test-vgshell.sh` checks installation.
- Hold the theme lock for apply, follow, reload, background changes and install verbs. Refuse competing holders except follow and update's bounded wait. `scripts/test-vgshell-follow.sh` checks waiting; the runner owns the timeout.
- Write through `replaceFile` in `bin/lib/judge-files.js`. Never merge an extra layer over a package or render Appearance values in targets except the explicitly set terminal font. `scripts/test-judge-files.js` and `scripts/test-theme-render.js` check these boundaries.

### Targets

- Keep targets pure data with text-in/text-out rendering. Declare `runsCode`, drop untrusted curated code and never execute `detect` entries. `scripts/test-theme-render.js` and `scripts/test-vgshell-targets.sh` check these contracts.
- Keep per-theme colours in generated files. User configuration receives stable native selectors, includes or ANSI identities. Preserve layout, glyphs, attributes, matching rules, commands and bytes outside migrated theme content. Reapplying the same theme changes nothing there. `scripts/test-theme-select.js` and `scripts/test-vgshell-targets.sh` check edits.
- Convert literal colours through `theme-select.js::nearestAnsi`, preserving existing ANSI names and codes. Remove migrated private palette definitions. The implementation owns the reference palette and tie rules.
- Keep the KDE exception explicit: write native colour groups into `kdeglobals` from the generated scheme while preserving the stable selector and unrelated bytes. `scripts/test-theme-select.js` checks this boundary.
- Keep editor-family selection tied to generated theme bytes, the accepted stable-selector exception ([VGS-1868](https://linear.app/vanillagreen/issue/VGS-1868/editors-document-the-stamped-selector-exception-for-no-reload-themes)). Register the replacement before selecting it and retain the previously selected extension until a later apply. Never remove a theme still shown by an open window. Isolate failures between editors. `scripts/test-vgshell-vscode.sh` checks the writer.
- Keep absent user settings absent unless the target explicitly allows creating a managed selection for a detected app that does not create its own file. Registered vaults also need their application configuration directory. `scripts/test-vgshell-targets.sh` checks creation boundaries.
- Use the same `select` declaration for apply and Theme Setup. Report wired only for selection in the same application, profile or account. Keep account discovery in `AccountDirectories.js` and preserve project settings. `scripts/test-themes-setup.js` checks association.
- Keep native application precedence in target declarations and generated loaders: final includes stay final, deferred colour restoration follows native events, and init-file cache removal occurs only when the selector changes. `scripts/test-vgshell-targets.sh` checks the supported targets; local upstream reasons belong beside their implementations.
- Add no second shell initialization for Oh My Posh. Change only a supported existing literal initialization and report missing, dynamic or complex forms as unwired. `scripts/test-theme-select.js` checks refusal.
- Replace managed entry files and links by rename; never delete a directory at an entry path. A directory refuses that target. `scripts/test-vgshell-entries.sh` checks replacement.
- Preserve local customization in generated Yazi flavors for both configurations. Select bat and television through their native configuration, with cache rebuild after bat's theme file. Write no environment to override bat's external inputs. `scripts/test-vgshell-targets.sh` checks these boundaries.
- Add no Copilot CLI custom palette target without a supported custom-palette interface. Review holds this support boundary.
- Limit Claude Desktop writes to VGS's theme file and existing profiles' active selection. Preserve user overlays, local theme definitions and custom CSS; removing their conflicts belongs to Dots or Jarvis on the user side. VGS owns only its generated colours. `themes/targets/claude-desktop/` declares the target; review holds ownership.
- Never prompt on apply. Skip missing privileged setup and keep privileged writers' grammar narrow ([D029](../decisions/D029-chromium-policy-writer.md)). Hooks receive no streams or lock descriptor and end at their timeout. `scripts/test-vgshell-browser-policy.sh` and `scripts/test-vgshell-reload.sh` check these boundaries.
- Keep toolkit hooks conservative: link shipped themes only over absence or dangling links, replace no existing preference and select no unavailable system value. Parse `gum.env`, never source it. `scripts/test-vgshell-toolkits.sh` and `scripts/test-theme-gum.js` check these rules.
- Add no Hyprland target. Use the generated layer ([D028](../decisions/D028-one-generated-hyprland-layer.md)).
- Keep Claude Code's message bands distinct after both truecolor and palette reduction. Solve highlight colours through ThemeLogic, prioritizing readable code text over the best achievable count contrast. `scripts/test-theme-render.js` owns the floors and checks every catalog theme.

### Applying

- Stage and rename files, never modify `theme/` in place. Write the shell theme last, byte for byte. Repair includes, managed entries and selection on every apply. `scripts/test-vgshell.sh` checks ordering and repair.
- Reload btop even for selection-only repair. Keep its stable selector and unrelated settings. `scripts/test-theme-render.js` checks the always-due hook.
- Keep `last` includes after user lines without changing other lines. tmux owns colours, not layout or content: remove whole colour-bearing style spans but preserve colour-free options, commands and every format row, including empty rows. `scripts/test-theme-tmux.js` checks preservation.
- Render every tmux role through `theme-render.js::tmuxColors` as an ANSI identity or default, never hex, so an ssh attach follows the viewing terminal's palette. A package may differ from its preview where its palette cannot express the preview's colours. `scripts/test-theme-render.js` checks every shipped and catalog package.
- Preserve semantic hue, readable text and active/inactive separation in ANSI mapping. Keep grey muted ink grey when a qualifying slot exists; otherwise use the client's default text with dim styling. Keep filled labels on client-page text through reverse rather than a second on-colour role. `tmuxColors` owns the selection algorithm; `scripts/test-theme-render.js` checks it.
- Keep tmux RGB and truecolor environment entries for pane applications even with ANSI bar colours. Existing panes retain their environment; new clients and panes receive changes under tmux's native lifetime. `scripts/test-theme-tmux.js` checks declarations.
- Create nothing through a dangling symlink. Refuse the whole apply for an invalid configuration layer. `scripts/test-vgshell.sh` checks both refusals.
- Record due targets as pending before swap so reload can retry. Run hooks by target name, with declared `reload.last` hooks after the rest. Keep colour-scheme after toolkit changes. `scripts/test-vgshell-reload.sh` checks pending state and ordering.
- Follow package, target, template and terminal-font changes regardless of the theme file's current contents. Write nothing when inputs are unchanged. Keep background state on unchanged-package rerenders. `scripts/test-vgshell-follow.sh` and `scripts/test-vgshell-backgrounds.sh` check these boundaries.

### Catalog

- Keep first-party catalog data in `themes/catalog/` under one judged index. `bin/vgshell-theme-judge catalog-check` refuses invalid packages, symlinks, curated code targets and unconsumed files.
- Install catalog packages on demand as ordinary installed packages with a marker. Do not grant them shipped-package code trust or overwrite packages and user edits. Recover under the theme lock before install mutations. `scripts/test-vgshell-catalog.sh` checks trust and preservation.
- Keep readability fixes inside each package. `scripts/check-theme-contrast.js` checks shipped and catalog themes.
- Download wallpapers on demand from the index's pinned release archive over HTTPS. Hold the download lock for fetch and theme lock only for landing, then judge again. `scripts/test-theme-download.js` and `scripts/test-vgshell-wallpapers.sh` check these boundaries.

### Backgrounds

- Keep `bin/lib/theme-backgrounds.js` the sole production wallpaper-state writer and `WallpaperState.qml` its JSON reader. Sandbox checkpoint and restore belongs only to the nested row boundary. `scripts/test-vgshell-backgrounds.sh` checks production state; `scripts/test-smoke-persisted-inputs.py` checks isolation.
- Declare wallpaper names and per-output state through the judged maps, with no separate mode flag or seeded map. Set only listed images; theme apply clears per-output overrides. `scripts/test-theme-logic.js` and `scripts/test-vgshell-backgrounds.sh` check contracts.
- Map no background surface without a current image. Log unreadable image paths and use the existing current/applied-package recovery order without a retry timer. `scripts/smoke/rows/themes.sh` checks the surface.
- Keep user images outside packages. Give the wallpaper browser no add, remove or delete action. Review holds this boundary.

### Runner boundary

- Run plugin changes through capability `theme`; judge no package in the shell. Keep results in core ThemeRunner so view disposal loses nothing. Run wallpaper downloads outside the serialized command queue. `scripts/smoke/rows/themes.sh` and `theme-browse.sh` check the runner; review holds judge ownership.
- Keep view decisions in pure logic without QML objects or I/O, as `BrowserLogic.js` does. `scripts/test-themes-browser.js` checks it.
- Read browser data at service start and view opening, and coalesce watched changes while a view is open. Read no browser data on a timer or for hidden views; the next opening refreshes it. `scripts/qml-tests/tst_themes_service.qml` checks admission.
- Watch browser sources through one helper, `vgs.themes/helper/watch.py`, with one inotify instance and no per-package instances. Tie it to service registration, log failures with stderr and bound restarts per registration. `scripts/test-theme-watch.py`, `scripts/qml-tests/tst_themes_service.qml` and `scripts/smoke/rows/themes.sh` check the resource boundary. Its qualified measurement evidence is attached to [VGS-2218](https://linear.app/vanillagreen/issue/VGS-2218/theme-watches-use-a-bounded-number-of-inotify-instances).

## The canonical example

Copy `themes/targets/kitty/` for a data target and `themes/vgs/` for a package.

## Revisit when

Packages gain signatures or trusted authors, a theme needs code without a template, the catalog outgrows repository delivery, backgrounds need more than images, apply must retain per-output choices, or an app supports neither external colour files nor ANSI references. Other changes follow D021, D022 and D025's revisit conditions.

## Not governed

Drawing and readability belong to [design-system.md](design-system.md), Tokens.js and `ThemeLogic.readabilityShortfalls`. Configuration ownership belongs to [configuration.md](configuration.md). Target definitions and their one-time setup belong to `themes/targets/` and the Themes README.
