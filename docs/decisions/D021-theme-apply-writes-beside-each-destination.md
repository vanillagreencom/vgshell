# D021: A theme apply writes beside each destination, under one lock, and the shell document last

[← Decision Index](INDEX.md)

**Date**: 2026-09-27
**Status**: Active (application-directory writes → [D022](D022-theme-apply-keeps-managed-links-in-application-directories.md))
**Research**: [VGS-461](https://linear.app/vanillagreen/issue/VGS-461), [VGS-458](https://linear.app/vanillagreen/issue/VGS-458)

**Decision**: Apply renders into a stage and swaps it over the state `theme/` directory by rename, under one `flock` beside the theme file. Every application write is staged beside its destination and moved in by rename; a symlink is resolved and the file it names replaced with its mode kept. The shell document is written last. A target that fails to render leaves the apply `partial` and keeps the files it landed, and an include line is never left naming a dropped file.

**Why**: A rename in one directory is atomic and crosses no filesystem. Replacing the resolved file keeps a dotfile manager's link a link. The lock beside the theme file is the one place two callers with different runtime directories both reach. Writing the shell last keeps the displayed theme from running ahead of the applications.

**Rejected**: An in-place write, which can leave a user's configuration half-written on a crash; replacing the link, which severs the managed file; and a lock under `XDG_RUNTIME_DIR`, which two callers need not share.

**Revisit when**: An application reads its configuration through a hard link or watches its inode, needs its include line somewhere other than the first line, or needs `theme/` present at every instant.
