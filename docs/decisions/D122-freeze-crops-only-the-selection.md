# D122: The freeze crops only the selected rectangle

[← Decision Index](INDEX.md)

**Date**: 2026-11-05

**Status**: Active

**Research**: [VGS-2322](https://linear.app/vanillagreen/issue/VGS-2322), owner approvals 1793915212 and 1793916073 and [chosen route](https://linear.app/vanillagreen/issue/VGS-2322#comment-4ba52100)

**Supersedes**: [D118](D118-screen-freeze-writes-its-held-frame.md), replacing frame export and its directory ownership

**Refines**: [D115](D115-screen-freeze-is-a-core-surface.md), retaining the core's whole-output freeze

**Decision**: Capture one frame per output before drawing the freeze, with the requested cursor in that same view. The core's ready answer permits selection. Crop only the selected rectangle from the held views through one Qt grab and PNG write, including a selection across outputs. The trusted capability holder owns the acquired destination file and delegates its write; this grants no sandbox boundary under [D010](D010-facade-scope-not-sandbox.md). Thaw and instance disposal invalidate pending work. A kept screenshot delay precedes its sole capture and selection.

**Why**: The owner requires omasnap's capture, select and in-memory crop route instead of whole-frame export and a second capture. Quickshell exposes a held texture rather than shared CPU pixels, so the existing worker's PNG consumers need one selected readback and write. Every-output selection must keep the drawn frames unchanged while Qt composes their selected portions in one window. The selected PNG write still runs on the GUI thread; its cost needs measurement, not another band chain.

**Rejected**: Whole-output PPM export at several scales followed by a Python crop, which performs work unrelated to the selected rectangle. A second cursor capture or a live capture after selection, which violates the one-capture choice. A core-owned output directory justified as isolation, which contradicts the shared-process authority in D010.

**Revisit when**: Quickshell offers a direct crop of a held frame, or the selected PNG write is measured to prevent the shell from responding.
