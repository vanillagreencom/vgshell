# Everything outside the core is a plugin

Read before structural work, before writing a plugin, a host or a capability provider, and before adding a kind, a capability or a manifest key.

## The approach

Every visible surface and background service is a plugin: one directory with a manifest. The core holds what must exist before plugins run and keep working when a plugin fails ([D003](../decisions/D003-everything-is-a-plugin.md)).

A host gives each declared kind a place to draw. Each instance receives a scoped `shell` object with its declared capabilities, released with that instance ([D005](../decisions/D005-kinds-are-surfaces-no-dependencies.md), [D012](../decisions/D012-core-owns-lent-objects.md)). A missing host prevents that kind from building without disabling the plugin's other kinds. This boundary is scoped authority and static import checking, not a process sandbox ([D010](../decisions/D010-facade-scope-not-sandbox.md)).

## Why

A small core limits the effect of feature changes. Hosts and capabilities let plugins share infrastructure without introducing plugin dependencies or a load order.

## Rules

### Plugins

- Put a new surface or service in its own plugin directory and manifest. Review holds this boundary.
- Import only modules `scripts/check-plugin-boundary.py` permits and files inside the plugin. Never import another plugin or a core file, create a surface, instantiate a lent object or call `Hyprland.dispatch`. That checker enforces these boundaries.
- Judge status replies through `shell.status.isOk` before a literal comparison. `scripts/check-plugin-boundary.py` checks direct comparisons and local `const` or `let` bindings; review holds replies that leave that binding.
- Declare no plugin dependency and name no plugin in requirements. `PluginLogic.validateManifest` and `requirementsError` refuse them. A NetworkManager VPN requirement names the service from its installed `.name` file; it need not hold a live bus name while idle.
- Declare requests to the core as manifest data, never Lua, code or command strings ([D011](../decisions/D011-native-manifest-no-cross-shell-compatibility.md)). `bin/lib/check-manifests.js` judges bundled manifests; review catches code inside string values.

### Core

- Name no plugin id in the core and import no plugin directory. `config/shell.json` names the default bar. `scripts/check-plugin-boundary.py` catches first-party id literals and plugin imports; review holds other ids.
- Add no kind for a widget drawn inside a plugin's existing surface. Register a built-in through capability `builtins`. Review holds this choice.
- Add a capability as a general core API, with a fixture consumer, before adding its product consumer. Review holds this order.
- Judge manifests only in `shell/Core/PluginLogic.js` ([D009](../decisions/D009-one-manifest-judge-under-node.md)). Add a refusal test with each manifest key. CLI and shell readers use the same judge; review catches a second validator.
- Keep the plugin manager's mechanism in core and its interface in a plugin using capability `manager` ([D032](../decisions/D032-settings-plugin-and-manifest-settings-convention.md)).
- Keep a disabled bundled plugin's startup migration independent of its service. Follow the vgs-plugin API's [startup migration contract](../../.agents/skills/vgs-plugin/references/api.md#startup-migrations), so disabling a plugin cannot leave a former service running.

### Hosts and capabilities

- Lend only declared capabilities through `Capabilities.providersFor`. Give each kind only what it reads, through `PluginLogic.instanceCapabilities`; an unnecessary hold keeps core work active. `PluginLogic.validateManifest` judges `capabilityKinds`, and `scripts/test-plugin-logic.js` checks it. The Hyprland layer publisher holds and releases its own `hyprland` capability for global keymap facts.
- Tell a service that the user disabled it only through optional `turnedOff()`. Reload, rescan and exit destroy it without that call. `scripts/smoke/rows/plugins.sh` checks this distinction.
- Return a disposer for every registration, or a hold whose `end` disposes it. `shell/Core/Lifetime.js` releases instance registrations; `scripts/test-lifetime.js` checks teardown.
- Hand text to another plugin only through `handoff`, never a named plugin call. `HandoffRegistry.qml` lends `offer(name, accept, reason)` and read-only `targets`: each descriptor has an opaque saved `key`, `label`, `kind` (`"action"` for a receiver whose entry declares it, else `""`), `available`, `reason` and `open(text)`, returning `{ ok, reason }`. A manifest's `handoffs` declares local names with labels. A null receiver withdraws the live offer and reports why; the returned disposer ends the report too. An old descriptor never reaches a replacement. A conversation receiver opens an editable draft. An action receiver, of kind `action`, opens its own plugin's draft or confirmation of the handed facts. Every receiver preserves an occupied draft and starts no turn. A plugin may name a fixed target when the user's action has exactly one meaningful receiver, and a receiver that opens its plugin's own draft rather than a conversation declares `"kind": "action"` in its `handoffs` entry ([D127](../decisions/D127-fixed-handoff-target.md)). `scripts/qml-tests/tst_handoff.qml` checks the general route with test-tree consumers.
- Keep session-wide objects core-owned and lend them through capabilities. `scripts/check-plugin-boundary.py` refuses lent types in plugins.
- Lend state without mutation authority through read-only capabilities ([D056](../decisions/D056-read-only-session-state.md), [D090](../decisions/D090-core-input-facts.md)). Review holds this API boundary.
- Keep each system section in its own `pane` plugin. One enabled window holds exclusive capability `panes` and mounts one pane at a time with that pane's own scoped `shell`. Never give it the holder's settings or authority. `scripts/smoke/rows/panes.sh` checks mounting.

## The canonical example

Copy `scripts/smoke/fixtures/plugins/acme.status/`: its service, widget and panel use their declared capabilities without importing the core or another plugin.

## Revisit when

A feature needs a surface no host can provide, a dependency cannot be carried through a capability, or measured process-per-plugin costs fit the resource budgets. Revisit pane ownership if two enabled windows must host the same pane set or a pane must outlive its holder.

## Not governed

A plugin's internal behavior belongs to its code and tests. Kind, capability and manifest contracts belong to the vgs-plugin [API reference](../../.agents/skills/vgs-plugin/references/api.md). Requirement execution belongs to [commands-are-data.md](commands-are-data.md); saved settings belong to [configuration.md](configuration.md).
