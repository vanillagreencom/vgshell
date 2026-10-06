# D062: A native lock plugin on the core's session lock, and a native polkit agent

[← Decision Index](INDEX.md)

**Date**: 2026-09-30
**Status**: Active
**Research**: [VGS-611](https://linear.app/vanillagreen/issue/VGS-611)

**Decision**: `vgs.lock` is a service on the core's `lock` capability, with its PAM stack in the plugin, an idle watch and a sleep hook, and `vgs.polkit` is a native agent. The core gains an `idle` capability, and the Hyprland layer sets `misc.allow_session_lock_restore`.

**Why**: The session fails closed when the plugin or the shell dies, and the restore option lets a relaunched shell take over a stranded lock. Without it a crashed lock screen leaves Hyprland's dead-lock screen that only a TTY clears. `scripts/smoke/rows/lock.sh` and `polkit.sh` read both back.

**Rejected**: Keeping `hyprlock` and `hyprpolkitagent`. Neither reads the tokens.

**Revisit when**: Quickshell keeps a lock across a reload, a lock needs a fingerprint, or Hyprland tells a replaced lock client it was replaced.
