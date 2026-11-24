# D142: A sandbox runner may declare a throwaway host, whose world is the host itself

[← Decision Index](INDEX.md)

**Date**: 2026-11-23

**Status**: Active

**Research**: [VGS-2747](https://linear.app/vanillagreen/issue/VGS-2747)

**Refines**: [D112](D112-one-world-owns-the-test-run.md), adding a declared world without bubblewrap, and [D099](D099-no-amdgpu-node-in-validation-runs.md), which that world meets by refusing any amdgpu node.

**Decision**: The runner that creates a sandbox host and will delete it may pass `--throwaway-host` at its outermost call of `scripts/smoke/gpu-fence.sh`. No entry point in the repository passes it, and no environment variable or setting selects it. On such a host the world is the host itself, without bubblewrap. The fence keeps the owned root, the reaper, the declared environment table, the data and core ceiling, the output and input refusals and evidence retention. It drops the read-only host, the private `/tmp` and `/dev/shm`, the unshared network and the PID namespace, and refuses `--secrets`, `--sign-in`, `--nix-store`, `--sys` and `--dev`. Every throwaway start reads the real `/sys` and `/run` first, and exits 77 when the host registers an amdgpu node, an input device or a display output, or shows a live session under `/run/user`, `/run/systemd/sessions`, `/run/dbus/system_bus_socket` or `/run/tailscale`. A nested call inherits the world only from a root that holds the world's marker and whose owner is the caller's ancestor. The fence is the child subreaper of the command's tree and KILLs every process the command leaves before it removes the root. A pass in this world proves the row's own checks, not the boundaries it drops: a record returned from it carries `world=throwaway`, and validate never reuses it as a pass for its own tree.

**Why**: A nested check must run on a sandbox the run creates and deletes, where bubblewrap or user namespaces are missing. A per-call declaration cannot be left on, as an environment variable or a setting can. The refusals stop the accidental case on a person's computer, which registers input devices, connectors or a session: the owner's desktop lists 72 input entries and 8 connectors, and the readings are on VGS-2747. They do not prove ownership. The decision covers only a host the run declares it created and that shows none of these facts. A caller who adds the declaration to their own command and hides every fact is bypassing on purpose, which review holds. Without the PID namespace the subreaper is the one owner of the command's descendants, sessions of their own included.

**Rejected**: Selecting the world from host facts with no declaration. No listing of `/sys` proves that the run owns the host, and a VM with no display can list no input device or connector. Running on the host wherever bubblewrap is missing, which is a fallback. A cgroup as the owner of the command's descendants, which needs a delegated cgroup tree the sandbox may not give.

**Revisit when**: The target sandbox gives user namespaces, so the bubblewrap world runs there; a person's computer is shown to pass the refusals; or a record from a throwaway world is reused as a full pass.
