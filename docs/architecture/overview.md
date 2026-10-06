# Everything outside the core is a plugin

Read before structural work, before writing a plugin or a host, and before touching a kind, a capability, a requirement, a manifest key, enablement, placement, plugin status or the plugin manager.

## The approach

VGS is a Quickshell shell for Hyprland. The core is what has to exist before any plugin can run and keep running when one breaks: the runner and its instance lock, the Hyprland connection and its reply judge, the design tokens, the surface hosts, the plugin registry, the plugin manager's mechanism and IPC; `scripts/check-plugin-boundary.py` draws the line. Everything a user sees or a service does is a plugin: one directory with one `manifest.json`, one QML entry point per kind, shown on each surface whose host exists, handed one scoped `shell` object with exactly the capabilities its manifest names, and landed with a validation row under `scripts/smoke/rows/` that reads back that it is built, shown and handed what it asked for. The core names no plugin; `config/shell.json` names the default bar. The choices are [D003](../decisions/D003-everything-is-a-plugin.md), [D005](../decisions/D005-kinds-are-surfaces-no-dependencies.md), [D010](../decisions/D010-facade-scope-not-sandbox.md) and [D088](../decisions/D088-system-panes.md).

A plugin declares what it fills and what it uses, never whom it needs. A kind is an entry point the core can host, from the closed list `PluginLogic.KINDS`; a kind whose host is absent is not built, and the plugin's other kinds are. A host is a core-owned Wayland surface a plugin draws inside. A capability is a core API the manifest names, made for one instance and released with it. A requirement is an external command or D-Bus name a plugin or the core uses, declared with its package per manager. Nothing in a manifest names another plugin, so there is no load order and no refusal to explain.

The core decides everything about a plugin in one place and holds each shared thing once: one manifest judge, one owner per session-wide object, one status record per plugin, the runtime values a plugin publishes for its own instances and its Settings page. The plugin manager is core mechanism with a plugin for its user interface; it installs, enables and places plugins, and runs none of their code. Placement, whether a bar widget sits in a bar section, is the manager's second axis beside enablement. A token is one named value the shell draws with, from `shell/Commons/Tokens.js`; a theme is a document that overrides tokens.

## Why

A core that holds features lets a change to one surface break another and grows past what one agent holds in context. A small privileged core changes rarely, and a plugin change cannot reach another plugin, so the review scope of a change is the plugin. The boundary is a static import check plus the scoped object, not a process sandbox: a process per plugin would multiply the resident size before any plugin justified it, and the remaining risk is stated rather than pretended away.

A dependency graph brings a load order and refusals; a requirement is a fact about the system, so a plugin keeps working when part of it has nowhere to draw. One owner per session-wide object removes the collision class, and one lifetime per instance makes disabling a plugin a complete release. One manifest judge has no second format to drift from, and a key it refuses fails loudly where a carried-and-ignored key hides a typo until a user reports the missing feature. Running a repository's code at install hands it the user's privileges, so the manager's question is the review step before new plugin code runs. Placement apart from enablement lets a plugin's service outlive its widget. Two writers of one value give two answers.

## Rules

### Plugins and kinds

- Do put a new surface or service in a plugin, with its own directory, manifest and validation row in the same change.
- Never name a plugin id in the core, let one plugin import another, or import a plugin's file from a core file. `scripts/check-plugin-boundary.py` refuses each, planted by `scripts/test-check-plugin-boundary.py`.
- Do import in a plugin only the module prefixes the boundary check allows and the plugin's own files; never instantiate a window type or a lent object, and never call `Hyprland.dispatch`. The same check refuses each.
- Never declare a dependency on another plugin; a dependency key is refused as unknown ([D005](../decisions/D005-kinds-are-surfaces-no-dependencies.md)). `scripts/test-plugin-logic.js` pins the refusals.
- Never add a kind for a widget a plugin draws inside its own surface; it is a built-in of that plugin, registered through capability `builtins`. A section of the System Settings window is a `pane`, mounted by the one `panes` holder.
- Do declare `shown` on a bar or background that has nothing to draw; a hidden surface reserves no space. The disable rows of `scripts/smoke/rows/bar.sh` read the reserved geometry.
- Do draw a pane as a body alone from x 0 with no `Pane` and no title; the holder owns the chrome. `scripts/smoke/rows/system-window.sh` plants a holder that hands no height.
- Do run `vgshell restart` after a core file changes; a first build after that is refused `restart=owed`. `scripts/smoke/rows/core-drift.sh` pins it.
- Never start a second shell against the live session, and never kill Quickshell processes by name; validation runs in the nested sandbox alone.

