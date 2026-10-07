# One shell per session, with one owner for every resource

Read before touching anything that starts, stops, measures or talks to the shell, and before adding a watcher, a poller, a cache or a subprocess.

## The approach

`vgshell run` holds the instance lock, starts the shell as its child and supervises it; every `vgshell` command addresses the pid the lock file names and judges an IPC reply by its text. Inside the shell, every watcher, poller, subprocess and session-wide object has one owner that creates it and destroys it, and a process-costing lookup runs once per set. The choices are [D053](../decisions/D053-runner-holds-the-instance-lock.md), [D069](../decisions/D069-runner-supervises-the-shell.md) and [D047](../decisions/D047-services-build-after-the-first-bar-frame.md).

## Why

A lock descriptor the shell inherits is held by every child the shell starts, so a long download kept the lock after the shell died. Quickshell 0.3.1 re-executes itself in the same pid after a crash signal, so a runner that trusted the exit alone would never see the crash. Two components polling one source cost twice and disagree, and a lookup per item that forks a process makes a scan cost a process per plugin. Quickshell links jemalloc, which purges retained pages lazily, so resident size falls in steps and reports live plus retained data; a rate read over a short span measures the allocator, not the shell.

## Rules

### Process

- Never start a second shell against the live session, and never kill Quickshell processes by name; other Quickshell applications share the seat. Validation runs in the nested sandbox alone.
- Do exit a shell through the runner, never `Qt.quit()` from the root; `Qt.exit` does nothing while the root is still loading. Review holds it.
- Do read the shell's pid from the lock file for every command that contacts it, and exit 69 on no pid, a dead pid or a failed call. `scripts/test-vgshell.sh` pins it.
- Do judge every `qs ipc call` reply by its text through `bin/lib/ipc-reply.sh`; `qs ipc call` exits 0 when the client fails. `scripts/test-ipc-reply.sh` pins it.
- Do answer a reply that grows with the plugin set through `IpcPages`. `scripts/test-ipc-reply.sh` pins it.
- Do send a JSON list argument inside an object, never as a bare list; `qs ipc call` strips the brackets of an argument that opens with `[`. Gap: no check sends a bare list.
- Do check the preflight floor before the lock; a raised floor reaches every package recipe through `scripts/check-packaging.js`.
- Never relaunch, restart or refuse a run from anywhere but the runner's supervision table in `bin/vgshell`; `scripts/test-vgshell-run.sh` and `scripts/smoke/rows/supervise.sh` pin it.
- Do keep the next sentence byte for byte; `scripts/check-readme.js` reads it and holds the README's install text to it. Autostart is `hl.on("hyprland.start", function () hl.exec_cmd("vgshell start") end)` in `hyprland.lua`.
- Never ship a systemd unit for the shell. Review holds it.

### Memory

- Do give every run-time object an owner that destroys it; an object parented to a singleton lives the whole session. `scripts/smoke/leaks.sh` checks what each smoke row leaves; review holds the rest.
- Never hold a cache keyed by data other applications supply without a ceiling. Review holds it.
- Do dispatch or destroy every Wayland object the shell creates; no check holds this, and a long sampled session with `scripts/sample-shell-memory.sh` is the instrument.
- Never state a growth rate over a span shorter than the sampler's floor, and never append a sample to a log whose last row names another session. `scripts/test-sample-shell-memory.sh` pins both.
- Never let the sampler signal, restart or drive the shell; it reads `/proc` alone. Attribution to a C++ class needs a profiled start, which `scripts/attribute-heap-profile.py` explains in its header.

### Performance

- Never let two components poll one source; the owner publishes, the rest read. Review holds it.
- Never run a process-costing lookup per item; `bin/vgshell-scan` reads every manifest in one process.
- Never walk the disk per keystroke; keep one index and cancel a stale query. Review holds it.
- Never sleep unconditionally on an apply path; read, then skip the write when nothing changes. Review holds it.
- Do build no service before the first bar frame. `scripts/smoke/rows/start-order.sh` pins it.
- Do name the tool and the run behind every figure a document or a comment states; a budget without its measurement is a defect. Review holds it.

## The canonical example

`bin/vgshell`'s `run` verb: the preflight, the lock, the migrations, the child started through `setpriv --pdeathsig`, and the supervision table. Copy its shape for any new process the shell depends on.

## Revisit when

Quickshell gives QML a file lock or relaunches after every unclean exit, or Quickshell or Qt signals a layer surface's first presented frame.

## Not governed

What the shell does with Hyprland, which is [hyprland.md](hyprland.md); a Quickshell or Qt fact the code rests on, which is a comment at that code; the smoke's latency budgets, which is [validation.md](validation.md).
