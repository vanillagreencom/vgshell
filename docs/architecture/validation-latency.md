# Smoke latencies

Covers: scripts/smoke/rows/diagnostics.sh, scripts/smoke/rows/start-order.sh, scripts/smoke/rows/notifications.sh, scripts/smoke/rows/supervise.sh, scripts/smoke/rows/lock.sh, scripts/smoke/rows/theme-latency.sh, scripts/smoke/ThemeLatencyProbe.qml

The latencies and the resident size the nested smoke reads, their ceilings and budgets, and the compositor state they are read under. The sandbox and its harness are in [validation-smoke.md](validation-smoke.md).

## Theme browser

The theme browser row reads a window's first presented frame after a physical key. Its warm endpoint requires keyboard focus, the complete retained installed and catalog list, and ready images on every visible card. It polls its small IPC reading back to back. The timestamp comes from the window's frame callback, before the observer inspects its items. Theme apply ends after the browser closes, on a desktop frame with the requested theme published, a new bar frame and a frame with the requested background ready when the theme has one. Wallpaper set ends after the browser closes, on the first background frame with the requested image ready. The observer retains requested desktop frames drawn under the browser. It completes on a native desktop frame after the browser closes and reads the requested background's live readiness. The probe requests that frame when the unchanged desktop needs no repaint. The row's actual-reader controls reject an open browser, an unpresented wallpaper, a wallpaper that loses readiness and a missing selected picture during held keys.

On host cachy on 2026-10-04, with compositor logs on, six warm opens read 112, 120, 97, 98, 88 and 97 ms. Load was 11.95 and CPU pressure was 0.3 to 1.4%. Pressure covers the sender and IPC observation window, which was 209 to 469 ms, rather than the shorter frame timestamp window. Cold installed open read 112 ms while catalog completion was held. `scripts/smoke/rows/theme-latency.sh` holds a 240 ms warm ceiling, twice the highest sample, under the VGS-757 owner ruling. The original 100 ms target remains unmet. The row rejects a synthetic reading one millisecond over each ceiling. It also holds keys and checks image readiness, and exercises retained-catalog arrival, package changes and the service timer without moving the selection.

The theme-change row takes six readings from physical keypress to the exposed desktop showing the requested ready background. Their median must be at or under 150 ms. Each reading must be at or under 292 ms. The owner ruling, ask `1791136884-3060298-761` answered on 2026-10-04, holds the desktop target with the median and keeps the single-reading ceiling to detect a slowdown under fleet load. Independent controls reject a median over 150 ms with all readings under 292 ms, and a reading over 292 ms with the median under 150 ms. Wallpaper keeps its 150 ms limit.

The corrected exposed-desktop reader on `6bf3f02f4` measured a theme change at 182 ms: queued at 11 ms, answered at 138 ms, published at 154 ms, uncovered at 158 ms, bar frame at 162 ms and background frame at 182 ms. A disposable instrumented copy of that main tree, run with `scripts/qml-smoke.sh --rows theme-latency,hyprland-consent,device-fakes --keep` through the fleet slot on cachy on 2026-10-04, read 136, 137, 124, 107, 129 and 114 ms at load 4.87 to 5.20 and CPU pressure 0.3 to 0.9%. An earlier baseline read 223, 102, 100, 101, 124 and 98 ms at load 6.66 to 6.72 and CPU pressure 0.4 to 3.4%. These baselines retain individual readings above the owner's desktop target.

The same scoped command after the apply cost fix read 140, 124, 123, 91, 128 and 92 ms at load 7.41 to 7.46 and CPU pressure 0.3 to 1.2%. Its observation windows were 338 to 345 ms, with compositor logs on. Wallpaper read 92 ms. The disposable copy logged apply stages to a temporary measurement file; production keeps no new process or cache. The first before and after readings had these offsets from keypress:

| Stage | Before, ms | After, ms |
|---|---|---|
| Queued | 11 | 11 |
| Process start | 12 | 12 |
| Node entry | 31 | 32 |
| Modules loaded | 53 | 49 |
| Package judgment complete | 71 | 59 |
| Target files and shell file written, reload complete | 72 | 61 |
| Process finished | 96 | 68 |
| Answered | 99 | 71 |
| Published | 88 | 86 |
| Browser uncovered | 102 | 89 |
| Bar frame | 134 | 126 |
| Ready background frame | 136 | 140 |

