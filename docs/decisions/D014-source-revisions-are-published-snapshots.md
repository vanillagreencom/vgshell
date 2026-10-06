# D014: A plugin's source revision is a published snapshot

[← Decision Index](INDEX.md)

**Date**: 2026-09-26
**Status**: Active
**Research**: —

**Decision**: The scan hashes a plugin directory into a revision and publishes each revision's files once under the session runtime directory. The shell loads entry points from there, every slot keys on `<id>@<revision>`, and a rescan rebuilds only the plugins whose files changed. The engine's cache of old revisions is accepted as unbounded within a session.

**Why**: QML caches every file by URL, so only a new directory makes a changed sibling file read again without a new engine, and a new engine drops every service's state. `scripts/test-vgshell-scan.py` and `scripts/smoke/rows/sources.sh` hold the rule.

**Rejected**: Restarting the shell, or Quickshell's own reload, on a plugin edit. Both lose a lock screen's or a notification service's state for an unrelated widget's edit; `clearComponentCache` cannot run while old-type objects exist.

**Revisit when**: A plugin tree is large enough that copying it per revision is felt, a session's retained types matter, or Quickshell offers per-URL cache eviction.
