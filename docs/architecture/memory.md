# Runtime memory

Covers: scripts/sample-shell-memory.sh, scripts/test-sample-shell-memory.sh, scripts/attribute-heap-profile.py, scripts/test-attribute-heap-profile.py

Two tools measure VGS's memory: `scripts/sample-shell-memory.sh` samples the shell that `bin/vgsh run` started, and `scripts/attribute-heap-profile.py` reads jemalloc heap dumps from any profiled Quickshell process. This file records where the shell's memory sits, how to measure it, and what a measurement can and cannot attribute. It holds no measured figures: a figure belongs beside the run that produced it. The sampler reads `/proc` and never signals, restarts or drives the shell.

## Vocabulary

- Anonymous memory: pages with no file behind them. The native C++ heap lives here.
- JavaScript heap: the QML engine's garbage-collected heap. It is a `memfd:JSGCHeap:QtQml` mapping, so `/proc/<pid>/smaps` separates it from anonymous memory by name.
- Retained: freed by the program but not yet returned to the kernel by the allocator. Retained pages count toward resident size.
- Transparent huge page: a 2 MiB page the kernel substitutes for 512 small ones. A huge page is resident in full even where the program touched one 4 KiB region of it.

## Where the memory sits

Class shares are read by matching the mapping name in `/proc/<pid>/smaps`. The sampler writes one column per class.

| Class | Matched by |
|---|---|
| Anonymous | no mapping name |
| JavaScript heap | `JSGCHeap` |
| Compiled QML | `JITCode`, `JSVMStack` |
| GPU driver | `nvidia`, `renderD`, `/dri/` |
| Fonts and other files | every other name, including Qt's remaining memfd mappings and the bracketed kernel ones |

## Boundaries

- Quickshell links jemalloc, not the system allocator. `ldd /usr/bin/quickshell` names it. VGS sets no `MALLOC_CONF`, so jemalloc runs on its build defaults and VGS owns none of its tuning.
- jemalloc purges retained pages lazily and only on activity in the arena that holds them. Resident size therefore reports live data plus retained data, and falls in steps rather than smoothly.
- Where the kernel's transparent huge pages are enabled, a retained region that is 2 MiB aligned and large enough is backed by huge pages and counts toward resident size in full.
- Resident size is not a leak measurement. The high-water mark in `/proc/<pid>/status` (`VmHWM`) is the number a session actually reached; the current value can be far below it.

## Invariants

- The sampler states no growth rate over a span shorter than 600 s: `--report` prints `status=span-under-floor` in place of that rate. Enforced by `scripts/test-sample-shell-memory.sh`.
- A sample row names its process and the process's start time, and the sampler refuses to append to a log whose last row names another session. Enforced by `scripts/test-sample-shell-memory.sh`.

## Sampling

```
scripts/sample-shell-memory.sh --hours 26        # log a session
scripts/sample-shell-memory.sh --report FILE     # print the baseline
```

`--samples N` stops after N samples. `scripts/smoke/rows/diagnostics.sh` runs the sampler for two samples against the shell `vgsh run` started in the sandbox and checks both rows name that shell. The sampler asks `bin/vgsh pid` for the shell's pid, the one reader of the lock file `bin/vgsh run` writes while it holds the lock, and confirms that `qs list -p <checkout>/shell -j` lists that pid. A missing or empty lock file, a pid with no process, or a pid the instance list does not name under this checkout's shell is a keyed refusal, so a stale lock or a shell started from another checkout never produces a log. The default log is `${XDG_CACHE_HOME:-$HOME/.cache}/vgs/memory-samples.tsv`.

Every sample row carries the sampled process and its start time, so one session is told from the next that reuses its process id. Sampling refuses to append to a log whose last row names a different session, rather than extending someone else's series. `--report` reads only the newest session in a log and says how many rows and sessions it left out, and it refuses every mark and rate for a session whose uptime does not run forward.

`--report` prints the process high-water mark beside the peak among logged samples, which is lower whenever sampling started after the peak. It prints one `mark=` line for each of 1 h, 8 h and 24 h of uptime and for the last sample. A mark the session never reached is `status=not-reached`. A mark it passed with no sample close enough to answer it is `status=no-sample-within`, so a mark is never filled from a sample hours away. It prints a `rate=window` line over the whole span the log covers, then one `rate=` line between each consecutive pair of marks that both exist. Every rate names the two uptimes it spans, and where a span is under 600 s the line carries `status=span-under-floor` instead of a rate. The window rate is what a log of a session the sampler joined late still reports, since such a log fills only the last mark and one mark forms no pair. Filling all three marks needs a session that starts while the sampler runs.

## Attribution limits

`/proc` says which memory class grows. It does not say which C++ type allocated it. That needs jemalloc's heap profiler, which only runs in a shell started with profiling in its environment. On the live desktop that start is a restart, so no read-only method reaches it. `scripts/qml-smoke.sh` has no option to pass the shell an environment, so no sandbox run is profiled.

`scripts/attribute-heap-profile.py BASE HEAD` reads two dumps from one profiled session. It prints each thread's net growth and share, then breaks one thread's growth down by call stack and by the library that made the allocation. `--thread` selects the thread by name, `WaylandEventThr` by default. It symbolizes through `eu-addr2line` against the dump's own mappings, so the packages on disk must be the ones that ran. The installed libraries are stripped: set `DEBUGINFOD_URLS` so local functions resolve, or they take the name of the nearest exported symbol and the frame row carries `resolution=symbol-table-only`.

The profiler's own bookkeeping is anonymous memory, so resident size in a profiled session is not the shell's growth rate. Attribution reads dump bytes only.

## Rules for plugins

- A plugin holds no cache keyed by data other applications supply without a ceiling: [plugins.md § Budgets](plugins.md#budgets). Notification icons and application names are such keys, since any application can send a new one.
- An object a plugin creates at run time has an owner that destroys it. An object parented to a singleton and never destroyed lives for the whole session.

## Decisions

- The allocator choice belongs to the Quickshell package. The shell sets no allocator tuning.
