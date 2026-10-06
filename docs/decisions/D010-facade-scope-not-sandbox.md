# D010: The plugin boundary is a static check plus a scoped API object, not a process sandbox

[← Decision Index](INDEX.md)

**Date**: 2026-09-21
**Status**: Active
**Research**: —

**Decision**: A plugin may import only the allowed module prefixes and its own files, names no window type, and receives a scoped `shell` object. Process, scene graph and privileges stay shared, and no sensitive state relies on the scope alone.

**Why**: A process per plugin multiplies the resident size the runtime budgets bound before any plugin justifies it. A static check plus a scoped object catches accidental coupling, and the remaining risk is stated rather than pretended away. `scripts/check-plugin-boundary.py` is the check; `scripts/test-check-plugin-boundary.py` plants one violation per rule.

**Rejected**: A process or QML engine per plugin. Quickshell's own guidance puts a process per widget at a significantly higher memory cost.

**Revisit when**: The budgets are measured against a process-per-plugin design and it fits, or a plugin needs credentials the scope cannot protect.
