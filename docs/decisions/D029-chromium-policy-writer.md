# D029: Chromium's theme colour is a managed policy written by one narrow passwordless writer

[← Decision Index](INDEX.md)

**Date**: 2026-09-28
**Status**: Active
**Research**: [VGS-491](https://linear.app/vanillagreen/issue/VGS-491)

**Decision**: The `chromium` target hands the theme's background colour to `bin/vgshell-browser-policy`, a root-installed writer with one sudoers rule whose only argument is six hex characters. It writes `color.json` under each browser's managed policy directory. Apply never prompts and skips the target as `setup-absent` until the writer is on PATH.

**Why**: The owner wants the browser to follow the theme in Classic mode, which only the managed policy reaches. The argument grammar is the whole grant, so the rule can hand out a colour and nothing else. `scripts/test-vgshell-browser-policy.sh` holds the writer.

**Rejected**: Following the theme through the browser's GTK mode alone, the first choice, which cannot set a colour; and a privileged writer asked through `pkexec` on each apply, because a background apply has no one to answer the prompt.

**Revisit when**: Chromium reads a theme colour from a user-owned file, or a second policy key needs writing.
