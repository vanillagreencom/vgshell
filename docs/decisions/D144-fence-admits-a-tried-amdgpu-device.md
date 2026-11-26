# D144: The GPU fence admits an amdgpu device a full battery ran on, and px13 takes nested units by placement

[← Decision Index](INDEX.md)

**Date**: 2026-11-26

**Status**: Active

**Research**: [VGS-2764](https://linear.app/vanillagreen/issue/VGS-2764)

**Refines**: [D099](D099-no-amdgpu-node-in-validation-runs.md), by admitting one amdgpu device by its PCI ids. [D142](D142-throwaway-host-world.md) still refuses every amdgpu node.

**Decision**: `scripts/smoke/gpu-fence.sh` keeps an amdgpu DRM node visible only when the `vendor` and `device` files of its PCI device in sysfs name a device on the fence's admitted list. The list is in the script, never in a setting. It holds px13's Strix Halo GPU, 1002:1586, and never home's Granite Ridge GPU, 1002:13c0, which faulted. A node whose ids are absent or unreadable stays hidden. The bubblewrap world also drops every face the host installed of a font family the checkout bundles, so the shell draws those families from the unit's own copies on every host. The throwaway world of D142 runs on a host the run created and gets no such filter. A unit goes to px13 only when the desk there is idle, no Jarvis Voice call is live, and its selection holds no row placed on home. These rows are placed on home: every row with a latency, timing or resident-size ceiling measured on home, theme-browser's pixel equality and capture's pointer check. Until orch runs a unit on a second host, the overseer runs a px13 unit as a stand-in: Jarvis runs `orch-runtime validate entry --foreground --run-id <admitted id>` in a clean clone at the lane's commit, and the overseer copies the run folder back into the admitted run folder on home. A copied record that `orch-runtime validate entry --record` refuses on home is no verdict. [kendex#7079](https://github.com/vanillagreencom/kendex/issues/7079) asks orch to own this step and removes the stand-in.

**Why**: A unit takes 3 to 4 hours, and home runs them one at a time, so a second runner halves the queue wait. px13's only GPU is amdgpu, so D099 left it nothing to draw with. The 2026-10-02 fault was in the per-open path of home's 1002:13c0 device. On px13's 1002:1586 device a full battery at 4b640102c ran 6180 s with no amdgpu, drm, reset, timeout, Oops or BUG kernel line. An id read from sysfs names the device itself, and a setting could be left on for the device that faults. The same battery failed greeter and core-drift because a font the host installed shadowed the unit's copies. Qt adds the copies to fontconfig's application set past the config's font filter, so the drop removes only the host's faces. The AMD node drew a 3-level channel difference where theme-browser wants equal pixels, and the capture lacked the pointer. Home's timing ceilings were measured on home's hardware.

**Rejected**: Admitting every amdgpu node on a host the owner names, which admits the device that faulted when a name is wrong. Widening theme-browser's pixel tolerance and capture's pointer check for the AMD node, which weakens the checks on home. Calibrating each timing ceiling again on px13, which doubles every budget's measurement for a runner that takes only part of the queue.

**Revisit when**: A full battery on px13 shows an amdgpu, drm, reset, timeout, Oops or BUG kernel line, which removes 1002:1586 from the list. Also revisit when another amdgpu device passes a full battery, when orch runs a unit on a second host, or when a row placed on home passes on px13.
