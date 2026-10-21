# D099: No graphics program a validation run starts can open an amdgpu DRM node

[← Decision Index](INDEX.md)

**Date**: 2026-10-03
**Status**: Active
**Research**: [VGS-784](https://linear.app/vanillagreen/issue/VGS-784)

**Decision**: Every validation entry point that starts a compositor, a shell, a test runner or a browser enters the world in `scripts/smoke/gpu-fence.sh`. The world hides amdgpu DRM nodes behind tmpfs mounts, restores device access to the other nodes, proves the AMD paths absent by `stat`, and exits 77 when it cannot build or prove the namespace. A world exit 77 is not a pass. [D112](D112-one-world-owns-the-test-run.md) governs the rest of the boundary.

**Why**: On host cachy on 2026-10-02 a smoke run's `qs` opened the AMD GPU's DRM node and the kernel faulted in the driver's per-open path, so a plain `open()` can hang the machine. The rule is enforced where the kernel resolves the path, because every traced opener lists `/dev/dri` and opens what it finds. `scripts/test-gpu-fence.sh` holds the fence.

**Rejected**: GPU-selecting environment variables such as `AQ_DRM_DEVICES`, `DRI_PRIME` and `MESA_VK_DEVICE_SELECT`. They choose among devices and leave every node listable. A systemd scope with `DevicePolicy=strict` did not enforce on the owner's machine.

**Revisit when**: A kernel on the owner's machine fixes the amdgpu open path, a process reaches the node through a path the namespace leaves, another device node is shown to fault, or systemd's user manager enforces a device policy.
