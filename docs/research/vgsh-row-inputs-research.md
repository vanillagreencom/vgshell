# Why bin/vgsh selects 28 smoke rows and 41 cli checks

Research for VGS-837. Read-only: no row, check or product file changed.

## Answer

28 smoke rows and 41 `cli` checks name `bin/vgsh` because every sub-command, its help text and its shared helpers sit in that one 2,194-line file, and an input glob names a whole file. 22 of the 28 rows run a vgsh command themselves, edit the file, stand in for it or read output it makes. Two rows, auth-sentinel and read-only-prefix, take all of `bin/*`. Four rows reach it only through the harness: hidpi, network, notices-control and manager. Dropping `bin/vgsh` from those four lines is the smallest change. It needs no split of `bin/vgsh`. On the four measured ranges it saves 0, 1, 2 and 4 rows. A split by sub-command saves no more rows on three of the four ranges, because their `bin/vgsh` hunks sit in code every sub-command shares.

## Method

- **Selection.** A Python copy of `smoke_rows_selected` in `scripts/validate` read each range's row lines, row list, harness line and tracked files at the range's head. It reproduces the published counts: 73, 40 and 50 rows with harness paths ignored for VGS-806, VGS-810 and VGS-808, and 43 rows for VGS-776, which `scripts/validate --list --changed 133c19ec7` printed as `smoke-rows=some selected=43 total=80`.
- **Seconds.** `tmp/lane-evidence/VGS-808/vgs-808-restack-qml-rows.last` on the overseer's host, an all-row run at 3a8e725c7. A row's time is the gap from the previous row's result stamp to its own, so the `updates-traceback-*` stamps count to `updates` and `jarvis-bubble` to `jarvis-keys`. The stamps run in `rows.list` order. `bar` is the first stamp, and `plugin-pages` and `auth-sentinel` have none, so these three rows have no time and no figure below includes them. The 77 timed rows total 1,828.2 s.
- **Usage.** Read from each row's code, the harness functions it calls and the shell code it drives.

## What the harness runs for every row

