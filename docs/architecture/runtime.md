# One shell per session, with one owner for every resource

Read before touching anything that starts, stops, measures or talks to the shell, and before adding a watcher, a poller, a cache or a subprocess.

## The approach

The runner owns the instance lock and supervises its shell child ([D053](../decisions/D053-runner-holds-the-instance-lock.md), [D069](../decisions/D069-runner-supervises-the-shell.md)). Inside the shell, each watcher, poller, process and session-wide object has one lifetime owner. The patched engine ends managed processes and their owned descendants when that shell ends, including on a crash restart.

## Why

An inherited lock can outlive the shell through its children. A resource without a teardown owner can likewise survive the feature that needs it. Shared readers avoid duplicate polling and disagreeing snapshots. Memory measurements must distinguish live data from allocator retention.

## Rules

### Process

- Never start a second shell against the live session or kill Quickshell processes by name. Validate only in the nested sandbox.
- Enforce managed child lifetime in the patched Quickshell `Process` launcher. Keep wrappers only for independent descendant or helper cleanup. Review holds this boundary.
- Give the lifetime group SIGTERM, the engine's five-second cleanup grace, then SIGKILL. Replacement does not wait; old descendants may overlap it during that grace. Keep helper cleanup within the grace. `scripts/smoke/rows/child-lifetime.sh` checks termination; review holds the cleanup bound.
- Keep cleanup ownership when a descendant forks or leaves the process group. Use `bin/lib/owned-group.py` for explicitly isolated query groups. Review holds escaped-descendant cleanup.
- Preserve explicit detached lifetimes: user terminals through `bin/vgshell-tui`, opened applications through `Capabilities.qml`, display rollback through `MonitorState.qml`, and restart, reset and detached cleanup requests through their core owners. These operations must finish or remain usable after the requesting shell ends. Review holds the exceptions.
- Exit through the runner, never `Qt.quit()` from the root. Root-loading constraints belong beside that code. Keep all run, restart and refusal decisions in the runner's supervision table. `scripts/test-vgshell-run.sh` checks the table.
- Read the shell pid from the lock file for each contacting command. No pid, a dead pid or a failed call exits 69. Judge every `qs ipc call` reply by text through `bin/lib/ipc-reply.sh`, not exit status. `scripts/test-vgshell.sh` and `scripts/test-ipc-reply.sh` check these contracts.
- Retain the version reading at shell start, log it as `shell: version=<version>` and answer version IPC from that reading without another process. Review holds it.
- Use `IpcPages` for replies that grow with the plugin set. Send JSON list arguments inside an object, never as a bare list. `scripts/test-ipc-reply.sh` checks paging; review holds the list boundary, which has no bare-list check.
- Check the runtime floor before taking the lock. `scripts/check-packaging.js` holds recipes to that floor.
- Keep the following autostart sentence byte for byte; `scripts/check-readme.js` consumes it. Autostart is `hl.on("hyprland.start", function () hl.exec_cmd("vgshell start") end)` in `hyprland.lua`.
- Never ship a systemd unit for the shell. Review holds it.
- Start voxtype only from `shell/Core/Dictation.qml` through `bin/vgshell-dictation`, while capability `dictation` is held ([D106](../decisions/D106-dictation-core-lent-over-voxtype.md)). Keep the helper engine-owned and its direct child covered by a parent-death SIGKILL. No plugin or user unit starts the daemon. `scripts/smoke/rows/dictation.sh` checks the lifetime.
- Start `bin/vgshell-idle-inhibit` only from `IdleRegistry.qml`, while an enabled plugin owns an idle stage that can fire ([D116](../decisions/D116-screensaver-inhibits-answered-by-a-core-helper.md)). Keep it engine-owned and childless. After it ends, retry only on a transition from no stage that can fire to one. `scripts/smoke/rows/idle-inhibit.sh` checks this boundary.

### Memory

- Give every runtime object an owner that destroys it. Parenting to a singleton grants a session lifetime. `scripts/smoke/leaks.sh` checks row residue; review holds other ownership.
- Keep the screen freeze's written frames owned by the hold. `shell/Core/ScreenFreeze.qml` alone creates `$XDG_RUNTIME_DIR/vgshell/freeze/<serial>` for a hold that requests the still, clears a crashed shell's files on its first such hold, and removes the directory when the hold ends. `shell/Hosts/FreezeHost.qml` writes there only while that hold lasts ([D118](../decisions/D118-screen-freeze-writes-its-held-frame.md)). `scripts/smoke/rows/screen-freeze.sh` checks removal after thaw and disable.
- Bound caches keyed by other applications' data. Dispatch or destroy every Wayland object the shell creates. Review holds these rules; `scripts/sample-shell-memory.sh` observes a long session but does not prove object ownership.
- State no growth rate below the sampler's duration floor and append no sample to another session's log. `scripts/test-sample-shell-memory.sh` checks both limits.
- Keep the sampler read-only: it never signals, restarts or drives the shell. A C++ attribution needs a profiled start; `scripts/attribute-heap-profile.py` owns that method.

### Temporary artifacts

- Keep lane scratch in its worktree. The base checkout's `tmp/` belongs to main-batch and fleet owners, not ad hoc lane scratch. Review holds this ownership boundary.
- Expire unused VGS artifacts through `scripts/main-run.sh`. Preserve paths referenced by open items and comments, open owner asks and live fleet files. A bare output root or `tmp/` preserves nothing; a named child preserves that artifact subtree. Read the complete kept set before deletion; an unread set permits no deletion. `scripts/test-main-run.sh` checks retention.
- Leave package-owned state to its package's retention owner.

### Performance

- Poll each source through one owner and publish its reading. Batch process-costing lookups across the set, as `bin/vgshell-scan` does for manifests. Never walk disk per keystroke; index once and cancel stale queries. Review holds these rules.
- Watch user-sized path sets through one inotify owner, never one watched `FileView` per path. `scripts/smoke/rows/themes.sh` checks the theme instance count; review holds other consumers.
- Never sleep unconditionally on apply. Read first and skip unchanged writes. Review holds it.
- Keep hot state out of unused or plugin-wide bindings. Notify only the plugin whose status changed; join manager status on read. `scripts/qml-tests/tst_plugin_status.qml` checks this boundary; review holds other hot bindings.
- Build services only after the first bar frame ([D047](../decisions/D047-services-build-after-the-first-bar-frame.md)). `scripts/smoke/rows/start-order.sh` checks it.
- Name the tool and run behind every measured figure. A budget needs its measurement. Review holds the evidence boundary.

## The canonical example

Copy the ownership in `bin/vgshell`'s `run` verb. Inside the shell, use managed `Process`; a helper that escapes its lifetime group owns the escaped descendants' cleanup.

## Revisit when

Quickshell provides a QML file lock, changes crash-restart ownership, or Quickshell or Qt reports a layer surface's first presented frame.

## Not governed

Hyprland requests belong to [hyprland.md](hyprland.md). Local Qt and Quickshell constraints belong beside the affected code. Smoke budgets and execution belong to [validation.md](validation.md).
