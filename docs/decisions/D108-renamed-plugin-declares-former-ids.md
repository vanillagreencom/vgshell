# D108: A renamed plugin declares its former ids

[← Decision Index](INDEX.md)

**Date**: 2026-10-17

**Status**: Active

**Research**: [VGS-1742](https://linear.app/vanillagreen/issue/VGS-1742): overseer ruling on the D003 conflict (option b).

**Refines**: [D107](D107-format-change-ships-its-migration.md), for a plugin id change in `shell.json`: the converter step is a manifest declaration, not a format version.

**Decision**: A plugin that changes its id lists each id it shipped under in its manifest's `formerIds`. `PluginLogic.formerIdClaims` builds a rename map from the scanned manifests and leaves out a claim of a former id that a scanned plugin holds. A bundled plugin's claim wins over an installed plugin's whatever the scan order, so a plugin the user installs cannot take a first-party plugin's settings, disable or placement; within one source the first claim in scan order wins. A claim left out is logged and does not refuse its manifest. `ConfigLogic.renamePlugins` applies the map to the user file. `Config.qml` renames the file when the scan hands it the map, before the registry publishes the manifests, and when it reads the file, and writes the result once. The rename covers `plugins[]` rows, `disabledPlugins` and `bar.layout` entries alone; `sounds`, `bar.id`, `manager.id` and `welcome.keys` keep the former id. A former id stays in the manifest for as long as the plugin ships. `CONFIG_VERSION` does not change for a rename.

**Why**: The core names no plugin ([D003](D003-everything-is-a-plugin.md)), so a table of old and new ids in `ConfigLogic.js` breaks the boundary, and each later rename would need a core change and a version bump. A version cannot record which plugins are installed, and an old id is a valid version 2 file. The declaration is the converter step D107 requires: removing it would make a user who skipped the renaming release lose their settings, their disable and their bar placement, and would let a plugin they disabled start.

**Rejected**: A rename table in `ConfigLogic.js` under a version bump, because it names a plugin in the core. The plugin's own service renaming its entries, because a disabled plugin never runs and a service writes only its own row.

**Revisit when**: A bar, the manager, a plugin with `sounds` or a plugin named in `welcome.keys` changes its id, or two installed plugins must claim one former id.