Further runs of the same scoped command after the apply cost fix on cachy on 2026-10-04 took twelve readings at load 3.2 to 3.5. Their minimum, median and maximum were 89, 108 and 132 ms. Selected validation at load 8.59 to 8.64 and CPU pressure 0.3 to 0.8% read 171, 93, 158, 116, 108 and 121 ms. Both sets meet the owner ruling. The first fleet-load reading had queued at 11 ms, answered at 103 ms, published at 128 ms, uncovered at 132 ms, bar frame at 147 ms and ready background at 171 ms. The third had queued at 14 ms, answered at 103 ms, published at 89 ms, uncovered at 106 ms, bar frame at 156 ms and ready background at 158 ms. Wallpaper read 107 ms.

Module initialization read 22 ms before and 17 ms after. Package judgment read 18 ms before and 9 ms after. Apply now loads no downloader and reads only the selected package and its shipped fallback; the source-root, selected-package and target checks remain. The row holds the owner ruling above; frame times vary with scheduling.

- A row that waits for a floating TUI's run to end calls `expect_run_end` in `scripts/smoke/harness.sh`. It polls `key_idle`, the core's view of the key, every 0.2 s until the key reads `idle` or `run_end_ceiling_ms` has passed, and prints each wait as `latency_run_end_ms`. An `idle` read that ends past the ceiling fails too. The ceiling bounds the chain from the presenter's exit to the core's runs, and the harness names the runs that measured it. A key still busy at the ceiling fails and prints the key's record files beside the core's view, so an ended record on disk that the core never listed reads as a missed listing ([runtime-qml.md](runtime-qml.md)), not as a slow run. The requirement notice's rows wait the same way, through `expect_within`, for the scan after an install run. `scripts/smoke/rows/tui.sh` holds the controls: a gated run held live past the ceiling never ends in time, and `expect_run_end` fails on it; a read that answers `idle` only past the ceiling fails `expect_within`.
- The first-bar reading, `first_bar_ms`, which `start_shell` in `scripts/smoke/harness.sh` takes, is the time from the runner's spawn to the first `vgs:bar` layer with a client in the nested compositor's layer list, polled every 10 ms. The sandbox's cache directory starts empty, so every reading is a start with no compiled QML cache. `scripts/smoke/rows/diagnostics.sh` prints it as `latency_first_bar_ms`, beside `cpu_some_pct`: the percent of the same window in which some runnable task on the host waited for a CPU, from the `some` totals of `/proc/pressure/cpu`. The record reads pressure stall information because the load average also counts tasks running on a CPU and tasks in uninterruptible sleep, so a host with many CPUs can show a high load while no task waits. The record is not a gate: a reading over the budget fails at any pressure. `scripts/qml-smoke.sh --first-bar-runs N` starts the sandbox N times with no row and prints each reading and the highest. The budget is twice the highest reading of such runs; the header of `scripts/qml-smoke.sh` names the runs, the host and the pressure they read.
- The default set has its own first-bar reading. `--first-bar-runs N --plugin-set default` starts every first-party plugin, as a live session does, and each run line carries the service gate's release and `waited_ms` ([D047](../decisions/D047-services-build-after-the-first-bar-frame.md)). `scripts/smoke/rows/start-order.sh` restarts the sandbox over the default set with no compiled QML cache and reads the same latency against `VGSHELL_SMOKE_DEFAULT_FIRST_BAR_BUDGET_MS`. Readings on host cachy on 2026-09-29, 12 runs a pass, one start a pass lost to an unsized nested monitor, `cpu_some_pct` at most 1.3 in every pass:

  | Tree | Plugin set | Load | Readings, ms | Highest, ms |
  |---|---|---|---|---|
  | `92d71ba3`, no gate | default | 6.8 to 7.1 | 307 to 344 | 344 |
  | `92d71ba3`, no gate | smoke | 7.1 to 7.9 | 215 to 281, 12 of 12 | 281 |
  | with the gate | default | 6.7 to 8.1 | 226 to 271, `waited_ms` 137 to 179 | 271 |
  | with the gate | default | 4.0 to 6.1 | 206 to 238, `waited_ms` 124 to 139 | 238 |
  | with the gate | smoke | 4.0 to 6.1 | 206 to 256, `waited_ms` 106 to 134 | 256 |
  | the gate released one deferred call after the scan | default | 5.5 | 288 to 330, 12 of 12 | 330 |
  | every bundled widget placed (VGS-846), 2026-10-05, two passes of 6 | default | 11 to 15 | 553 to 713, 12 of 12 | 713 |
  | `origin/main` at `d1ff7b3`, the same day, interleaved, two passes of 6 | default | 11 to 16 | 363 to 467, 11 of 12 | 467 |

  The default set's budget is twice the highest of the two VGS-846 passes, 1426 ms, each a pass whose runs all read `cpu_some_pct` at most 1.3; the service gate's deadline is twice the highest `waited_ms` of all three passes with the gate, 358 ms. The smoke set's 620 ms budget still holds.