### Hosts and surfaces

- Never create a surface in a plugin; a plugin draws inside the surface a host gives it, and the boundary check refuses every window type.
- Do pick the surface class through the kind. A surface the user works in, moves or tiles is kind `window`, a Hyprland window, which Hyprland borders, focuses, moves, tiles and closes ([D044](../decisions/D044-application-windows-are-hyprland-toplevels.md)). Every other summoned surface is a transient overlay: it never tiles, moves or floats, and an anchored one closes on a click outside it ([D018](../decisions/D018-overlays-are-quickshell-popups.md)). Content that sits over every window and never takes the keyboard goes on the passive layer of capability `layers`. `PluginLogic.summonSurface` decides the class; `scripts/smoke/rows/surfaces.sh` and `scripts/smoke/rows/windows.sh` read each back.
- Do leave an Escape the plugin does not use unaccepted, so the host closes the surface; accept it only for a step of the plugin's own. `scripts/smoke/rows/surfaces.sh` pins it.

### Capabilities

- Do return a disposer from every registration a provider makes, and keep each resource owner's state, registration and release together; `shell/Core/Lifetime.js` releases them all with the instance and goes on after one throws. `scripts/test-lifetime.js` pins the lifetime, and `scripts/smoke/rows/capability-release.sh` reads the lending record back after a disable.
- Do land a new core capability first, with its name, its provider, a fixture consumer and its validation rows, then the plugin that uses it.
- Never own a session-wide object in a plugin: the core owns the session lock, the polkit agent, the notification server and the Bluetooth agent and lends each ([D012](../decisions/D012-core-owns-lent-objects.md)), and keeps the session locked while the lock plugin is disabled, updated or rebuilt. `scripts/smoke/rows/lock.sh` and `scripts/smoke/rows/polkit.sh` read it.
- Do treat the capabilities `PluginLogic.EXCLUSIVE_CAPABILITIES` lists as exclusive: the first holder wins, and a second plugin naming one builds once the holder lets go. `PluginLogic.lendRefusal` decides, and at start every surface plugin builds before any service ([D047](../decisions/D047-services-build-after-the-first-bar-frame.md)). `scripts/test-plugin-logic.js` and `scripts/smoke/rows/start-order.sh` pin it.
- Never lend authority with a reading: the shared `session` capability exposes lock state without unlock authority ([D056](../decisions/D056-read-only-session-state.md)), and an input observation is a read-only snapshot that a failed read clears, that refuses an unrecognised or ambiguous target, and that a consumer reads again immediately before it acts ([D090](../decisions/D090-core-input-facts.md)). `scripts/test-input-facts.js` pins both.
- Never add a dispatcher to the compositor provider; add it to `Dispatch.PLUGIN_DISPATCHERS`. `scripts/test-dispatch.js` pins the list.
- Never let `configure` write a key the manifest's `schema` does not declare, and let it write every entry a pane or service plugin reads. `scripts/test-plugin-logic.js` pins both.
- Never let a notice a plugin offers release with the instance; the user closes it.

### Requirements

- Do declare every external command a plugin runs and every D-Bus name it reaches in the manifest's `requirements`, and never name a plugin there; `requires` and a dotted command, which reads as a plugin id, are refused ([D035](../decisions/D035-manifest-requirements.md)). `scripts/test-plugin-logic.js` pins both.
- Do keep `config/requirements.json` to core commands; each plugin owns its own, and a requirement only an extra uses sits under that extra's entry ([D075](../decisions/D075-consumer-features-need-no-developer-setup.md)). `scripts/test-plugin-logic.js` and `scripts/test-plugin-extras.js` pin it.
- Never install or elevate without the user: an install is a `vgshell pkg run` in a terminal the user watches, and the package manager never takes `--noconfirm`. `scripts/test-vgshell-requirements.sh` and `scripts/test-vgshell-pkg-table.js` pin both.
- Do ask a running shell to rescan after every package change, however it ends. `scripts/test-vgshell-requirements.sh` pins it.
- Do raise a requirement notice only for requirements its owner declares, never for optional requirements alone; rest a plugin's own offers after Not now, and never rest the user's own triggers. `scripts/test-notice-logic.js` pins each.

