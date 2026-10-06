# Everything outside the core is a plugin

Read before structural work: adding a surface, a service, a kind, a capability or a core module.

## The approach

VGS is a Quickshell shell for Hyprland. The core is what has to exist before any plugin can run and keep running when one breaks: the runner and its instance lock, the Hyprland connection and its reply judge, the design tokens, the surface hosts, the plugin registry, the plugin manager's mechanism and IPC. Everything a user sees or a service does is a plugin: one directory with one `manifest.json`, one QML entry point per kind, shown on each surface whose host exists, handed one scoped `shell` object with exactly the capabilities its manifest names. Plugins declare no dependency on one another; a kind is one of the closed list the core owns; a widget a plugin draws inside its own surface is a built-in of that plugin, never a kind; a section of the System Settings window is a `pane` mounted by the one `panes` holder. The core names no plugin; `config/shell.json` names the default bar. The choices are [D003](../decisions/D003-everything-is-a-plugin.md), [D005](../decisions/D005-kinds-are-surfaces-no-dependencies.md), [D010](../decisions/D010-facade-scope-not-sandbox.md) and [D088](../decisions/D088-system-panes.md).

## Why

A core that holds features lets a change to one surface break another and grows past what one agent holds in context. A small privileged core changes rarely, and a plugin change cannot reach another plugin, so the review scope of a change is the plugin. The boundary is a static import check plus the scoped object, not a process sandbox: a process per plugin would multiply the resident size before any plugin justified it, and the remaining risk is stated rather than pretended away.

## Vocabulary

- Core: the runner, the lock, the Hyprland connection, the design system, the hosts, the registry, the manager and IPC. `scripts/check-plugin-boundary.py` draws the line.
- Kind: `bar-widget`, `bar`, `panel`, `overlay`, `menu`, `window`, `pane`, `service` or `background`; `PluginLogic.KINDS` is the list. A `window` is a Hyprland window; every other surface is a transient overlay.
- Host: a core-owned Wayland surface a plugin draws inside. A plugin creates no surface of its own.
- Capability: a core API a plugin names in its manifest and receives on its `shell` object at load, made for one instance and released with it.
- Requirement: an external command a plugin or the core runs, declared with its package per manager; it names a command, never a plugin.
- Token: one named value the shell draws with, from `shell/Commons/Tokens.js`; a theme is a document that overrides tokens.
- Validation row: an assertion under `scripts/smoke/rows/` that a plugin is built, shown and handed what it asked for, read back from the instance.

## Rules

- Do put a new surface or service in a plugin, with its own directory, manifest and validation row in the same change.
- Never name a plugin id in the core, let one plugin import another, or import a plugin's file from a core file. `scripts/check-plugin-boundary.py` refuses each, planted by `scripts/test-check-plugin-boundary.py`.
- Do import in a plugin only the module prefixes the boundary check allows and the plugin's own files; never instantiate a window type or a lent object. The same check refuses it.
- Do make every decision about a manifest, the configuration, enablement, placement and the TUIs a plugin may open once, in `shell/Core/PluginLogic.js`; `scripts/test-plugin-logic.js` and `bin/lib/check-manifests.js` load the same file ([D009](../decisions/D009-one-manifest-judge-under-node.md)).
- Do land a new core capability first, with its validation row, then the plugin that uses it.
- Never let the plugin manager run plugin code or ask for a privilege; the install rows of `scripts/test-vgshell.sh` run every git call with hooks off.
- Do declare `shown` on a bar or background that has nothing to draw; a hidden surface reserves no space. The disable rows of `scripts/smoke/rows/bar.sh` read the reserved geometry.
- Do draw a pane as a body alone from x 0 with no `Pane` and no title; the holder owns the chrome. `scripts/smoke/rows/system-window.sh` plants a holder that hands no height.
- Do run `vgshell restart` after a core file changes; a first build after that is refused `restart=owed`. `scripts/smoke/rows/core-drift.sh` pins it.
- Never start a second shell against the live session, and never kill Quickshell processes by name; validation runs in the nested sandbox alone.
- Do name the tool and the run that produced every figure a document or comment states.

## The canonical example

`scripts/smoke/fixtures/plugins/acme.status/`: a manifest that declares its kinds and the capabilities it needs, a service that publishes through one of them, and nothing of the core. Copy it.

## Revisit when

A feature needs a surface no host can give without a core rewrite, a plugin cannot work without another plugin's service and no capability can carry it, or the budgets are measured against a process-per-plugin design and it fits.

## Not governed

What a plugin does inside its surface, which is its own tests and README; the manifest's keys, which is [plugin-manifest.md](plugin-manifest.md); the capabilities themselves, which is [capabilities.md](capabilities.md); the surface classes, which is [surfaces.md](surfaces.md).
