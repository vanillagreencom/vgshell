# D051: Every notification action reveals the sender's window, and an expired toast stays deliverable

[← Decision Index](INDEX.md)

**Date**: 2026-09-29
**Status**: Active
**Research**: [VGS-603](https://linear.app/vanillagreen/issue/VGS-603)

**Decision**: Every click, row and action pill except Dismiss delivers the action, then brings the sender's window into view through one core helper, `shell.compositor.reveal`, which waits a bounded time on Hyprland's events for the sender to raise itself. An expired toast stays tracked, so its inbox row still works.

**Why**: Quickshell 0.3.1's notification server emits no activation token, so a sender on Wayland cannot raise its own window after a click. The wait exists so a sender that does raise itself is not switched twice. `scripts/smoke/rows/compositor-reveal.sh` reads the reveal back.

**Rejected**: Raising the window only when the action fails. The action succeeds and still nothing comes forward without a token.

**Revisit when**: Quickshell emits an activation token, Hyprland's focus dispatcher stops showing special workspaces or group tabs, or a sender is measured raising itself later than the wait.
