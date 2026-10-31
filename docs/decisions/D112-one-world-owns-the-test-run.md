# D112: One world owns the nested test run

[← Decision Index](INDEX.md)

**Date**: 2026-10-21

**Status**: Active

**Research**: [VGS-1971](https://linear.app/vanillagreen/issue/VGS-1971)

**Refines**: [D099](D099-no-amdgpu-node-in-validation-runs.md), extending the GPU fence into the nested run's boundary.

**Decision**: `scripts/smoke/gpu-fence.sh` owns one root and one world for each nested run. The host is read-only, temporary and runtime directories are private, session sockets and the network are hidden, and the environment is declared. Only a world deletes a root, and only one under its own `TMPDIR`: its own after its namespace ends, where it retains evidence, and a root whose owner is gone, which the next world to make a root removes. The owner is named in the root's name at creation; a root whose owner is alive, unreadable or in another PID namespace, or kept by `--keep`, is never removed. A root without an owner in its name, made by older code and a `--keep` root of that form included, is removed only when it is older than 10800 s and no process holds it as a working directory, descriptor or mount point. Runners declare outputs, keep and the selftest's filtered bus, sign-in and network exceptions at entry. The shell always hides stand-in registry names from its host PATH.

**Why**: A caller-named cleanup target erased a checkout, and a missing stand-in exposed the host's Tailscale command. Per-caller guards leave every writer and deleter responsible for the host. One mount boundary prevents the class. The owner's home remains readable by absolute path. SIGKILL of the owner runs no trap and leaves its root; cachy's RAM-backed `/tmp` held 189 such roots, 8.6 GB, on 2026-10-31. A timer or sweeper would add a second deleter, so the next acquisition is the reaper.

**Rejected**: A timer or separate sweeper for dead roots, which adds a deleter outside the world. Per-runner guards, user-manager sandboxing and one container per run. They divide ownership or replace the existing nested runner boundary. A closed tool allowlist would also exclude host tools the shell legitimately probes.

**Revisit when**: A nested runner needs a host write or service that cannot be expressed as a declared output or a narrow selftest exception, or a process can reach the live session through a path the world leaves.
