# One judge decides every manifest

Read before touching a manifest key, `PluginLogic.validateManifest`, the settings schema, or a plugin's `hyprland`, `status`, `tui`, `menu` or `extras` entry.

## The approach

A plugin is a directory with `manifest.json` at its root. `shell/Core/PluginLogic.js` is the one judge of a manifest, offline and in the shell alike: `bin/lib/check-manifests.js` and `vgshell plugin validate` run the same file under node, and `scripts/test-plugin-logic.js` pins each refusal. A key the judge does not list refuses the manifest, so a misspelt key fails loudly instead of being carried and ignored. The schema is VGS's own ([D011](../decisions/D011-native-manifest-no-cross-shell-compatibility.md)), and every key below is data the core renders: a plugin never ships page code, Lua or a command string.

## Why

A carried-and-ignored key hides a typo until a user reports the missing feature. One judge with one list has no second format to drift from, and a judge that runs under node tests in milliseconds without a compositor ([D009](../decisions/D009-one-manifest-judge-under-node.md)).

## Rules

- Never add a manifest key without adding it to the judge and a refusal row to `scripts/test-plugin-logic.js`; `bin/lib/check-manifests.js` validates every bundled manifest offline.
- Do give every `schema` entry a default of its type, inside its bounds, in `settings`; never declare both `presets` and `optionsFrom` on one string entry. `scripts/test-plugin-logic.js` pins both.
- Do judge a `list` entry's items through `shell/Core/Pads.js`; `scripts/test-pads.js` pins each refusal.
- Do declare an owner-only extra under `extras` with its own status and requirement entries and no schema entry ([D075](../decisions/D075-consumer-features-need-no-developer-setup.md)); `scripts/test-plugin-extras.js` pins it.
- Do declare a status entry's setup step as an `action` and its command only behind "Show command" ([D061](../decisions/D061-no-manual-commands.md)); `PluginLogic.statusError` refuses a command without its action.
- Never name a plugin in `requirements`; a dotted command is refused because it reads as a plugin id ([D035](../decisions/D035-manifest-requirements.md)).

## The canonical example

`shell/plugins/vgs.tray/manifest.json`: kinds, one capability, a schema with defaults in `settings`, and nothing the core does not render. Copy it.

## Revisit when

A plugin marketplace with a stable, versioned schema exists that VGS gains more from joining than from owning its own, or a plugin needs a setting no schema type can hold.

## Not governed

What a kind is and how an instance is built, which is [overview.md](overview.md); the capabilities the keys name, which is [capabilities.md](capabilities.md). The key table below is reference content; its home is the vgs-plugin skill's `references/api.md` § Manifest once that file takes it.

## Manifest

