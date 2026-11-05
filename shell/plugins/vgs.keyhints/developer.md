# Key Hints developer reference

Read when changing shortcut rows or key capture. The [manifest](manifest.json) declares the toggle binding. [Service.qml](Service.qml) registers it and toggles the window on the focused monitor.

## Window and key writes

[Window.qml](Window.qml) accepts an empty payload or an empty JSON object. Any other payload refuses the summon.

The window reads plugin binds from the manager and renders the shared `BindField`. It adds no key store or conflict judge. Writes go through `shell.manager.setKey`, so Key Hints and the Settings Keys row change the same configuration. `Reply.line` supplies the shared refusal text, and a refused write leaves the stored key in place.

The [Hyprland contract](../../../docs/architecture/hyprland.md) owns binding conflicts and unbound shortcuts. [The nested validation row](../../../scripts/smoke/rows/keyhints.sh) checks the manager rows against the compositor and Settings.

## Summon

<details>
<summary>Show command</summary>

```text
vgshell ipc call shell summon window vgs.keyhints '{}'
```

</details>
