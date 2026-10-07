# Everything outside the core is a plugin

Read before structural work, before writing a plugin, a host or a capability provider, and before adding a kind, a capability or a manifest key.

## The approach

Every surface a user sees and every background service is a plugin: one directory under `shell/plugins/` or `~/.config/vgshell/plugins/`, with one `manifest.json`. The core is what has to exist before any plugin can run and keep running when one breaks.

A plugin reaches the core in two ways only. A host gives it a surface to draw inside, one per kind its manifest declares. The scoped `shell` object hands it the capabilities its manifest names, made for that instance and released with it. A manifest declares what the plugin fills and what it uses, never another plugin. A kind whose host is absent is not built, and the plugin's other kinds are.

The choices are [D003](../decisions/D003-everything-is-a-plugin.md), [D005](../decisions/D005-kinds-are-surfaces-no-dependencies.md), [D010](../decisions/D010-facade-scope-not-sandbox.md) and [D012](../decisions/D012-core-owns-lent-objects.md).

## Why

A core that holds features lets a change to one surface break another, and grows past what one agent holds in context. A small core changes rarely. A plugin change cannot reach another plugin, so the review scope of a change is the plugin.

A dependency between plugins brings a load order and refusals to explain. A plugin that depends only on hosts and capabilities keeps working when part of it has nowhere to draw.

The boundary is a static import check plus the scoped object, not a process sandbox ([D010](../decisions/D010-facade-scope-not-sandbox.md)).

## Rules

### Plugins

- Do put a new surface or service in a plugin, with its own directory and manifest. Review checks it.
- Never let a plugin import another plugin or a core file: a plugin imports only the allowed module prefixes, `qs.Commons` and `qs.Ui` among them, and its own files. `scripts/check-plugin-boundary.py` refuses the rest.
- Never create a surface, instantiate an object the core lends, or call `Hyprland.dispatch` in a plugin. `scripts/check-plugin-boundary.py` refuses each.
- Never declare a dependency on another plugin, and never name a plugin in `requirements`. `PluginLogic.validateManifest` refuses an unknown key, `requires` and a requirement spelt as a plugin id; `scripts/test-plugin-logic.js` pins each.
- Do declare everything a plugin asks of the core as data in its manifest, never code, Lua or a command string ([D011](../decisions/D011-native-manifest-no-cross-shell-compatibility.md)). `bin/lib/check-manifests.js` judges every bundled manifest; review catches code inside a string value.

### Core

- Never name a plugin id in the core, or import a plugin directory from a core file; `config/shell.json` names the default bar. `scripts/check-plugin-boundary.py` refuses a first-party `vgs.` id and a plugin import; review catches any other id.
- Never add a kind for a widget a plugin draws inside its own surface; register it as a built-in through capability `builtins`. Review checks it.
- Do add a capability as a general core API, with a fixture consumer under `scripts/smoke/fixtures/plugins/`, before the plugin that needs it. Review checks it.
- Do make every decision about a manifest in `shell/Core/PluginLogic.js`, the one judge, and add a manifest key there with its refusal row in `scripts/test-plugin-logic.js` ([D009](../decisions/D009-one-manifest-judge-under-node.md)). `bin/lib/check-manifests.js` and `vgshell plugin validate` load the same file; review catches a second validator.
- Do keep the plugin manager's mechanism in the core, because it must run before any plugin and keep running when one breaks; its user interface is a plugin that reaches it through capability `manager` ([D032](../decisions/D032-settings-plugin-and-manifest-settings-convention.md)). Review checks it.

### Hosts and capabilities

- Do hand a plugin only the capabilities its manifest names. `Capabilities.providersFor` builds one provider per named capability, and `scripts/smoke/rows/capabilities.sh` checks that a plugin that does not name one does not hold it.
- Do return a disposer from every registration a provider makes, so that disabling a plugin releases everything it held. `shell/Core/Lifetime.js` releases them with the instance; `scripts/test-lifetime.js` and `scripts/smoke/rows/capability-release.sh` pin it.
- Never let a plugin own a session-wide object; the core owns it and lends it through a capability. `scripts/check-plugin-boundary.py` refuses a lent type in a plugin.
- Never lend authority with a reading: a read-only capability exposes state without the power to change it ([D056](../decisions/D056-read-only-session-state.md), [D090](../decisions/D090-core-input-facts.md)). `scripts/smoke/rows/session.sh` and `scripts/test-input-facts.js` pin it.

## The canonical example

`scripts/smoke/fixtures/plugins/acme.status/`: a manifest that declares its kinds and the capabilities it uses, a service that publishes through capability `status`, a widget and a panel that read it through their own `shell`, and no import beyond `QtQuick` and `qs.Ui`. Copy it.

## Revisit when

A feature needs a surface no host can give without a core rewrite, a plugin cannot work without another plugin's service and no capability can carry it, or the resident-size budgets are measured against a process-per-plugin design and it fits.

## Not governed

What a plugin does inside its surface, which is its own tests and README. Each kind, capability member and manifest key, which is the vgs-plugin skill's [`references/api.md`](../../.agents/skills/vgs-plugin/references/api.md). Requirements and the requirement notice, which are [commands-are-data.md](commands-are-data.md) and `PluginLogic.noticeRequest`. The configuration files, which are [configuration.md](configuration.md).
