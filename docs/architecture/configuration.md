# Shipped defaults under user edits, and no write without a read

Read before touching the configuration files, their merge, their judge or a write to them.

## The approach

`ConfigLogic.effectiveConfig` merges the shipped and user `shell.json` layers ([D006](../decisions/D006-two-configuration-layers.md)). `shell/Core/Config.qml` owns their reads and the user layer's writes. It never replaces a file it could not read.

The applied `theme.json` has no user layer ([D025](../decisions/D025-no-theme-override-layer.md)). The user's Appearance values in `shell.json` are the exception ([D104](../decisions/D104-appearance-values-over-the-theme.md)).

## Why

Separate shipped defaults let an update reach values the user has not changed. One merge and one writer keep precedence and write failures consistent. Refusing a write after a failed read protects edits the shell has not seen.

## Rules

### Layers and settings

- Merge only through `ConfigLogic.effectiveConfig`. Start enable and disable edits from the effective disabled list; an explicit empty user list still overrides the shipped list. `scripts/test-plugin-logic.js` checks these rules.
- Read product surface identities, including `welcome.keys`, `manager.id` and the default bar, from the shipped layer alone. Review holds this boundary.
- Keep a plugin's settings in its `plugins[]` row for every instance and the Settings page. A `bar.layout` entry places a widget and holds only its id. `ConfigLogic.configError` judges the shape; `PluginLogic.settingsFor` owns the runtime settings.
- Declare a value kept by a plugin surface in `settings`, even when it has no Settings field. Use `configure` to write it. `PluginLogic.settingRefusal` checks its JSON type; the plugin owns its range check.
- Pass control values through `PluginLogic.settingRefusal`, `withSetting`, `keyRefusal` and `withKey`. Their `controlValue` conversion handles values delivered through QML signals. Never add a page-specific conversion.
- Keep joined program choices in the existing string setting. Declare atomic presets and their separator. `SettingField` preserves unknown tokens and their order, and opening the field writes nothing. `scripts/qml-tests/tst_settingfield.qml` checks the control.
- Omit undeclared saved settings from runtime settings and the row a normal setting write updates. Preserve reserved `keys`. Keep undiscovered plugin ids in the user file and report them through `PluginLogic.unknownIds`; removal of a plugin must not erase its saved configuration. `scripts/test-plugin-logic.js` checks these rules.

### Migrations

- Run retained format converters at the user-file read boundary through `ConfigLogic.migrateConfig`, before the current judge ([D107](../decisions/D107-format-change-ships-its-migration.md)). `Config.qml` writes the conversion once; `bin/` readers use it in memory. Keep converters and their shipped context usable across skipped releases.
- Save the source bytes to `Config.preConversionPath` before writing a format conversion. Replace that one state-directory copy on the next conversion; never remove it on a current-format read. Refuse writes if saving or confirming the copy fails. `scripts/qml-tests/tst_config_writes.qml` checks this boundary.
- Take migration source identities from the shipped layer alone. The package review transfer uses `packageReviewSettingsSource`, runs after layout conversion and preserves destination presence, including false and empty strings. Never invent a saved preference from a manifest default. Invalid source types refuse conversion. `ConfigLogic.migratePackageReview` and `scripts/test-plugin-logic.js` own these semantics.
- Edit shared package review choices through `ConfigLogic.withPackageReview`. Confirm a live write against fresh disk bytes and the writer's read state. An unconfirmed live reply never authorizes an offline retry. Without a shell, use the guarded writer in `bin/lib/judge-files.js`.
- Rename former plugin ids before publishing the scan, through `PluginLogic.formerIdClaims`, `Config.adoptRenames` and `ConfigLogic.renamePlugins` ([D108](../decisions/D108-renamed-plugin-declares-former-ids.md)). Only bundled claims grant rename authority; exclude a claim on a scanned plugin's id. Preserve settings, disablement and placement, and keep the converted value in memory if disk refuses it. `scripts/qml-tests/tst_config_writes.qml` checks writes; review holds publication order.
- Apply bundled splits after renames, before scan publication and on later user-file reads ([D110](../decisions/D110-tailscale-and-vpn-split.md)). `ConfigLogic.splitPlugins` copies only declared target settings and preserves an already referenced target. Record each new target so later user edits cannot repeat the split. A first write of an absent file records targets without copying that new edit. Installed claims grant no split authority.

The `bin/` readers do not apply plugin renames or splits. They can read and write former ids until the shell has read and written the user file. Keep this limitation explicit when changing an offline reader.

### Reads and writes

- Judge each parsed layer with `ConfigLogic.configError`. Log a refusal and keep the last good value.
- Classify a whole-number version above this build's format through `ConfigLogic.configResult` as `newer`, not damaged. Read no fields of that format and refuse writes. The existing core notice names the file, both versions, that the file is untouched and the retained pre-conversion copy when present. `scripts/test-plugin-logic.js` checks the judgement; review holds the notice.
- Build nothing until the shipped file has loaded and the user file has settled. Review holds this startup boundary; no row starts with an unsettled user file.
- Write the user file only in `loaded` or `absent` state. After a disk refusal, block writes until another read. Answer `ok` only when the file holds the edit. `scripts/qml-tests/tst_config_writes.qml` checks the writer.
- Preserve unrelated keys. `scripts/test-plugin-logic.js` checks the edit functions; review holds other writes.
- Use `WatchedFile` to read an edit that arrives during a read. `scripts/qml-tests/tst_watched_file.qml` checks this boundary.

### Theme file

- Judge `theme.json` only through `ThemeLogic.accept`. Absence publishes defaults; a later unreadable or refused file keeps the last accepted theme.
- Make a lasting theme change as its own package. Resolve only the allowed Appearance values over it, through `ThemeLogic.withAppearance`; never accept a colour override.
- Write Appearance values only through capability `appearance`, after `ThemeLogic.appearanceRefusal`. The configuration judge checks shape alone; a bad member must not block unrelated keys. `scripts/test-theme-logic.js` and `scripts/test-plugin-logic.js` check these boundaries.

## The canonical example

Copy `writeUser` in `shell/Core/Config.qml` for a file written on the user's behalf: check read state, hold disk errors and confirm persistence before success.

## Revisit when

A system-wide layer under `/etc` is needed, a shipped default must override a user value, or a local theme change must follow upstream package updates.

## Not governed

Key shapes belong to `ConfigLogic.configError`. Drawing rules belong to [design-system.md](design-system.md); theme installation and apply belong to [themes.md](themes.md).
