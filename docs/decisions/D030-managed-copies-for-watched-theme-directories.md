# D030: Managed copies serve watched theme directories

[← Decision Index](INDEX.md)

**Date**: 2026-09-28
**Status**: Active
**Research**: [VGS-492](https://linear.app/vanillagreen/issue/VGS-492)
**Refines**: [D022](D022-theme-apply-keeps-managed-links-in-application-directories.md), [D024](D024-theme-apply-sets-one-theme-key-in-an-application-settings-file.md)

**Decision**: A target entry is a link or a copy, never both. A copy is written by rename into the application's watched directory and is managed only while its bytes equal the previous or the new render; a user-edited file is never replaced.

**Why**: Directory and file watchers see a renamed file but not a swapped link target, so sessions kept the old colours until a restart. Byte equality is the only ownership marker that needs no second file. `scripts/test-vgshell-entries.sh` holds the rule.

**Rejected**: Keeping links and touching the link. A watcher still may not read the target's new bytes, and each CLI would need its own unproven nudge.

**Revisit when**: A watched CLI cannot reload from an atomic copy, or a copied file needs a mode other than 0644.
