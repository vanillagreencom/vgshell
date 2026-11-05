# Dev Tools developer reference

Read when adding a catalog row or changing tool execution. The [manifest](manifest.json) owns plugin settings and TUI declarations. [CatalogLogic.js](CatalogLogic.js) judges [catalog.json](catalog.json); its callers supply the package-manager IDs, icons, appearance table and package-name rule.

## Catalog and engine

[bin/devtools](bin/devtools) owns tool discovery, execution and launcher files. Its header defines the verbs, row output and refusals. The [catalog contract](../../../docs/architecture/commands-are-data.md#dev-tools-catalog) governs install routes and data boundaries.

A row's presence probe is separate from its install route. A removal that leaves the probe satisfied reports `present=remains`; it does not claim to remove a copy supplied outside VGS. A tool declared only in the owner's mise configuration is not a catalog install target.

The engine's terminal admission applies to mutations. The declared [TUI](tui/devtools.sh) runs them; the window does not install in a background process. Mise execution uses the row's build environment and disables automatic pruning before an upgrade, so a running session can keep its executable. The engine owns that preparation and any post-install work.

## Service and view

[Service.qml](Service.qml) owns queries and publishes their results. [Query.qml](Query.qml) owns each query process. The trigger table in the service header defines which events refresh local and network answers. [ViewLogic.js](ViewLogic.js) owns presentation decisions, including failures that retain the last count.

The window opens on search, not a mutation button. [The nested validation row](../../../scripts/smoke/rows/devtools.sh) checks initial focus before it runs fixture TUIs.

## Launcher files

The engine recognizes its launchers by `LAUNCHER_MARK`. It preserves foreign files and links and avoids writing a launcher that would hide another installed command. An installed row with an `exec` path retains its required launcher even when optional launcher writing is off. The engine's launcher functions own those distinctions.

## Developer command

Run the engine from the plugin directory with the VGS tree supplied explicitly.

<details>
<summary>Show command</summary>

```text
bin/devtools --tree <dir> list --json
```

</details>
