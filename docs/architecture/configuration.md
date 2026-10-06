# Shipped defaults under user edits, and no write without a read

Read before touching the configuration files, their merge, their judge or a write to them.

## The approach

The shell's configuration is two layers of `shell.json`: the shipped layer, `config/shell.json`, and the user layer, `shell.json` under `~/.config/vgshell/` (`XDG_CONFIG_HOME` when set), a directory `shell/Commons/Paths.qml` derives once. A user key replaces the shipped key whole, except `plugins`, merged by id with the user entry winning, and `disabledPlugins`, which is the user list when present; `PluginLogic.effectiveConfig` is the one merge ([D006](../decisions/D006-two-configuration-layers.md)). `shell/Core/Config.qml` is the one reader of both layers and the one writer of the user layer, and it never writes a file it has not read. The theme file, `theme.json` beside it, is the applied package's document with no layer over it ([D025](../decisions/D025-no-theme-override-layer.md)); `shell/Commons/ThemeSource.qml` reads it and `vgshell theme apply` writes it.

## Why

One file stops delivering shipped defaults the moment a user edits it, and a deep merge makes the effective value unreadable; merging by id keeps what is running readable from two files. A write over a file the shell could not read replaces the user's hand edit with the shell's last value, and the user loses work they never saw fail. A second writer, or a theme overlay merged over the package, makes every value the product of two sources that must agree.

## Rules

### Layers

- Do merge only through `PluginLogic.effectiveConfig`. `scripts/test-plugin-logic.js` pins each merge rule and the seeding of the user `bar` key.
- Do start an enable or disable edit from the effective disabled list, so a user file with no list keeps the shipped exclusions; an explicit empty user list still overrides them.
- Do read `welcome.keys` and `manager.id` from the shipped layer alone, as the shell reads the default bar; they name the product's own surfaces, not a user preference.

### Reads and writes

- Do judge each layer with `PluginLogic.configError` after every parse. A file that fails keeps its last good value, and the log names the defect.
- Never build anything before the configuration is ready: the shipped file has loaded once and the user file has settled, so a bar never draws from the user file alone.
- Never write the user file unless it is `loaded` or `absent`, so an unparseable, unreadable or malformed file is never overwritten unread. After the disk refuses a write, refuse every write until the file is read again.
- Do answer `ok` only once the file holds the edit. `scripts/smoke/rows/style.sh` stops the shell as a toggle answers and reads the file.
- Never drop a key the shell does not read; a write carries every other key untouched.
- Do read a file again when an edit lands during a read, through `WatchedFile`, so the last edit is the one the configuration holds.

### Unknown ids

- Do keep an id that `plugins` or `disabledPlugins` lists and no discovered plugin has, as a removed plugin leaves behind, in the file, and report it: `PluginLogic.unknownIds` names each one with its key, `listPlugins` carries it as `unknown`, and `vgshell plugin list` prints it. `scripts/test-plugin-logic.js`, `scripts/test-vgshell-plugin-list.sh` and `scripts/smoke/rows/configuration.sh` pin the rule, the line and the shell's report.

### Theme file

- Do judge `theme.json` with `ThemeLogic.accept` alone. An absent file publishes the defaults; a file that becomes unreadable or that the judge refuses is logged and leaves the last accepted theme.
- Never merge a user layer over the applied theme. A lasting change is an edited copy installed as its own package ([D025](../decisions/D025-no-theme-override-layer.md)).

## The canonical example

`writeUser` in `shell/Core/Config.qml`: the state check before any write, the held disk error, and `ok` only once the file holds the value. Copy its shape for any file the shell writes on the user's behalf.

## Revisit when

A third system-wide layer under `/etc` is needed, a shipped default must override a user value, or users need a local theme change that follows upstream updates of an installed package.

## Not governed

Each key's shape, which `PluginLogic.configError` judges; the theme document's tiers and tokens, which is [design-system.md](design-system.md); what `vgshell theme apply` writes and when, which is [themes.md](themes.md).
