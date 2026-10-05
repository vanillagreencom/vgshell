# D001: Hyprland is the only compositor

[← Decision Index](INDEX.md)

**Date**: 2026-09-21

**Status**: Active

**Research**: —

**Context**: Supporting a second compositor, such as Niri, doubles every compositor-facing path and every review, and its paths cannot be verified without its hardware.

**Decision**: VGS targets Hyprland alone. There is no compositor abstraction and no second compositor. `shell/Core/Compositor.qml` is the one dispatch path; `shell/Core/Dispatch.js` builds every request and speaks both Hyprland config dialects.

**Rationale**:

- One compositor halves the code paths that talk to the session and the review surface with them.
- A compositor path nobody can run on its hardware cannot be verified.

**Revisit When**: A second compositor gains a Wayland protocol set the shell needs and a maintainer with the hardware to validate it.

**Verification**: `scripts/qml-smoke.sh` runs the shell under nested Hyprland only.

**References**: `docs/architecture/overview.md`