The harness runs `bin/vgsh` for every row: `start_shell` runs `vgsh run` and `vgsh pid`, and `ipc` runs `vgsh ipc call`. Every shell start then runs `vgsh hypr state` (`shell/Core/HyprlandLayer.qml`) and, at the end of each scan, `vgsh theme follow` (`shell/Core/ThemeRunner.qml`). `bin/vgsh` stays off the harness line by design ([validation-runner.md § Method](../architecture/validation-runner.md#method)): the core rows make these calls on every run that selects the smoke, so a break in them fails the core rows. The `nested smoke` row of the `qml` area selects on `bin/*`, so any `bin/vgsh` change starts the smoke with the core rows and the rows they name: bar, hyprland-consent, plugins, capabilities, session, start-order and auth-sentinel.

## Smoke rows that name bin/vgsh

"Own use" is what the row runs beyond the harness calls above. Seconds are from the VGS-808 run.

| Row | Own use of bin/vgsh | Helpers it reaches | s |
|---|---|---|---|
| auth-sentinel | none; its `bin/*` glob covers every writer that could reach sudo (core row) | all of `bin/*` | none |
| configuration | `plugin list` | vgsh-plugin-judge | 0.5 |
| devtools | `doctor --json`; the devtools plugin runs `doctor`, `self status`, `pkg check` | vgsh-scan, vgsh-plugin-judge, vgsh-pkg | 31.5 |
| diagnostics | `pid`, through `scripts/sample-shell-memory.sh` | none | 1.2 |
| hidpi | harness only | none | 19.5 |
| hyprland-consent | Connect makes the shell run `hypr wire` (core row) | vgsh-hypr-judge | 1.3 |
| hyprland-consent-decline | `hypr unwire`, `hypr render` | vgsh-hypr-judge | 11.9 |
| hyprland | `theme apply`, `hypr render`, `hypr unwire`, `hypr wire` | vgsh-hypr-judge, vgsh-theme-judge | 10.0 |
| instance-guard | `theme apply` | vgsh-theme-judge | 3.9 |
| lock | `lock` | vgsh-lock | 18.8 |
| manager | harness only; asserts TUI argv text naming `vgsh plugin update`, `remove`, `add`, which the stand-in terminal records and replaces with `true` | vgsh-tui | 22.1 |
| network | harness only | none | 13.1 |
| notices-control | harness only, in a copied tree | none | 1.2 |
| notices | `plugin add`, `plugin remove --yes` | vgsh-pkg, vgsh-scan | 5.9 |
| overlay-capture | the theme browser's cards come from `theme catalog` | vgsh-theme-judge | 21.6 |
| plugin-pages | `plugin list`, a paged reply through vgsh's internal `ipc` | vgsh-plugin-judge, lib/ipc-reply.sh | none |
| plugins | `plugin add`, `plugin list` | vgsh-scan, vgsh-plugin-judge | 8.7 |
| read-only-prefix | installs the tree and starts the installed `vgsh run` | all of `bin/*` | 6.3 |
| sound | edits the runner's `QS_PIPEWIRE_IMMEDIATE_RECONNECT` line in a copy | none | 41.6 |
| start-order | `restart`; edits the runner's `exec qs` line in a copy (core row) | none | 37.9 |
| supervise | edits the runner's relaunch and give-up lines in two copies | none | 34.4 |
| system-steps | `system apply` | vgsh-system | 2.9 |
| theme-browse | stands in for bin/vgsh; the shell runs `theme catalog`, `install`, `images`, `set`, `wallpapers`, `preview` | vgsh-theme-judge, lib/theme-* | 16.4 |
| theme-browser | `theme catalog --json`, `theme apply`, `theme background set`; stands in for bin/vgsh | vgsh-theme-judge, lib/theme-* | 51.0 |
| theme-latency | stands in for bin/vgsh; `theme apply` | vgsh-theme-judge | 22.5 |
| themes | stands in for bin/vgsh; `plugin enable`, `theme apply`, shell theme jobs | vgsh-theme-judge, lib/theme-* | 79.1 |
| tui | `tui open` | vgsh-tui | 5.1 |
| updates | a wrapper runs `pkg check`, `self status`, `plugin outdated`, `theme outdated` | vgsh-pkg, lib/self.js | 29.1 |

## Command-line checks that name bin/vgsh

41 rows of the `cli` area match `bin/vgsh`. 18 of them use the glob `bin/vgsh*`, which also matches every `bin/vgsh-*` helper: a change to `bin/vgsh-lock` selects 24 rows of the table, 18 of them through that glob.

| Check | Own use of bin/vgsh |
|---|---|
| devtools engine | none; the engine checks that `bin/vgsh` exists as the tree marker |
| automations engine | the engine runs `plugin settings` |
| plugin settings controls | `plugin settings` |
| runner CLI controls (`*`) | `plugin add`, `update`, `remove`, `enable`, `disable`; `theme add`, `update`, `remove`, `list`, `apply`; `run`; `ipc` |
| runner lifetime controls | `run`, `restart` |
| one-time migration runner controls | `run`, `migrate` |
| version controls | `version`, `--version` |
| install tree controls | installs `bin/*`; `--version`, `run` |
| fedora source RPM controls | `--version` in a fixture tree |
| packaging recipe check, and its controls | reads the `preflight_floor` table text |
| README install section check controls | reads the quickshell floor line |
| README install runner host-side controls | copies the file into the scratch tree the README check reads |
| plugin list controls | `plugin list`; a control edits the paged `ipc` function |
| add and remove question controls (`*`) | `plugin add`, `plugin remove` |
| requirement report controls | `plugin requirements`, `plugin rescan`, `doctor` |
| self status and update controls | `self status`, `self update` |
| curl installer controls | `self status`, `pkg detect`, `pkg plan`, `run`, `--version` |
| AUR publisher controls | runs the packaging recipe check, which reads the floor table |
| outdated controls (`*`) | `plugin outdated`, `theme outdated`, `plugin add`, `theme add` |
| theme reload, target, package symlink, entry wiring, toolkit, editor, editor entry, chat and tool, agent CLI controls (`*`) | `theme apply`, with `reload`, `follow` or `list` in some |
| Hyprland layer wiring controls (`*`) | `hypr wire`, `state`, `unwire`, `render` |
| browser target controls (`*`) | `theme setup`, `reload`, `browser-policy`, `apply` |
| theme background, follow, catalog install, wallpapers controls (`*`) | `theme background`, `follow`, `install`, `update`, `remove`, `catalog`, `outdated`, `wallpapers`, `preview`, `apply` |
| passwordless sudo grant controls | `sudo` sub-commands, through vgsh-sudo-grant |
| system steps controls | `system status`, `apply`, `undo`, through vgsh-system |
| floating TUI presenter controls | `tui present`, `open`, `list` |
| vgsh lock controls | `lock` |
| vgsh pkg check owner and command rows | `pkg plan`, `pkg check`; controls edit a copy |
| vgsh pkg run and pickers | vgsh-pkg's run ends with `plugin rescan` |

Five more rows outside `cli` match `bin/vgsh`: `user command text` and its controls read the text of `bin/*`, `memory sampler report` runs `pid` on a copy, and `nix flake package` and `nested smoke` select on `bin/*`.

Every `cli` check but the devtools engine runs a vgsh command or reads the file's text. Narrower lines therefore move one check at most: 42 to 41 for VGS-806 and VGS-776, and no change for VGS-810 (45) and VGS-808 (44), where other files also select the devtools engine. No per-check seconds were read.

## What each range changed in bin/vgsh

| Range | bin/vgsh hunks | Code that runs them |
|---|---|---|
| VGS-806 b7b4ad270..829eebfb4 | `rescan_if_running` | `plugin add`, `update`, `remove`, `rescan` |
| VGS-810 5c9e08a7e..a9934a144 | the internal `ipc` function, split into `ipc_call` and `ipc` | every sub-command that calls the shell |
| VGS-808 1f39ae4d2..3a8e725c7 | `ipc_call`, `shell_restart`, the `ipc` sub-command | every shell call, `restart`, the harness's `ipc call` |
| VGS-776 133c19ec7..330329460 | two help-text hunks (lines 2 to 394 are the help `vgsh --help` prints) and three comment hunks near `graphical_session` and `plugin_scan` | help output; no behaviour |

VGS-806, VGS-810 and VGS-808 also changed `scripts/smoke/harness.sh`, so each ran all its rows whatever the row lines said.

## Selection per range

Rows and seconds of the smoke. "Harness ignored" drops the harness's inputs from the changed paths. "Four rows narrowed" also drops `bin/vgsh` from the lines of hidpi, network, notices-control and manager. "Split" assumes `bin/vgsh` split by sub-command, with the changed hunks reaching only the rows named. "No bin/vgsh" drops the path from the change: the floor any narrowing of `bin/vgsh` can reach.

| Range | Actual | Harness ignored | Four rows narrowed | Split | No bin/vgsh |
|---|---|---|---|---|---|
| VGS-806 | all 78 | 73, 1,362.9 s | 73, 1,362.9 s | 71, 1,306.1 s | 70, 1,305.6 s |
| VGS-810 | all 80 | 40, 711.5 s | 39, 710.3 s | 39 (shared code) | 24, 455.0 s |
| VGS-808 | all 80 | 50, 1,097.5 s | 48, 1,083.2 s | 48 (shared code) | 33, 856.7 s |
| VGS-776 | 43, 760.4 s | 43, 760.4 s | 39, 578.4 s | 29, 406.2 s | 25, 332.0 s |

- **Four rows narrowed** drops notices-control from VGS-810; network and notices-control from VGS-808; hidpi, notices-control, and the notifications and notifications-keys rows hidpi's line names, from VGS-776 (182.0 s).
- **Split, VGS-806** puts `rescan_if_running` in a plugin file named by configuration, plugin-pages, plugins, notices and themes.
- **Split, VGS-810 and VGS-808** changes nothing: their hunks are the IPC code every sub-command and the harness use, so the shared file stays on the same lines.
- **Split, VGS-776** needs the help text in its own file and the commented code in a doctor file named only by devtools. With the moved `plugin_scan` comment in shared code it stays at 39 rows.

## Narrower files with no split

A glob names a file, never a part of one, so a row cannot name "the IPC part" of `bin/vgsh`. Rows that run a sub-command run the dispatcher, the help text and the shared helpers in the same file, so they keep `bin/vgsh`. The four harness-only rows can drop it: the core rows make every call they make. overlay-capture keeps it: it reads `theme catalog` output. diagnostics keeps it: it runs `pid` itself. Separately, the 18 `bin/vgsh*` checks could name `bin/vgsh` and the helpers they run; that changes nothing on these four ranges, since each changed `bin/vgsh`.

## Cost of a split

- **Files.** One dispatcher plus one file per sub-command group, sourced as `bin/lib/ipc-reply.sh` is. Each new file joins `packaging/install-tree.manifest` and the install tree check.
- **Lines to rewrite.** The 28 row lines and 41 check inputs, plus every edit and stand-in that targets the file: supervise, sound and start-order edit runner lines in place, and themes, theme-browse, theme-browser, theme-latency and updates stand in for or wrap it.
- **Docs.** `docs/architecture/runtime.md` and validation-runner.md describe the runner as one file.
- **Payoff.** On the four ranges it saves 2 rows beyond narrowing on VGS-806, which ran all rows anyway, none on VGS-810 or VGS-808, and 10 on VGS-776 only with the help text also moved out. Shared code stays on every line that runs a sub-command.

## The inputs check after the change

`smoke_reads_check`, the `smoke rows name the rows they read` row of `validate tools`, holds row-to-row reads only: a function or variable a row takes from another row's file. After the change it still holds the row files the four lines name, such as network's `start-order.sh` and `overlay-capture.sh` and hidpi's `notifications.sh`. It does not read product paths. It would not report a row that runs `"$repo/bin/vgsh" theme apply` without naming `bin/vgsh`, nor a row that names `bin/vgsh` and never runs it. That is true today. The smoke controls in `scripts/test-validate.sh` use fixture rows, and its one `bin/vgsh` plan reads the offline floor checks, so neither changes.

## Text the change would amend

- **D100**, Decision, "A harness change runs every row", second sentence. Now: "A product file the harness copies or edits goes on the line of each row that exercises it; the core rows catch a break that stops the shell starting." Amended: a product file the harness copies or edits goes on the line of each row that runs one of its commands itself, edits it, stands in for it or reads its output; the harness's own `vgsh run`, `pid` and `ipc call`, and the `hypr state` and `theme follow` every shell start runs, go on no row's line, since the core rows make them on every run that selects the smoke.
- **validation-runner.md**, § Method, "Every smoke row", the sentence "A product file the harness copies or edits, `bin/vgsh` among them, goes on the line of each row that exercises it, not on the harness line: the core rows catch a break that stops the shell starting." Amended the same way.
- **validation-runner.md**, § Method, "Smoke input self-check": one added sentence, that the scan reads no product path, so a row's product inputs are its author's to name.

## Recommendation

Drop `bin/vgsh` from the input lines of hidpi, network, notices-control and manager, and amend the three sentences above. Do not split `bin/vgsh`. Add no check.
