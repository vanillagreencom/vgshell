# D118: The screen freeze also writes its held frame for the holder

[← Decision Index](INDEX.md)

**Date**: 2026-11-03

**Status**: Superseded by D122

**Research**: [VGS-2232](https://linear.app/vanillagreen/issue/VGS-2232)

**Refines**: [D115](D115-screen-freeze-is-a-core-surface.md), adding the held frame as files beside the drawn freeze

**Decision**: The former `still` option exported every held output as PPM bands at its own scale and each greater layout scale, in a core-owned per-hold directory removed on thaw. A separate hidden view supplied cursor pixels. The worker cropped selected screenshots and text from those files. [D122](D122-freeze-crops-only-the-selection.md) replaces this contract in full.

**Why**: The prior whole-layout grim duplicated the freeze's capture and took 212 ms of 453 ms to the selector in the [VGS-2232 round-2 trace](https://linear.app/vanillagreen/issue/VGS-2232#comment-e0675c7d), in the nested sandbox at the owner's geometry and a 5-minute load of 11.6 to 13.8. The band choice bounded each GUI-thread save after a whole-frame save took 29-43 ms (nested sandbox, NVIDIA, Qt 6.12.0, unit VGS-2232-measure-1793759881). The directory restriction did not isolate file authority: plugins share the shell's process and privileges under [D010](D010-facade-scope-not-sandbox.md).

**Rejected**: A second grim capture, which duplicated work and could include the freeze. Whole-output saves on the GUI thread, which the cited run found too costly per turn.

**Revisit when**: Quickshell gives QML an image writer off the GUI thread or a `ScreencopyView` image export, or a holder needs the frame of some screens only.
