# D088: System sections are pane plugins mounted by one panes holder

[← Decision Index](INDEX.md)

**Date**: 2026-10-01
**Status**: Active
**Research**: [VGS-691](https://linear.app/vanillagreen/issue/VGS-691)
**Refines**: [D005](D005-kinds-are-surfaces-no-dependencies.md), [D032](D032-settings-plugin-and-manifest-settings-convention.md), [D044](D044-application-windows-are-hyprland-toplevels.md)

**Decision**: A section is a plugin of kind `pane`. One enabled window plugin holds the exclusive `panes` capability, mounts one pane at a time, and hands it the pane plugin's own scoped `shell`, never the holder's.

**Why**: Each section also owns a bar widget, a flyout and a service, so it must stay its own plugin. A pane that received the holder's `shell` would get the wrong settings and capabilities. `scripts/smoke/rows/panes.sh` reads the mount back.

**Rejected**: One `vgs.system` plugin holding every section. No section could be enabled, updated or reviewed alone.

**Revisit when**: Two enabled windows must host the same pane set at once, or a pane must outlive its holder window.
