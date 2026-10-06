# shell/

The Quickshell shell root. `shell.qml`, `greeter.qml` (the login screen's host, [D101](../docs/decisions/D101-greeter-host-and-greeter-system-step.md)), `Core/`, `Hosts/`, `Commons/` and `Ui/` are the core; `plugins/` holds first-party plugins and has its own `AGENTS.md`.

- The core names no plugin and imports no plugin directory. `scripts/check-plugin-boundary.py` enforces it.
- What a host and a capability provider may do, and what each hands a plugin: `docs/architecture/overview.md` § Hosts and surfaces and § Capabilities; each member a plugin receives: `.agents/skills/vgs-plugin/references/api.md`.
- Every Hyprland dispatch the code relies on: `docs/architecture/hyprland.md` § Dispatch. Read it before editing `Core/Compositor.qml` or `Core/Dispatch.js`.
- Every Quickshell or Qt fact the code relies on is checked against the Quickshell 0.3.1 reference or a run, never memory, and stated in a short comment at the code that rests on it. Read that comment before editing the code, such as a handler that reads a property a binding also reads.
