---
name: vgs-plugin
description: "Load to create, change or review a VGS shell plugin: a bar widget, a bar, a panel, an overlay, a menu, a window, a pane, a service or a background."
summary: "The plugin contract as a checklist, a scaffold command, templates for every kind, and the API a plugin may use."
license: MIT
user-invocable: true
argument-hint: "new <author.name> --kinds <kind,...> | check <dir>"
metadata:
  author: vanillagreen
  source: in-place
  repository: "https://github.com/vanillagreencom/vgshell"
  bugs: "https://github.com/vanillagreencom/vgshell/issues"
  version: "0.5.0"
tags: [plugins, quickshell]
---

<!-- kendex:project-instructions:start -->
## Project Instructions

<!-- kendex:shared-instructions:start -->
Problems with a kendex-owned skill go through `kendex report`; check ownership in the file first.

VGS delivery policy overrides the shared workflow's mandatory review, CI-wait, branch-size and commit-hook gates. Work targets main. PRs are optional; push directly or merge a PR immediately with gh, with no queue or CI wait. Review goes by risk: a change to code where a defect shows as a performance, stability, race, leak or lifetime problem (services, Quickshell or Hyprland IPC, processes and timers, file or socket watchers, object ownership and destruction, caches, concurrency, the plugin scan and publish path, the sandbox and smoke harness) runs one internal review round, the orch review panel, before the push; a change that is only layout, copy, styling, tokens, docs or a settings field runs none. The done line names which applied and why. Do not arm git guards. Run scripts/validate once on the final relevant diff; use --changed <last-validated-commit> for a fix round, and reuse passing results while those inputs are unchanged. Do not rerun a full battery at commit, push or submission. Use --full only for an explicit full sweep or an unmapped dependency. Keep the live-session safety rules.

<!-- kendex:shared-instructions:end -->
<!-- kendex:project-instructions:end -->

# vgs-plugin

Write a plugin for the VGS shell. The contract is [`docs/architecture/overview.md`](../../../docs/architecture/overview.md); this skill holds the steps, the scaffold command and the templates.

```bash
.agents/skills/vgs-plugin/scripts/vgs-plugin new acme.weather --kinds bar-widget,service
.agents/skills/vgs-plugin/scripts/vgs-plugin check shell/plugins/acme.weather
```

## Rules

