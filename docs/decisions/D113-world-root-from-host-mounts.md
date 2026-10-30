# D113: Build the world root from host mounts

[← Decision Index](INDEX.md)

**Date**: 2026-10-29

**Status**: Active

**Research**: [VGS-2061](https://linear.app/vanillagreen/issue/VGS-2061), owner ruling for root-from-mounts.

**Refines**: [D112](D112-one-world-owns-the-test-run.md), extending the world's mount layout to admit a declared, world-owned `/nix`.

**Decision**: The world's `/` is bubblewrap's own empty root. Bind each top-level host directory read-only and recreate each top-level host link. Bind `/nix` from a declared directory inside the world's own root, created and deleted by the world. Then remount `/` read-only.

**Why**: A read-only bind of the host `/` cannot create `/nix` when the host lacks it. Separate host mounts admit the exported Nix store without a host write or a second world. A host top-level entry created after world entry is not visible inside that world; this is an accepted limit.

**Rejected**: Keep the host root bind and leave the Nix install outside the nested startup proof. That leaves a published install without the proof the other channels receive.

**Revisit when**: A test needs a host top-level entry created after world entry.
