# D047: Services build after the first bars present a frame

[← Decision Index](INDEX.md)

**Date**: 2026-09-29
**Status**: Active
**Research**: [VGS-587](https://linear.app/vanillagreen/issue/VGS-587), [VGS-592](https://linear.app/vanillagreen/issue/VGS-592)

**Decision**: The core builds services only after every bar of the first scan has presented its first frame, through one latch in `shell/Core/ServiceGate.qml` that opens once per process, with a 358 ms deadline for a bar that never presents.

**Why**: Every service build ran in the same synchronous turn as the bar and delayed its first frame. Measured on host cachy on 2026-09-29 with `scripts/qml-smoke.sh --first-bar-runs 12`, the default set's first bar fell from 307 to 344 ms before the gate to 206 to 271 ms behind it, while releasing one event-loop turn later measured 288 to 330 ms, close to no gate at all, because the bar had not reached the compositor yet. The deadline is twice the highest wait logged over 33 runs. `scripts/smoke/rows/start-order.sh` reads the order back.

**Rejected**: Releasing one event-loop turn after the bars.

**Revisit when**: Quickshell or Qt signals a layer surface's first presented frame, a service must run before the first bar maps, or builds become asynchronous.
