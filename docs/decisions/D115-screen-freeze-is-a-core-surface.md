# D115: The screen freeze is a core surface lent through `screencopy`

[← Decision Index](INDEX.md)

**Date**: 2026-11-01

**Status**: Active

**Research**: [VGS-2130](https://linear.app/vanillagreen/issue/VGS-2130)

**Refines**: [D012](D012-core-owns-lent-objects.md)

**Decision**: The still screen a selection tool maps above is drawn by the core: `shell.screencopy.freeze` captures one frame of every screen through Quickshell's `ScreencopyView` and draws it on a whole-output overlay surface of namespace `vgs:freeze`, which takes no input and maps with no animation; `thaw` and the holder's teardown end it. No external program freezes the screen.

**Why**: hyprpicker 0.4.7 reads the frame over wlr-screencopy, which carries no transform, and turns it by the output's own transform. Hyprland 0.57.0 sends every capture upright, so the frame on a rotated output was turned and stretched, and grim saved that frame as the picked region. `ScreencopyView` takes the frame's transform from ext-image-copy-capture and draws it upright on either Hyprland release. The frame is captured while its surface draws nothing, so it holds no freeze. A plugin creates no surface, so the core lends this one.

**Rejected**: A hyprpicker release that reads ext-image-copy-capture, which upstream had not published; the passive `layers` capability, whose surface stays clear of reserved space and whose lent preview is a live stream; a new kind for one service's selection.

**Revisit when**: A selection tool draws its own still frame correctly on every transform, or a second consumer needs a freeze on some screens only.
