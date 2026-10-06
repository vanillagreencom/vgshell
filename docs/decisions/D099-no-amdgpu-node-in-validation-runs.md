# D099: No graphics program a validation run starts can open an amdgpu DRM node

[← Decision Index](INDEX.md)

**Date**: 2026-10-03
**Status**: Active
**Research**: [VGS-784](https://linear.app/vanillagreen/issue/VGS-784)

**Decision**: Every validation entry point that starts a compositor, a shell, a test runner or a browser hands itself to one fence, `scripts/smoke/gpu-fence.sh`, which hides the amdgpu DRM nodes behind a tmpfs in a mount namespace, proves them absent by `stat`, and exits 77 when it cannot build or prove the namespace. A fence exit 77 is not a pass.

**Why**: On host cachy on 2026-10-02 a smoke run's `qs` opened the AMD GPU's DRM node and the kernel faulted in the driver's per-open path, so a plain `open()` can hang the machine. The rule is enforced where the kernel resolves the path, because every traced opener lists `/dev/dri` and opens what it finds. `scripts/test-gpu-fence.sh` holds the fence.

**Rejected**: GPU-selecting environment variables such as `AQ_DRM_DEVICES`, `DRI_PRIME` and `MESA_VK_DEVICE_SELECT`. They choose among devices and leave every node listable. A systemd scope with `DevicePolicy=strict` did not enforce on the owner's machine.

**Revisit when**: A kernel on the owner's machine fixes the amdgpu open path, a process reaches the node through a path the namespace leaves, another device node is shown to fault, or systemd's user manager enforces a device policy.