### Manifest

- Do make every decision about a manifest, the configuration, enablement, placement and the TUIs a plugin may open once, in `shell/Core/PluginLogic.js`, the one judge; a second validator is a twin. `scripts/test-plugin-logic.js`, `bin/lib/check-manifests.js` and `vgshell plugin validate` load the same file under node ([D009](../decisions/D009-one-manifest-judge-under-node.md)).
- Never add a manifest key without adding it to the judge and a refusal row to `scripts/test-plugin-logic.js`; a key the judge does not list refuses the manifest. `bin/lib/check-manifests.js` validates every bundled manifest offline.
- Never carry page code, Lua or a command string in a manifest; every key is data the core renders, in VGS's own schema ([D011](../decisions/D011-native-manifest-no-cross-shell-compatibility.md)).
- Do write a plugin from the vgs-plugin skill: its `references/api.md` § Manifest gives each key's meaning, and `PluginLogic.js` states each rule the judge applies.

### Status

- Do keep one writer per plugin status record: the core holds one record per plugin, the instance that owns the source, the service, writes it, and every other instance and the Settings page read it ([D037](../decisions/D037-plugin-status.md)). `scripts/smoke/rows/status.sh` reads one record from every instance; review catches a second writer of one key.
- Never let a credential's value enter status; its presence does, from a probe that does not read it.
- Do leave the status schema to its code owners: `PluginLogic.js` judges declarations and writes, and `shell/Core/PluginStatus.qml` holds the record. `scripts/test-plugin-status.js` pins each rule.

### Manager

- Never let the plugin manager run plugin code, a git hook or a privileged step: an install clones, judges the manifest and moves the directory into place, and the manager asks every question on a terminal the user sees before new plugin code runs ([D007](../decisions/D007-install-runs-no-plugin-code.md)). The install rows of `scripts/test-vgshell.sh` run every git call with hooks off, and `scripts/test-vgshell-prompts.sh` asks each question on a terminal.
- Do keep the manager's mechanism in the core, because it must run before any plugin and keep running when one breaks; its user interface is a plugin that reaches it through capability `manager` ([D032](../decisions/D032-settings-plugin-and-manifest-settings-convention.md)). The operation sequences live in `shell/Core/Plugins.qml`, `bin/vgshell` and `bin/vgshell-plugin-judge`.

### Placement

- Do keep placement independent of enablement: a placement edit never writes `disabledPlugins`, and placing or unplacing a widget never builds or destroys the plugin's other kinds, so its service outlives its widget and its settings outlive its layout entry. `PluginLogic.withPlaced` decides the edit; `scripts/test-plugin-logic.js` and `scripts/smoke/rows/placement.sh` pin it.

### Figures

- Do name the tool and the run that produced every figure a document or comment states.

## The canonical example

`scripts/smoke/fixtures/plugins/acme.status/`: a manifest that declares its kinds and the capabilities it needs, a service that publishes through one of them, and nothing of the core. Copy it.

## Revisit when

A feature needs a surface no host can give without a core rewrite, a plugin cannot work without another plugin's service and no capability can carry it, a plugin needs a lent object two plugins share at once, a requirement is neither a command on PATH nor a D-Bus name, or the budgets are measured against a process-per-plugin design and it fits.

## Not governed

What a plugin does inside its surface, which is its own tests and README; each capability's members and each manifest key's meaning, which is the vgs-plugin skill's [`references/api.md`](../../.agents/skills/vgs-plugin/references/api.md); the package-manager table an install runs through, which is [commands-are-data.md](commands-are-data.md); the configuration files, which is [configuration.md](configuration.md).
