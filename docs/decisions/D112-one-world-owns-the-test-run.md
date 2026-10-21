# D112: One world owns the nested test run

[← Decision Index](INDEX.md)

**Date**: 2026-10-21

**Status**: Active

**Research**: [VGS-1971](https://linear.app/vanillagreen/issue/VGS-1971)

**Refines**: [D099](D099-no-amdgpu-node-in-validation-runs.md), extending the GPU fence into the nested run's boundary.

**Decision**: `scripts/smoke/gpu-fence.sh` owns one root and one world for each nested run. The host is read-only, temporary and runtime directories are private, session sockets and the network are hidden, and the environment is declared. Only the world deletes its root and retains evidence after its namespace ends. Runners declare outputs, keep and the selftest's filtered bus, sign-in and network exceptions at entry. The shell always hides stand-in registry names from its host PATH.

**Why**: A caller-named cleanup target erased a checkout, and a missing stand-in exposed the host's Tailscale command. Per-caller guards leave every writer and deleter responsible for the host. One mount boundary prevents the class. The owner's home remains readable by absolute path, and SIGKILL of the owner leaves its root.

**Rejected**: Per-runner guards, user-manager sandboxing and one container per run. They divide ownership or replace the existing nested runner boundary. A closed tool allowlist would also exclude host tools the shell legitimately probes.

**Revisit when**: A nested runner needs a host write or service that cannot be expressed as a declared output or a narrow selftest exception, or a process can reach the live session through a path the world leaves.
