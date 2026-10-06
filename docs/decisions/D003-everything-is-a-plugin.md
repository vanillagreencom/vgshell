# D003: Everything outside the core is a plugin, and the plugin manager is core

[← Decision Index](INDEX.md)

**Date**: 2026-09-21
**Status**: Active
**Research**: —

**Decision**: Every surface and every service is a plugin. The core is only what must exist before any plugin runs and keep running when one breaks: the process, the instance lock, the compositor link, the theme tokens, the hosts, the registry, the plugin manager's mechanism and IPC. The core names no plugin; the manager's user interface is itself a plugin.

**Why**: A small privileged core fits in one agent's context and changes rarely, and a plugin change cannot reach another plugin, so the review scope of a change is the plugin. `scripts/check-plugin-boundary.py` refuses a plugin id or a plugin import in a core file.

**Rejected**: Features in the core. A change to one surface then breaks another, and the core outgrows what one agent can hold.

**Revisit when**: A feature needs a surface no host can give without a core rewrite, or the core grows past one agent's context.
