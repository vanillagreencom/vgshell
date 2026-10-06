# D001: Hyprland is the only compositor

[← Decision Index](INDEX.md)

**Date**: 2026-09-21
**Status**: Active
**Research**: —

**Decision**: VGS runs on Hyprland alone. There is no compositor abstraction and no second compositor target; `shell/Core/Compositor.qml` is the one dispatch path.

**Why**: A second compositor doubles every dispatch path and every review, and a path nobody can run on their own hardware cannot be verified.

**Rejected**: A compositor abstraction with a second target such as Niri. It doubles the code for a path no maintainer could validate.

**Revisit when**: A second compositor gains the Wayland protocol set the shell needs and a maintainer with the hardware to validate it.