| Field | Required | Meaning |
|---|---|---|
| `schemaVersion` | yes | `1`. Any other value refuses the plugin. |
| `id` | yes | Dotted and author-namespaced, lower case: `author.name`. `vgs.*` is first-party. |
| `name`, `version`, `author`, `description` | yes | Listing metadata, non-empty strings. |
| `license` | no | A non-empty string when present. The judge checks nothing more about it. |
| `icon` | no | A Lucide name from the shipped set, `shell/Ui/icons/Lucide.js`, which `PluginLogic.js` imports; the Settings window lists the plugin with it, and with `package` when absent. |
| `kinds` | yes | One or more of the kinds `PluginLogic.KINDS` lists and [overview.md § Vocabulary](overview.md) defines, each once. |
| `entryPoints` | yes | One QML file per declared kind, keyed by the kind name, relative to the plugin root and inside it. A key naming an undeclared kind is refused. |
| `capabilities` | no | Core APIs the plugin uses beyond its kinds, from the table under § Capabilities. |
| `settings` | no | The plugin's default settings, an object without an `id` or a `keys` key. The configuration entry for the plugin overrides them key by key. `placement` is reserved: the core reads it for a summoned panel or menu, and a value outside `PluginLogic.PLACEMENTS` refuses the manifest. |
| `schema` | no | The settings a user or the plugin itself may change, keyed by setting name. [Settings schema](#settings-schema) defines entry keys, presets, runtime choices, units and fields. Required with capability `configure`. |
| `defaultSection` | no | `left`, `center` or `right`: where `vgshell plugin enable` places a bar widget that has no placement. Needs kind `bar-widget`; `center` when absent. |
| `optIn` | no | Boolean. `true` keeps a first-party plugin off until it is enabled: it takes the `row` rule of `PluginLogic.enablementRule` ([manager.md](manager.md)). Refused for kind `bar` and for a plugin whose only kind is `bar-widget`. |
| `alwaysOn` | no | Boolean. `true` keeps the plugin enabled whatever the configuration says, a `disabledPlugins` entry included, and the core refuses its disable ([manager.md](manager.md)). Needs the `first-party` rule of `PluginLogic.enablementRule`. |
| `pane` | no | `{ group, order }` for kind `pane`. `group` is the section heading the panes holder lists the plugin under, and `order` sorts it inside that group. Needs kind `pane`; kind `pane` needs it. |
| `appearance` | no | A `.js` file inside the plugin holding the plugin's own look, which the theme reaches through its mode and accent alone: [appearance.md](appearance.md). |
| `status` | no | The runtime values the plugin publishes through capability `status`, which the manifest must name, each `{ type, label, group?, hint?, info?, action?, actions?, command?, hidden? }`; its instances read them and the Settings page draws them, with an entry's `action`, or the one of a `state` entry's named `actions` its value names, as a one-click setup step and its `command` behind Show command. `info` adds an icon that opens one short explanation. The page draws both only while the action applies to the published value, a `presence` while `absent` and a `state` while it carries `action: true` or an action's name, and neither while the value is present, healthy or unreported, so a command shows only beside its offered step: [status.md](status.md), [settings-window.md](settings-window.md), [D061](../decisions/D061-no-manual-commands.md). |
| `secrets` | no | `{ service, label }`: the libsecret items the core stores and clears for the plugin from a masked field on its Settings page. Needs capability `secrets` and a `presenceList` status entry whose items name each account: [status.md](status.md). |
| `extras` | no | Owner-only extras, features that need developer setup such as a token from an app the user must create, which no consumer sees ([D075](../decisions/D075-consumer-features-need-no-developer-setup.md)). Each key names a setting whose default is `false` and which has no `schema` entry; its entry lists `status`, the drawn status entries only it uses, and `requirements`, the optional requirements only it uses, each non-empty when present, and no entry serves two extras. While the setting is not `true`, `PluginLogic.activeManifest` leaves them out of the Settings page, the manager's steps, the requirement notice and the requirement reports. The plugin's README documents each under "Extras (not supported)". |
| `hyprland` | no | What the plugin asks of Hyprland, as data the core renders into the Hyprland layer: `binds`, a list of `{ shortcut, key, hold?, tap? }`, each a shortcut the plugin registers through capability `shortcut`, which the manifest must name, and its default key such as `SUPER+SPACE`, or `null` for none, which the Settings page's Keys row lets the user replace by pressing a combo in a `ShortcutField` ([D086](../decisions/D086-key-capture-passthrough-submap.md)); optional boolean `hold` adds the release bind defined in [hyprland-shortcuts.md § Hold shortcuts](hyprland-shortcuts.md), and optional boolean `tap` fires on a tap of a lone key. `layerRules` is a list of `{ namespace, blur, ignoreAlpha }` for `^vgs:<name>$`, the core hosts' namespaces; `appearance` maps `borders`, `radius`, `motion` or `noGaps` to a boolean schema key for a plugin with capability `theme`, `noGaps` a workspace rule that holds over a user's later `general` gaps ([hyprland.md](hyprland.md)); `options` maps a schema key to an input option path of the core's table for a plugin with capability `hyprland`, written only while the plugin's `plugins` row sets that key: [hyprland.md](hyprland.md); `pads` names a `list` schema setting whose items are pads, below. At least one of `binds`, `layerRules`, `appearance`, `options` or `pads` is declared, and no shortcut, key or namespace appears twice. An appearance-only section is valid: [hyprland.md](hyprland.md). |
| `requirements` | no | The external requirements the plugin uses, each `{ command, packages, optional, purpose }` or `{ dbus: { bus, name }, packages, optional, purpose }`: a bare command name or a D-Bus name on the system or session bus, its package per manager id, whether the plugin works without it, and one line on what it is for. The Settings page lists each with its state and offers Install all missing while one is missing. A requirement never names a plugin, and `requires` is refused: [requirements.md](requirements.md). |
| `tui` | no | Floating TUI scripts: [tui-capability.md](tui-capability.md). |
| `menu` | no | Launcher rows, keyed by a dotted id whose dots name its parent, as in the launcher's menu files. Each row has a printable `label`, an `icon` from the shipped set and optional `aliases` and `description`. A row with `shortcut`, one of the plugin's own registered shortcut names, needs capability `shortcut` and runs that shortcut. A row with `tui` names `core/<name>` or `<plugin id>/<name>`, and opens that listed TUI through the launcher. A row with `tuiGroup` opens the first listed TUI in that group. A row without `shortcut`, `tui` or `tuiGroup` is a category. `provider` names one of this manifest's `launcherRows` status keys, needs `shortcut`, refuses `toggle`, `tui` and `tuiGroup`, and fills this row as a category with plugin-published rows; selecting a published non-menu row calls the shortcut with that row id. `toggle`, `{ setting, label, icon? }`, needs a `shortcut`, refuses `tui` and `tuiGroup`, and names a boolean schema entry: while the plugin's `plugins` row sets it true, the row shows `toggle.label` and its icon, so the label always names what selecting the row does. A row states at most one of `shortcut`, `tui` and `tuiGroup`. The core lists every enabled plugin's rows through capability `shortcut`, and the launcher shows them: [capabilities.md § Launcher rows](capabilities.md). |
| `systemSteps` | no | The core's system steps the plugin offers, each once, from `PluginLogic.SYSTEM_STEPS`; needs capability `system`, which lends their probed states, and a status action `{ label, system }` applies one: [system-steps.md](system-steps.md). |

A string `schema` entry may carry `optionsFrom`, the key of its own plugin's `choices` status. The judge verifies the reference. The editor and retained-value contract is [status.md § Setting choices](status.md).

## Settings schema

Each entry has `type`, one of `string`, `number`, `boolean`, `enum` or `list`; `label`; optional `description`; optional `info`, one short explanation opened from an icon; and optional `group`, a non-empty section heading. An `enum` has `options`, a non-empty list of distinct non-empty strings. A `number` may take finite `min` and `max`, with `min` below `max`, and a positive `step`; these keys are refused on other types. Every entry needs a default of its type, inside its bounds, in `settings`. A written number outside its bounds is refused. `step` refuses nothing.

A `string` entry declares `presets` or `optionsFrom`. It never declares both. `optionsFrom` names a `choices` status entry of the same plugin. `presets` is a non-empty list of `{ value, label? }` entries on a `string` or `number`. Each value fits the entry's type, bounds and format, and values are distinct. `label`, when present, is one printable line. An empty string preset has a label.

`allowCustom` is a boolean that needs `presets`. Without it, a written value must equal one preset. With it, any value that fits the entry is accepted. `format` is for a `string` with `presets`. The only format is `datetime`, a Qt date and time format. `unit` is for `number`: `seconds`, `minutes`, `hours` or `days`, which the page converts to the largest whole unit, `%`, which it draws after the number, or `×`, which it draws after a multiplier.

The Settings window draws one field per entry in key order, ungrouped entries first, then each group in the order its first entry appears. A boolean uses a switch. An enum with at most three options uses a segmented control, and a larger enum uses a select. A string with `optionsFrom` uses a select. A string or number with presets uses a select, and adds Custom… when `allowCustom` is true. A bounded number uses a slider, and a `unit` labels the value. A `list` has its own section: [settings-window.md](settings-window.md).

A `list` entry holds `items`, a flat schema of its items' fields, and `defaults`, the value of each field a new item takes, judged as a manifest's `schema` and `settings` are: an item field is any entry above but a `list`, and none is named `name`. Its value is a list of objects, each with every field and a `name` of lower case letters, digits and dashes no other item holds. `Pads.js` judges both and `scripts/test-pads.js` pins each refusal. A `list` entry's string fields with `optionsFrom` take their Select models as [status.md § Setting choices](status.md) sets out.

## Pads

`hyprland.pads` names a `list` setting and needs capability `shortcut`. Its items hold the fields the layer renders, each of its type: `class`, a string, the window class the pad holds; `width` and `height`, numbers whose `min` and `max` lie within 1 to 100, shares of the work area in percent; `position`, an enum of `center`, `top`, `bottom`, `left`, `right`, `top-left`, `top-right`, `bottom-left` and `bottom-right`; `margin`, a number within 0 to 50, a share of the work area's shorter side; `entry`, an enum of `top`, `bottom`, `left` and `right`; and `motion`, an enum of `slide`, `fade` and `none`. Other item fields are the plugin's own. Each item is a pad named by its `name`: a bind `pad-<name>`, which the plugin registers, with the key the plugins row's `keys` gives it and none by default, and the layer's pad ([hyprland.md](hyprland.md)). A pad whose class holds a character outside `A-Z a-z 0-9 . _ -`, or whose class an earlier pad holds, is left out of the layer and reported as `hyprland: pad <name> of <id> skipped: <reason>`; it keeps its bind, so its key stays set and its press reaches the plugin. A plugin whose pads another plugin before it by id defines is reported as `hyprland: pads of <id> skipped: already defined by <owner>`. A key set for a pad that is not listed is kept, so a pad added again takes it, and is no unknown key. [D102](../decisions/D102-pads-tiled-in-their-special-workspace.md) records the choice.