- Consumer text follows [`docs/architecture/design-system.md` § Copy](../../../docs/architecture/design-system.md#copy).

- One directory, one `manifest.json` at its root, one QML entry point per kind. Copy the templates. The field table is [`references/api.md` § Manifest](references/api.md#manifest); an unknown key is refused.
- Declare surfaces, never dependencies. Every external command the plugin runs and every D-Bus service it reaches goes in the manifest's `requirements`, with its package per manager, `optional` when the plugin works without it, and a one-line `purpose`; a requirement names a command or a D-Bus name, never another plugin: [`docs/architecture/overview.md` § Requirements](../../../docs/architecture/overview.md#requirements). The core shows its notice when the plugin is installed or enabled without a requirement it needs; a button that asks the user to install one of the plugin's own requirements calls `shell.requirements.offer`, never a package manager.
- Imports and names: the allowed table in [`references/api.md`](references/api.md) § Allowed imports, and nothing else. `scripts/check-plugin-boundary.py` refuses the rest.
- Every entry point declares `property var shell: null` or inherits it from `BarWidget`. Capabilities come from `shell.<name>` after naming them in `capabilities`; a widget never reads them from `bar`.
- Settings default in the manifest's `settings` and arrive as `shell.settings` for every kind; a bar widget also reads them with `setting(name, fallback)`. A change reaches the running instance as a new `shell`; hold no copy.
- The manifest is the plugin's settings page: name an `icon` from the shipped Lucide set, and give every setting a user would reasonably change, and the plugin reads, a `schema` entry, with `min`, `max`, `step` and `unit` on a number, `presets` on a format-like value, `allowCustom` only when custom values are useful, and a `group` for its section; a string without `presets` or `optionsFrom` is refused. A constant earns an entry only when a user has a reason to change it. A key is `hyprland.binds`, never a schema entry; the Settings page's Keys row captures a pressed combo for it with `ShortcutField`. The Settings window draws the page from these alone: [`references/api.md` § Manifest](references/api.md#manifest), [D032](../../../docs/decisions/D032-settings-plugin-and-manifest-settings-convention.md), [D077](../../../docs/decisions/D077-settings-schema-presets-and-row-rhythm.md).
- A bar widget extends `BarWidget` from `qs.Ui` and sizes itself with `implicitWidth` and `implicitHeight`. The core assigns `bar`, `moduleName`, `settings` and `frame` after creation; the widget sets none of them. `BarWidget` gives every widget its right-click Hide; a widget takes no right click of its own.
- A bar declares `leftSection`, `centerSection` and `rightSection`. The core mounts every plugin widget; a widget the bar draws itself registers through `shell.builtins`.
- A surface the user works in, moves or tiles, such as a settings or tools window, is kind `window`, a Hyprland window; a section inside a System-style holder is kind `pane` and starts from `templates/Pane.qml`; a flyout from a widget is an anchored `panel` or `menu`, which closes on a click outside it: [`docs/architecture/overview.md` § Hosts and surfaces](../../../docs/architecture/overview.md#hosts-and-surfaces), [D044](../../../docs/decisions/D044-application-windows-are-hyprland-toplevels.md).
- Compose the components of `qs.Ui` ([`references/api.md` § Components in `qs.Ui`](references/api.md#components-in-qsui)) before drawing anything by hand. Every colour, size, font, radius, opacity and duration reads a token through `Theme` in `qs.Commons`. `scripts/check-design-tokens.py` refuses a `Theme` path that names no token and reports each literal it finds.
- Keyboard support is first class: follow [`docs/architecture/design-system.md` § Keyboard](../../../docs/architecture/design-system.md#keyboard) for each pointer action and focusable control.
- Before choosing a default key, check common Hyprland bindings and avoid Super with H/J/K/L, W/A/S/D or a digit.
- A list whose rows each take one selection declares one `ListCursor` from `qs.Ui` and names it in each row's `cursor`; keys write the list's one selection, a hover moves the plate and, in a pick list, the selection, and no row draws its own hover or highlight fill: [`docs/architecture/design-system.md` § Motion](../../../docs/architecture/design-system.md#motion).
- A plugin whose design must look the same under every theme owns its look instead: the manifest's `appearance` names a table of its own, every value is `look.<path>` from `Theme.appearance(TOKENS, LIGHT)`, and the theme reaches it through its mode, accent and motion scale alone. [`docs/architecture/design-system.md` § Appearance](../../../docs/architecture/design-system.md#appearance) is the contract; it reads no other `Theme` member.
- One owner per timer, watcher, poller and subprocess, inside the entry point's tree. A `Process` gets its stdout parser before it starts.
- A value the plugin's widgets, flyout or Settings page show is plugin status: declare it in the manifest's `status`, name capability `status`, write it from the one instance that owns its source, the service, with `shell.status.set`, and read it from `shell.status.values`. One writer per key; a credential's value never enters status, only its presence. [`docs/architecture/overview.md` § Status](../../../docs/architecture/overview.md#status), [D037](../../../docs/decisions/D037-plugin-status.md).
- A plugin that needs a Hyprland key, a blur rule, an input option or a display rule declares it as data in the manifest's `hyprland` key and never writes Hyprland configuration: the core renders it into the one Hyprland layer, [`docs/architecture/hyprland.md`](../../../docs/architecture/hyprland.md). An input option maps a schema setting through `hyprland.options` and reads Hyprland back through capability `hyprland`, never its own `hyprctl`: [hyprland.md](../../../docs/architecture/hyprland.md). Only one enabled plugin may own `hyprland.monitors`; other plugins read outputs through capability `monitors` and do not set monitor rules.
- No manual commands ([D061](../../../docs/decisions/D061-no-manual-commands.md)): a setup step is automatic or one click. Give the status entry that shows it an `action`, the plugin's own TUI, its own requirement commands or a step of the core's root setup table it declares in `systemSteps` ([commands-are-data.md § System steps](../../../docs/architecture/commands-are-data.md#system-steps)), and publish when it applies; a credential is a `presenceList` item naming its account of the manifest's `secrets`, which the Settings page connects through a masked field. A command a user could run shows only as the entry's `command`, behind Show command, never in a README step, a hint or a notice: [commands-are-data.md](../../../docs/architecture/commands-are-data.md). `vgs-plugin check` runs `scripts/check-user-commands.py`.
- Consumer features need no developer setup ([D075](../../../docs/decisions/D075-consumer-features-need-no-developer-setup.md)). A feature that needs an app, API key or token the user must create is an owner-only extra: a setting off by default with no `schema` entry, named in the manifest's `extras` with the status entries and optional requirements only it uses, which the core hides while it is off, and documented under "Extras (not supported)" in the README: [`references/api.md` § Manifest](references/api.md#manifest).
- A command the user must see or answer runs in a floating TUI: a script under the plugin's `tui/`, declared as data in the manifest's `tui` key and opened with `shell.tui.run`, never a command string: [`docs/architecture/commands-are-data.md` § Commands as data](../../../docs/architecture/commands-are-data.md#commands-as-data).
- No cache keyed by data other applications supply without a ceiling.
- Every Quickshell type, property and signal comes from the 0.3.1 reference on Context7: `ctx7 docs /websites/quickshell_v0_3_1 <query>`.
- A first-party plugin's README shows a screenshot made by `scripts/readme-shots.sh`, with its row in `docs/images/plugins/shots.tsv`: [DEVELOPMENT.md § Regenerate](../../../DEVELOPMENT.md#regenerate).
- Land with `scripts/validate manifests`, `scripts/validate boundary` and `scripts/validate qml` clean, the last with the readback rows [`workflows/new-plugin.md`](workflows/new-plugin.md) step 9 names.

## Workflows

| Workflow | Trigger |
|----------|---------|
| [`workflows/new-plugin.md`](workflows/new-plugin.md) | Creating a plugin from nothing |
| [`workflows/review-plugin.md`](workflows/review-plugin.md) | Reviewing or changing an existing plugin |

## References

- [`references/api.md`](references/api.md): what a plugin receives and may call, per kind.
- [`templates/`](templates/): `manifest.json.tmpl`, `BarWidget.qml`, `Service.qml`, `Panel.qml`, `Window.qml`, `Pane.qml`, `Bar.qml`, `Background.qml`, `tui.sh`.
