# D099: No graphics program a validation run starts can open an amdgpu DRM node

[← Decision Index](INDEX.md)

**Date**: 2026-10-03

**Status**: Active

**Research**: VGS-784; owner order 1791052161 and owner additions 2026-10-03 18:35Z

**Context**: On host cachy on 2026-10-02, under kernel 7.2.8-1-cachyos, a smoke run's `qs` opened the AMD integrated GPU's DRM node and the kernel faulted in `drm_sched_rq_add_entity`, called from `amdgpu_vm_init`, called from `amdgpu_driver_open_kms`. The run's nested Hyprland then entered the same open path and spun, and the machine needed a hard reset. The fault is in the driver's per-open path, so a plain `open()` of the node can trigger it, and kernel 7.2.9 holds no fix. The AMD GPU drives no display on that host; the NVIDIA GPU does. Each validation run starts new compositor and shell processes, so it is the most frequent fresh opener.

**Decision**: No compositor, shell, `qmltestrunner` or browser a validation run starts, and no process below one, can open an amdgpu DRM node. The node is absent from the view those processes run in.

- **One owner.** `scripts/smoke/gpu-fence.sh` alone resolves the nodes, builds the view and proves it. Node numbers change across boots, so it reads each node's driver from `/sys/class/drm/<node>/device/driver` on every run, and no entry point resolves a node or builds a namespace argument of its own.
- **A mount namespace.** Where an amdgpu path is visible, the fence runs its caller in a mount namespace bubblewrap makes, inside the new user namespace an unprivileged bubblewrap needs. A tmpfs covers `/dev/dri` and `/dev/char`. Every node whose driver is not amdgpu is bound back, and every link that does not resolve to an amdgpu node is made again, the `/dev/dri/by-path` ones included.
- **Proved before the caller starts.** Inside the namespace the fence stats every path, with no open, and prints one `gpu-fence: absent path=` or `gpu-fence: present path=` line for each. An amdgpu path that resolves, or another node or link the host had that no longer does, stops the run.
- **Never outside.** A missing bubblewrap, a namespace that cannot be made or a failed proof exits 77 with `gpu-fence: status=not-measured reason=<reason>`. A host with no amdgpu node runs as before, with no namespace.
- **Every starter calls it.** `scripts/qml-smoke.sh`, `scripts/sandbox-shots.sh`, `scripts/measure-shader.sh` and `scripts/qml-unit.sh` hand themselves to the fence before they make anything. `scripts/smoke/harness.sh`, the one starter of the nested Hyprland and the shell, starts nothing where the fence's check fails.
- **Scope: the DRM nodes and every link to them.** `/dev/fb*`, `/dev/drm_dp_aux*` and `/dev/kfd` belong to amdgpu too and stay visible. The recorded fault's call path is the DRM file open; that an open of those nodes stays out of it is read from that call path and not tested. On host cachy on 2026-10-03 no `ls -l /proc/<pid>/fd` snapshot of the nested Hyprland and `qs`, taken once a second through one validation run, held one of them, and one traced start of both opened none. An open shorter than a second in a later row is not ruled out.
- **Scope: the four starters.** Every other `scripts/validate` row runs outside the fence, in the host's view. Two of them run Qt's `qsb`, `scripts/check-voiceorb-shader.py` and its control. Traced inside the fence on the same day, `scripts/check-voiceorb-shader.py` opened nothing under `/dev/dri`, and its one open under `/dev` was `/dev/tty`.
- **The caller's pid is bubblewrap's monitor.** The monitor forwards no signal, so a run is stopped by its process group or its unit, and a caller's wait can return before the teardown ends.
- **Known limit.** The PID namespace stays the caller's, because the harness reads `/proc/<pid>` and a reader outside reads `/proc/<pid>/fd` of the nested processes. A path through an outside process's `/proc/<pid>/root` or `/proc/<pid>/fd` therefore still reaches the node.

**Rationale**:

- A kernel hang costs the owner the whole machine, so the rule is enforced where the kernel resolves the path, not where a library chooses a device.
- A node that does not exist cannot be opened by a library that lists `/dev/dri`. Traced inside the fence with strace 7.2 and `-k` on host cachy on 2026-10-03, every open under `/dev/dri` follows a listing of that directory, and no program names an amdgpu path. NVIDIA's `libnvidia-glsi` and `libnvidia-eglcore` list and open in `qs` and in the nested Hyprland, `libnvidia-egl-wayland2` in `qs` alone, and `libaquamarine` in Hyprland. Mesa's `libEGL_mesa` in Hyprland and RADV, `libvulkan_radeon`, in the shader runner's `qs` list the directory through libdrm's `drmGetDevices2` and open nothing there. The trace does not prove which of them opened the node outside the fence.
- One resolver gives one answer. Two scripts that each read the driver links could disagree after a boot renumbers the nodes.
- The proof makes each run carry its own evidence, and a broken fence stops the run before any graphics program starts.

