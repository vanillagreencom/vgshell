# D037: Plugin status is a declared, published, per-plugin record

[← Decision Index](INDEX.md)

**Date**: 2026-09-28
**Status**: Active
**Research**: [VGS-525](https://linear.app/vanillagreen/issue/VGS-525), [VGS-588](https://linear.app/vanillagreen/issue/VGS-588)
**Refines**: [D032](D032-settings-plugin-and-manifest-settings-convention.md)

**Decision**: A plugin declares typed status entries in its manifest; its service writes them through the `status` capability, every instance of the plugin reads the one in-memory record, and Settings draws them read-only. A credential's presence, never its value, enters status. The types include `presenceList`, a bounded list of labelled presences, for accounts a manifest cannot know ahead, such as a Slack workspace, whose token lives in libsecret under its own key.

**Why**: One writer per key keeps one owner per poller across screens, and a record the core lends is released with the plugin with nothing on disk. A manifest cannot list the owner's workspaces, and page code is refused by D032, so the list type carries them. `scripts/test-plugin-status.js` and `scripts/smoke/rows/status.sh` hold the record.

**Rejected**: A state file per plugin that every instance watches. It outlives the plugin and costs a watcher per instance. Status `data` drawn by a plugin's own page code was rejected for the same reason as D032.

**Revisit when**: A plugin must publish a value another plugin reads, status must survive a restart, or a record exceeds 64 KiB.
