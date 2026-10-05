# Configuration

Covers: shell/Core/Config.qml, shell/Commons/Paths.qml, shell/Commons/WatchedFile.qml, config/shell.json

The shell's configuration files: two layers of `shell.json` merged by entry id, and the theme file. `shell/Core/Config.qml` reads the first two, `shell/Commons/ThemeSource.qml` the third, and `shell/Commons/Paths.qml` derives the user directory once for both. `Paths.stateDir` is the directory `vgshell theme` keeps what it applied in, which the `vgs.themes` plugin reads for the wallpaper: [theme-backgrounds.md](theme-backgrounds.md).

## Layers

`config/shell.json` is the shipped layer and `~/.config/vgshell/shell.json` (under `XDG_CONFIG_HOME` when set) the user layer, [D006](../decisions/D006-two-configuration-layers.md). `PluginLogic.effectiveConfig` merges them: a user key replaces the shipped key whole, except `plugins`, merged by id with the user entry winning, and `disabledPlugins`, which is the user list when present. `scripts/test-plugin-logic.js` pins each merge rule and the seeding of the user `bar` key.

An enable or disable edit starts with the effective disabled list. This preserves inherited exclusions when the user file has no list. An explicit empty user list still overrides the shipped exclusions.

## shell.json keys

Both layers share one shape, judged by `PluginLogic.configError` after every parse. A file that fails the judge is in the `malformed` state: the last good value stands and the log names the defect. A user file in that state refuses every write until it passes again. The shell reads every key of the table but `disabledTargets`, which only `vgshell theme apply` reads ([theme-apply.md § Apply](theme-apply.md#apply)), and `packages`, which only `vgshell pkg run` reads. The shell carries that key, and any key outside this table, untouched.

| Key | Shape |
|---|---|
| `version` | `1` when present. |
| `bar.id` | A string: the active bar's plugin id. |
| `bar.layout.left[]`, `bar.layout.center[]`, `bar.layout.right[]` | Objects, each with a string `id` and the widget's settings beside it. |
| `plugins[]` | Objects, each with a string `id` and the plugin's settings beside it. |
| `plugins[].keys` | An object: each name is a shortcut the plugin's manifest binds in `hyprland.binds`, and each value the key that replaces its default, such as `SUPER+ALT+SPACE` or `SUPER+code:108`, or `null` to unbind it. `PluginLogic.hyprlandSection` resolves it for the layer and the plugin's read-only `shell.shortcut.keys`: [hyprland.md](hyprland.md). The manager's `setKey` writes it, normalised, from the Settings window's Keys rows, [manager.md](manager.md). A name the manifest binds nothing under is reported by `listPlugins`, not refused. |
| `disabledPlugins[]` | Strings: plugin ids. |
| `disabledTargets[]` | Strings: theme target names an apply skips. A user list replaces the shipped one. |
| `welcome.keys[]` | Objects, each with a string `id`, a string `shortcut` and non-empty string `text`: one key line of the first-start welcome, drawn as `<key> <text>` while plugin `id` binds `shortcut` ([requirement-notice.md](requirement-notice.md)). The shell reads it from the shipped layer alone, as it reads the default bar. |
| `packages.elevate` | `sudo`, `doas` or `run0`, from `PackageManagers.ELEVATORS`: the command `vgshell pkg run` puts before a step that needs root. Without it, the first of the three on PATH. `packages` is an object; a user `packages` replaces the shipped one whole. [packages.md § Running a plan](packages.md#running-a-plan). |

## Unknown ids

An id `disabledPlugins` or `plugins` lists that no discovered plugin has, as a removed plugin leaves behind, enables and disables nothing, and the shell keeps it in the file. `PluginLogic.unknownIds` names each one with the key that lists it, once per key. `listPlugins` carries the rows as `unknown` once the first scan has completed, and `vgshell plugin list` prints one `unknown <id> in <key>` line per row. `scripts/test-plugin-logic.js` pins the rule, `scripts/test-vgshell-plugin-list.sh` the line, and `scripts/smoke/rows/configuration.sh` the shell's report of a stale `disabledPlugins` entry.

## States

- Each file is in one state: `pending`, `loaded`, `absent` (the user file), `unparseable`, `unreadable` or `malformed`. `listPlugins` reports both.
- The configuration is ready once the shipped file has loaded once and the user file has settled. Nothing is built before that, so a bar never draws from the user file alone.
- A file that fails after one load keeps its last good value, so the shell draws from what it has and the log names the cause.
- Each layer retains its accepted text. A reload of identical text keeps the value object, so a manager write and its file notification produce one configuration change.
- Every write is refused unless the user file is `loaded` or `absent`, so a file the shell could not read is never overwritten unread. `ok` from a write means the file holds the edit: the shell writes before it answers, so a stop right after the answer keeps it. `scripts/smoke/rows/style.sh` stops the shell as a toggle answers and reads the file.
- A write the disk refuses answers `refused: user-config=unwritable` with the error and leaves the value in memory as it was. Every write is refused that way until the shell has read the file again.
- An edit to either file that lands while the shell reads it is read again, so the last edit is the one the configuration holds.

## Theme

`~/.config/vgshell/theme.json` holds the shell document: `schemaVersion`, `name` and `tokens`, a nested tree of overrides for the token table. `ThemeSource.qml` reads it the way `Config.qml` reads `shell.json`, and `ThemeLogic.accept` is the one judge of the document. An absent file, including one deleted while the shell runs, publishes the defaults, the same theme a fresh start without the file draws. A file that becomes unreadable or that the judge refuses is logged with its token and reason and leaves the last accepted theme. The document shape, the tiers and the expression grammar are in [design-system.md](design-system.md). The file is the applied package's document: `vgshell theme apply <name>` replaces it with the package's `theme.json` bytes, and `vgshell theme list` reports it modified when a hand edit makes it differ, [theme-apply.md § Apply](theme-apply.md#apply). No overlay layer merges over it; reverting an edit is applying the package again, and a lasting change is an edited copy installed as its own package, [D025](../decisions/D025-no-theme-override-layer.md). A five-key palette file is refused by its first key, and the defaults draw.

## Decisions

[D006](../decisions/D006-two-configuration-layers.md), [D025](../decisions/D025-no-theme-override-layer.md).
