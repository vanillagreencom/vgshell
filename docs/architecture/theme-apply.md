# A theme apply lands whole or not at all

Read before touching the apply, a reload hook, the follow, or `vgshell theme reload`.

## The approach

Apply renders every target into a stage beside its destination, swaps the stage over the state `theme/` directory under the theme lock, and writes the shell document last, so the shell never reads half a theme. A target that fails to render costs only itself: the apply is `partial`, exit 3, and that target keeps its last files. A written file changes nothing until its application re-reads it, so a target with a reload hook stays `reload-pending` until the hook succeeds, and `vgshell theme reload` retries the pending set. A package that changed after its apply reaches the theme file only through a follow, which never overwrites a hand-edited theme file. The choices are [D021](../decisions/D021-theme-apply-writes-beside-each-destination.md) and [D022](../decisions/D022-theme-apply-keeps-managed-links-in-application-directories.md).

## Why

A rename in one directory is atomic, and a rename cannot replace a non-empty directory, so the swap is two renames with the old directory moved back when the second fails. Writing the shell last keeps the displayed theme from running ahead of the applications. A shipped package changes with a VGS update and an installed one with `vgshell theme update`; without a follow the theme file keeps stale bytes, and without the hash check a follow would overwrite a user's edit.

## Rules

- Do stage every file and swap by rename; never write into `theme/` in place. `scripts/test-vgshell.sh` pins it.
- Do write the theme file last and byte for byte; a re-serialised copy reports every apply as modified. `scripts/test-vgshell.sh` pins it with a re-serialising control.
- Do keep the include line, the managed entries and the selection key on every apply, unchanged bytes included, so a hand edit is repaired. `scripts/test-vgshell.sh` and `scripts/test-vgshell-agents.sh` pin it.
- Never create a file through a dangling symlink; resolve the link and replace the file it names by rename with its mode. `scripts/test-vgshell.sh` pins it with a link-replacing control.
- Do refuse the whole apply as `malformed` when either configuration layer is refused, since no target's enablement is then known. `scripts/test-vgshell.sh` pins it.
- Do record every due target as pending before the swap, so an apply that dies after the swap leaves it pending, and never run a hook on unchanged bytes unless the target says `reload.always`. `scripts/test-vgshell-reload.sh` pins both.
- Do give a hook `/dev/null` for its streams and no lock descriptor, kill it at its timeout, and leave the target pending. `scripts/test-vgshell-reload.sh` pins it.
- Never start a hook under `VGS_TEST_RUN` whose target directory, command path or any PATH entry lies outside the scratch root, or while a live session channel such as `WAYLAND_DISPLAY`, `TMUX` or `DBUS_SESSION_BUS_ADDRESS` is set. `scripts/test-vgshell-reload.sh` pins it, and `scripts/test-validate.sh` proves `scripts/validate` exports the marker.
- Do record the applied name, the theme file's hash and the package digest after the theme file lands, and never follow over a theme file whose hash is not the recorded one. `scripts/test-vgshell-follow.sh` pins both.
- Do digest `theme.json`, `terminal.json` and `targets/` only; `backgrounds/` holds no colours. `scripts/test-vgshell-follow.sh` pins it with a curated-out control.

## The canonical example

The `apply` verb of `bin/vgshell-theme-judge`: stage, swap under the lock, wire, mark pending, write the theme file last, record the follow. Copy its order for any new verb that writes.

## Revisit when

An application reads its configuration through a hard link or watches its inode, needs its include line somewhere other than the first line, or needs `theme/` present at every instant.

## Not governed

What each target renders and how it is wired, which is [theme-targets.md](theme-targets.md). The test-run guard's reason, that a test reaching a shipped hook would signal the owner's live session, is [validation.md](validation.md)'s.
