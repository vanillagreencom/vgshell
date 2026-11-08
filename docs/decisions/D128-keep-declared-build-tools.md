# D128: Keep declared build tools out of orphan removal

[← Decision Index](INDEX.md)

**Date**: 2026-11-08

**Status**: Active

**Research**: [VGS-2373](https://linear.app/vanillagreen/issue/VGS-2373/update-orphans-keep-build-tools-of-installed-packages-and-read-every)

**Decision**: The orphan review excludes tools that current VGS recipe or AUR metadata declares as make or check dependencies of installed packages. It names kept tools and their packages. A partial metadata read names unread packages and makes no unused-dependency claim.

**Why**: The owner wants installed packages' build tools retained (owner Slack 1794107513). Removing cli11 or asar only makes a later build install them again. Current declarations apply that choice to every consumer without a fixed ignore list or changing install reasons.

**Rejected**: VGS-2090's choice to offer every orphan with explanatory labels. It still offers tools installed packages need, and incomplete metadata can make an unused-dependency label misleading.

**Revisit when**: Package metadata gains a reliable way to distinguish build tools that installed packages no longer need, or the owner requests their removal.