- `scripts/smoke/rows/notifications.sh` reads two latencies with Slack custom emoji, each once: `latency_emoji_toast_ms`, from the notify call for a card whose body holds six emoji to its body naming the images on every screen, and `latency_emoji_inbox_ms`, from the history call to forty panel rows naming their emoji images on the visible cards. The toast reader counts the image texts of the measured card alone: the layers can still hold the items of dismissed emoji cards when a new card arrives, and their texts would end the reading before the card draws. The inbox reader counts the image texts in the panel and returns only the count, because reading the full `rows` array moved 39,344 characters through the smoke IPC on every poll and added 516 to 565 ms after the panel had already drawn. Each reader polls the probe back to back, one smoke IPC round trip a poll. A round trip cost about 22 ms when the budgets were read, and 27 to 65 ms on 2026-10-05 beside two and three other nested runs. Each latency line prints `cpu_some_pct` for its window, as the first-bar record does. Each reader fails over `VGSHELL_SMOKE_EMOJI_TOAST_BUDGET_MS` or `VGSHELL_SMOKE_EMOJI_INBOX_BUDGET_MS`, twice the highest reading named below. The panel builds all forty rows when it opens, so scrolling it moves built rows and adds no card work; the harness has no wheel input, so scroll frames are not read. Readings on host cachy on 2026-09-29, one nested monitor, load 4 to 7, by an uncommitted copy of the row's procedure run under the smoke harness over each tree; `origin/main` at `409efdb5` has no emoji, so its card is read when it is listed:

  | Tree | Reading | Toast, ms | Inbox of 40, ms |
  |---|---|---|---|
  | `origin/main` | card listed | 43 to 87, median 46 to 49 | 93 to 120, median 100 to 104 |
  | branch | card listed | 44 to 72, median 46 to 48 | 98 to 135, median 103 to 111 |
  | branch | emoji named in the body | 43 to 61, median 45 to 46 | 101 to 114, median 110 to 113 |
  | branch, full smoke, four runs | emoji named in the body | 35 to 37 | 88 to 102 |
  | VGS-674, the probe counts, 14 runs of the row on 2026-09-30, load 4 to 8 | emoji named in the body | 43 to 50 | 79 to 95 |
  | `vgs-597-keyboard-first`, summoned panel with full `rows` readback, one run with three summons on 2026-09-30 | rows present | 88 | 667 to 750 |
  | `vgs-597-keyboard-first`, summoned panel with image-count readback, two full-smoke readings on 2026-10-01, load 5.58 to 8.80 | emoji named in the body | 77 to 78 | 651 to 688 |

  The earlier rows read the whole text item list on every poll, about 108,000 characters for the inbox. The summoned-panel regression came from reading the full `rows` array on each poll, after the panel's first frame already had the forty rows. The budgets come from the VGS-674 toast row and the image-count summoned-panel row: the toast budget is 100 ms and the inbox budget 1376 ms.
