# D005: Kinds are a closed list of surfaces, and plugins declare no dependencies

[← Decision Index](INDEX.md)

**Date**: 2026-09-21
**Status**: Active
**Research**: —

**Decision**: A plugin fills kinds from the closed list the core owns, and declares no dependency on another plugin: a kind with no host is not shown, and an unknown manifest key such as a dependency list is refused. A widget a plugin draws inside its own surface, such as the bar's clock, is a built-in registered through the `builtins` capability and recorded under that plugin with origin `plugin`; it is never a kind value.

**Why**: One closed list keeps every switch on `kind` exhaustive, and the core owns placement and lifecycle. No dependency graph means no load order, no refusal to explain and no plugin that names another; a plugin keeps working when part of it has nowhere to draw. `scripts/test-plugin-logic.js` pins the refusals.

**Rejected**: A `requires` list by plugin id with the manager refusing to disable a required plugin, and a `kind` value of its own for built-ins. The first brings an order and refusals; the second puts a word outside the closed list into the field every host switches on.

**Revisit when**: A plugin cannot work without another plugin's service and no core capability can carry that contract, or a built-in needs its own settings or enablement.
