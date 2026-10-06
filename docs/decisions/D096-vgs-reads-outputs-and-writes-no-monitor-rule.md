# D096: VGS reads outputs and writes no monitor rule

[← Decision Index](INDEX.md)

**Date**: 2026-10-02
**Status**: Active
**Research**: [VGS-744](https://linear.app/vanillagreen/issue/VGS-744), [VGS-707](https://linear.app/vanillagreen/issue/VGS-707)
**Refines**: [D028](D028-one-generated-hyprland-layer.md)
**Supersedes**: the monitor half of [D080](D080-hyprland-options-rendered-from-data.md)

**Decision**: Monitor settings belong to the user's own Hyprland configuration. VGS reads the outputs Hyprland lists through a shared `monitors` capability and holds no rule document, no judge, no layer section, no preview and no guard.

**Why**: A user already sets outputs in `hyprland.lua`, where a later line wins, so a second source gives two owners of one fact. A wrong mode can blank every screen, which the removed writer needed a preview, a record, a detached guard and a lock to recover from. The `runtime_writes_no_monitor_rule` row of `scripts/validate` refuses a shipped writer.

**Rejected**: Keeping the writer for a later Displays page. No caller exists, and unused code that can blank a screen is a cost with no user.

**Revisit when**: The owner asks for a Displays page that changes an output, or Hyprland gains an interface that sets a rule and reports which rule set each field.