- Two readings follow a SIGKILL to the shell, each held under a ceiling in its row ([D069](../decisions/D069-runner-supervises-the-shell.md)). `scripts/smoke/rows/supervise.sh` prints `latency_relaunch_ms`, from the kill to the runner's new shell answering ping, polled every 50 ms on the lock file and every 200 ms on ping; `relaunch_budget_ms` is 1514. `scripts/smoke/rows/lock.sh` prints `latency_lock_back_ms`, from a kill while locked to the new shell's confirmed lock with its lock screen, polled every 50 ms; `lock_back_budget_ms` is 3212. Each budget is twice the highest of six readings of its row on host cachy on 2026-09-30, at load average 5 to 8: 733 to 757 ms and 1497 to 1606 ms. Both hold the runner's first delay, 0.5 s.
- The resident-size ceiling, `VGSHELL_SMOKE_RSS_CEILING_KIB`, holds the largest resident size of the shells the run starts up to `scripts/smoke/rows/diagnostics.sh`. `shell_memory_note` in `scripts/smoke/harness.sh` reads `VmRSS` and `VmHWM` of the shell from `/proc/<pid>/status` and prints them as `rss_kib` and `hwm_kib` with the shell's pid and the row that read them. `stop_shell` calls it before its TERM, so a shell a row replaces is read at its end, and the diagnostics row calls it for the shell it finds. That row prints the largest reading as `rss_peak_kib` with its row, fails when it is over the ceiling, and fails when a shell the run started was never read. A reading a stop takes after the diagnostics row is printed and not judged. The row holds the controls: a reading one over the ceiling reads `over`, no reading reads `unread`, an earlier shell's larger reading stays the largest, and a started shell that no note read is named. `scripts/smoke/rows/notifications-keys.sh` stops and starts the shell, so the run's first shell ends there and is read at that stop: one run over a tree on `main` at `387cdc26e` read it at 542368 KiB, and the shell the diagnostics row finds at 336708 KiB. `7bb195940` held no notifications-keys row and a monitor-preview row that stopped and started the shell five rows before the diagnostics row, so in the three runs below the largest reading is the shell that ran the rows up to that row's first stop, and the shell the diagnostics row found read 321540 to 350548 KiB. Readings of `scripts/qml-smoke.sh` on host cachy on 2026-10-02, one nested monitor, over `main` at `7bb195940` with these readers:

  | Run, UTC | Nested compositors at start | Load at start | `rss_peak_kib` | Its `hwm_kib` | Diagnostics shell, `rss_kib` |
  |---|---|---|---|---|---|
  | 20:36 to 21:01 | 2 | 5.16 | 581348 | 734360 | 325164 |
  | 21:01 to 21:25 | 1 | 12.19 | 587008 | 725580 | 336180 |
  | 21:25 to 21:50 | 2 | 8.55 | 576964 | 735192 | 328608 |

  The ceiling is twice the highest of the three, 1174016 KiB. The largest reading grows with the rows the run holds, with no step at one landing. One run of each older tree on the same day, where the diagnostics row reads the shell that ran every row before it:

  | Tree | Rows the read shell ran | `rss_kib` | `hwm_kib` |
  |---|---|---|---|
  | `007788d11`, `main` on 2026-09-29 | 32 | 479500 | 625596 |
  | `d00aa26c4`, `main` on 2026-09-30 | 40 | 505416 | 730712 |
  | `24885a7ef`, a lane's tree over `main` at `27e853976` on 2026-10-01 | 51 | 578304 | 745560 |
  | `7bb195940`, the three runs above | 49 and the start of its monitor-preview row | 576964 to 587008 | 725580 to 735192 |
- The nested compositor starts with its logs off: logging every surface slows the first bar, whose median over five interleaved startups of the harness on host cachy on 2026-09-29, at a load of 5 to 6, read 260 ms with the logs on and 244 ms with them off. Once `scripts/smoke/rows/bar.sh` has read the startup latencies, `compositor_logs_on` creates the flag file the harness's `hyprland.lua` reads and reloads the configuration, so `hyprctl rollinglog` holds each cursor shape the shell sends from then on ([runtime-pointer.md](runtime-pointer.md)). The `hyprland.log` the verdict reads therefore holds the lines logged before the configuration first loaded and every line from that reload to the end, but not the bar rows between.
