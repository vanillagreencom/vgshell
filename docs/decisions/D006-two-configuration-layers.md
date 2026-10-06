# D006: Two configuration layers merged by entry id

[← Decision Index](INDEX.md)

**Date**: 2026-09-21
**Status**: Active
**Research**: —

**Decision**: Configuration is a shipped layer and a user layer. A user key replaces the shipped key whole, except `plugins`, merged by entry id with the user entry winning, and `disabledPlugins`, which is the user's list alone. `shell/Core/PluginLogic.js` is the one merge.

**Why**: One file stops delivering shipped defaults the moment a user edits it, and a deep merge makes the effective value unreadable. Merging by id keeps what is running readable from two files.

**Rejected**: One configuration file, or a deep merge. The first loses shipped defaults; the second hides the effective value.

**Revisit when**: A third system-wide layer under `/etc` is needed, or a shipped default must override a user value.