## Alternatives Considered

| Alternative | Why rejected |
|---|---|
| A systemd user scope with `DevicePolicy=strict` and `DeviceAllow` | The user manager does not enforce it. `systemd-run --user --scope -p DevicePolicy=strict -- head -c 1 /dev/full` exited 0 and returned the byte, and a scope that allowed only `/dev/null` still read `/dev/full` (systemd 262, host cachy, 2026-10-03, tested against `/dev/full` alone). |
| Environment variables that pick a GPU: `AQ_DRM_DEVICES`, `DRI_PRIME`, `MESA_VK_DEVICE_SELECT` | They choose among devices and leave every node in `/dev/dri`, which the traced programs list and open from. This change did not test them. |
| A rebuilt `/dev` holding only the nodes the programs need | The list must name every node a row uses: the nested Hyprland and `qs` hold `/dev/nvidiactl`, `/dev/nvidia0` and `/dev/nvidia-modeset` beside the DRM node, and rows use ptys, shared memory and input nodes. A missed node breaks a row; a tmpfs over two directories leaves the rest of `/dev` as the host has it. |
| A wrapper at each process start | The smoke starts the shell from many rows and through `bin/vgshell`, which ships and cannot carry test code. A namespace entered once by the entry point is inherited by every process below it. |
| Hiding `/dev/fb*`, `/dev/drm_dp_aux*` and `/dev/kfd` too | The recorded call path is the DRM file open, and 1453 once-a-second `ls -l /proc/<pid>/fd` snapshots of the nested Hyprland and `qs` processes of one validation run held none of them. Neither reading is a test of those nodes: the Scope bullet states the limits. |
| A PID namespace, to close the `/proc/<pid>/root` path | The harness and the evidence reader need the nested processes' `/proc` entries from outside. One start of the nested Hyprland and `qs`, traced with every path syscall, named no `/proc/<pid>/root` or `/proc/<pid>/fd/<n>` path; later rows were traced for the DRM paths alone. |

## Omarchy comparison

Checked against basecamp/omarchy `quattro` at `821ae5890`: `docs/testing.md`, `test/shell.d/base-test.sh` and `test/shell.d/chromium-claude-test.sh`.

| Omarchy | VGS | Where VGS takes it, or why it differs |
|---|---|---|
| Runs no nested or test compositor. A test that needs one calls `require_compositor`, which asks the live session through `hyprctl -j monitors` and skips without it. | Starts its own nested Hyprland and shell for every smoke run. | Differs: VGS never tests against the live session, so its runs start fresh GPU clients, and the host has an amdgpu node those clients must not open. |
| Hides no GPU node. | Hides the amdgpu DRM nodes from every run. | Differs: Omarchy has no such run to protect. |
| `chromium-claude-test.sh` probes `bwrap --ro-bind / / --unshare-user ... true` first and skips when user namespaces are unavailable. | The fence makes a namespace around `true` first and exits 77 when that fails. | Taken: probe before use, with the same tool. Here a failed probe is a run that did not measure, never a pass. |

**Revisit When**: A kernel on the owner's machine fixes the amdgpu open path; a process is found that reaches the node through a path the namespace leaves; an open of `/dev/fb*`, `/dev/drm_dp_aux*` or `/dev/kfd` is shown to enter the faulting path; or the systemd user manager enforces a device policy.

**Verification**: `scripts/test-gpu-fence.sh` drives the fence over trees of ordinary files, with one control per rule; its first control is the fence with no restriction, which reports every amdgpu path it sees by stat and starts nothing. It also holds each entry point to the call and the harness to its check. On host cachy on 2026-10-03 the fence's proof printed six `absent` lines for the amdgpu paths and six `present` lines for the NVIDIA ones before each run, and the fd snapshots of a `scripts/validate` run held `/dev/dri/renderD128` as the only DRM node.

**References**: [validation-smoke.md](../architecture/validation-smoke.md), [D001](D001-hyprland-only.md)
