# D101: The login screen is a core greeter host over greetd

[← Decision Index](INDEX.md)

**Date**: 2026-10-04
**Status**: Active
**Research**: [VGS-756](https://linear.app/vanillagreen/issue/VGS-756)
**Refines**: [D003](D003-everything-is-a-plugin.md), [D061](D061-no-manual-commands.md), [D081](D081-system-steps-closed-core-table.md)

**Decision**: greetd runs Hyprland with a static VGS configuration, and Hyprland runs a second Quickshell root, `shell/greeter.qml`, which loads one plugin view from inside the installed plugin tree only. One row of D081's table writes VGS-owned greetd, PAM and drop-in files, enables greetd without starting it, and undoes only what it recorded.

**Why**: The greeter runs where every account's password is typed, so it may run only files root alone can change, which rules out a checkout, a per-user install or a plugin-built window. Starting greetd inside a running session takes the console from it, and editing greetd's own files would leave `undo` unable to tell VGS's lines from the distribution's. `scripts/test-greeter-compositor.sh` and `scripts/smoke/rows/greeter.sh` hold the host.

**Rejected**: A display-manager theme such as an SDDM theme. It cannot load `qs.Ui` or `Theme`, so boot would carry a second design system.

**Revisit when**: greetd can run a greeter without a compositor Quickshell supports, Quickshell resolves modules outside its config root, a distribution names the greeter account otherwise, or VGS ships a package that can own the greetd configuration.
