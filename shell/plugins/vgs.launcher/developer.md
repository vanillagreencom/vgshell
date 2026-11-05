# Launcher developer reference

Read when changing menu composition, summon payloads or picker completion. The [manifest](manifest.json) owns entry points, bindings, appearance and layer rules. [Service.qml](Service.qml) registers toggle and summon; [Launcher.qml](Launcher.qml) owns the open overlay's state.

## Payload

[MenuModel.js](MenuModel.js) defines accepted payload keys and types in `parsePayload`. Empty input means an empty object. Menu routes can open a menu or run a resolved action directly; query text initializes search.

Picker modes require distinct selection and completion paths inside the runtime directory. A successful selection writes the selection before the completion marker. Cancellation writes only the completion marker. A failed selection write reports an error through that marker. Read the marker before treating any selection file as this request's result.

`Launcher.finishRequest` answers a request once, including cancellation on hide, replacement summon and destruction. Keep that ownership when changing the overlay lifecycle.

<details>
<summary>Show command</summary>

```text
vgshell ipc call shell summon overlay vgs.launcher '{"menu":"system"}'
```

</details>

## Menu composition

[menu.json](menu.json) declares shipped rows. The user's launcher menu merges per ID and per key. Enabled plugin rows merge between the shipped and user rows. A plugin cannot replace a shipped row; a user row can replace a plugin row's action kind. A missing parent hides its descendants.

`MenuModel.ITEM_KEYS`, `PROVIDERS` and `itemError` own the menu-file contract. Plugin providers enter through `pluginEntries`, not a menu file. Do not copy the manifest's plugin-row shape into a menu file.

TUI rows resolve against the core's listed entries. An unavailable entry hides its row. A busy TUI counts as a successful handoff after the core focuses its window; another refusal stays visible. [Commands as data](../../../docs/architecture/commands-are-data.md#commands-as-data) owns TUI admission and argv construction.

## Files and navigation

[file-search.sh](file-search.sh) defines its protocol, index limits and refusal keys. [FileSearch.qml](FileSearch.qml) owns the helper process. `MenuModel` owns parsing and ranking; the overlay owns selection and open-with actions.

The overlay's key handlers and `navigate` implement list navigation. The [Hyprland key contract](../../../docs/architecture/hyprland.md#keys) owns delivery of the user's directional focus keys.

## Appearance and shader

[Appearance.js](Appearance.js) owns the plugin's appearance values. The [appearance contract](../../../docs/architecture/design-system.md#appearance) defines the theme inputs. The shared glass component consumes the plugin's fill and rounding; the manifest declares blur for the overlay layer.

After changing [the edge shader](shaders/edgelight.frag), regenerate its adjacent compiled asset from this plugin directory.

<details>
<summary>Show command</summary>

```text
/usr/lib/qt6/bin/qsb --glsl "100es,120,150" --hlsl 50 --msl 12 -o shaders/edgelight.frag.qsb shaders/edgelight.frag
```

</details>
