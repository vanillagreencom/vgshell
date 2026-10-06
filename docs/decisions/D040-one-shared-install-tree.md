# D040: Every channel installs one shared VGS tree

[← Decision Index](INDEX.md)

**Date**: 2026-09-28
**Status**: Active
**Research**: [VGS-531](https://linear.app/vanillagreen/issue/VGS-531), the platform roadmap attached to [VGS-511](https://linear.app/vanillagreen/issue/VGS-511)

**Decision**: Every channel runs one installer into `/usr/share/vgshell`, or a versioned user tree for a curl install. `vgshell self update` touches only trees VGS laid out itself, and publishing runs from the maintainer's machine with no GitHub workflow.

**Why**: One installer gives every channel the same file set, the install method decides who owns the tree, and local publishing keeps signing and AUR keys off the repository. `scripts/test-install-tree.sh` and `scripts/check-packaging.js` hold the tree.

**Rejected**: `/usr/lib/vgshell`. The tree is scripts and data, not architecture-specific binaries.

**Revisit when**: VGS ships architecture-specific binaries, the owner reinstates CI, or Fedora ships the runtime floor.
