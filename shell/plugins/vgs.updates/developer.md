# Updates developer reference

## Sources

The service runs this command with argv only:

```text
bin/check --vgshell <absolute path to vgshell>
```

`bin/check` refuses when `--vgshell` is missing or is not an executable absolute path.

The script holds this lock for the whole check:

```text
${XDG_RUNTIME_DIR}/vgshell/updates/check.lock
```

It starts these read-only commands concurrently, each in its own process group:

- `vgshell pkg check --json`: system packages, AUR, Flatpak and mise tools.
- `vgshell self status --json`: the VGS checkout, package, Nix install or curl install.
- `vgshell plugin outdated --json`: installed plugin git checkouts.
- `vgshell theme outdated --json`: installed theme git checkouts and catalog installs.

TERM, INT or HUP to `bin/check` sends TERM to every probe's process group and waits for each probe to exit. A probe starts with SIGINT ignored, as every background job of a shell without job control does, so TERM is the signal each probe acts on. A probe ends its own git fetch before it exits: [manager.md § Outdated](../../../docs/architecture/manager.md#outdated).

It writes this file atomically:

```text
${XDG_STATE_HOME}/vgshell/updates/status.json
```

The status file has this shape:

```json
{ "checkedAt": 1790650695194, "sources": [], "error": null }
```

`checkedAt` is whole milliseconds since the Unix epoch.

`sources` is a list of source rows. Each row is `{ source, label, count, packages, checkedAt, error }`. A failed source stays visible with `count: null` and its reason in `error`.

The shared status value bounds `packages` to twelve rows per source. A shared source row adds `more` with the number of package rows omitted. Package `name`, `old` and `new` text is cut to eighty characters in shared status. The full package list stays in `status.json`.

`error` is null in every file `bin/check` writes: each probe's failure is its own source row. A check that fails before it writes leaves the last good file unchanged, and the service reports that failure in `checkState`. The service still reads a non-null `error` as a failed check.

## Counts

The badge counts every source, because it represents the whole system.

Package-manager rows count packages.

VGS counts as one update when `vgshell self status --json` reports `behind: true`.

Plugins and themes count one update per checkout or catalog package that is behind. Their package rows keep the commit count as `behind` for the window.

An installed directory that is not its own git checkout, such as a copied plugin, has no upstream and `vgshell plugin update` refuses it too, so it is not an update source and is left out.

A checkout whose fetch failed names itself in the source's `error`; the other checkouts still count.

## Cadence

The default check interval is six hours.

The service publishes the cached snapshot at startup. It checks at startup only when the cache is older than the interval. It schedules the next check from `checkedAt`.

It accepts an on-demand check over IPC:

```text
vgshell ipc call vgs.updates invoke check ''
```

It checks again when one of its own TUI runs records a new end in `shell.tui.state` after the service started, except the review's, which runs inside an update run. A service rebuilt after a run does not check again for it.

A cache older than twice the interval reports a stale check state.

A check process failure keeps the last good snapshot and reports a danger state. After a process failure, the service retries after five minutes.

Only one check process runs at a time. A second request while a check runs queues one more check.

## Status values

The service publishes these status keys:

- `pending`: total updates with numeric counts.
- `lastCheck`: the last successful snapshot time.
- `checkState`: `ok`, `info`, `warning` or `danger`, with a short reason.
- `checking`: whether a check process runs. It is the widget's spinner, since `info` also means "not checked".
- `sources`: the source rows for the bar widget and the window.
- `reviewAgent`: the agent that reviews third-party packages, in words: its name, `Custom:` and the edited command's first word, that the chosen agent is not installed, `None found`, or `Off`.
- `reviewAgents`: the agents found on `PATH`, the choices of the `reviewAgent` setting.

The Settings page shows `pending`, `lastCheck`, `checkState` and `reviewAgent` as read-only status. `checking` and `sources` are data for the widget and the window.

The service finds the agents with `bin/facts agents` when it starts, after each check and when its settings change.

## IPC

`check` starts a check. It returns `started` or `queued`. The window's Refresh reaches the same handler through `shell.ipc.call("check", "")`, so the service stays the one owner of every probe.

`status` returns the values currently published through plugin status.

`review <dir>` opens the `review` TUI for an update run's review directory and returns `shell.tui.run`'s answer. When the run ends it writes `<dir>/ended`: [pipeline.md § Third-party review](pipeline.md#third-party-review).

## Privacy and network

The service does not send data itself. The commands it runs can touch the network:

- `vgshell pkg check --json` can use `checkupdates`, Flatpak remotes and mise registries.
- `vgshell self status --json` can fetch the VGS upstream or query the GitHub release API.
- `vgshell plugin outdated --json` fetches installed plugin git upstreams.
- `vgshell theme outdated --json` fetches installed theme git upstreams.

The shell never elevates for a check.

## Bar widget and window

The widget and the window read the status values alone. `UpdatesLogic.js` decides what each draws, and neither runs a check.

The widget has five states:

| State | When | Draws |
|---|---|---|
| Current | The last check succeeded and nothing waits. | The calm `refresh-cw` icon in the bar's colour, with no badge. |
| Pending | The last check succeeded and updates wait. | The icon and a count badge in the accent tone. |
| Attention | The check failed, a source failed, or the snapshot is older than twice the interval. | The `triangle-alert` icon and the count in the warning tone. |
| Checking | A check process runs. | A spinner in place of the icon, with the last count. |
| Unchecked | No check has published a state yet. | The calm `circle-dashed` icon. |

The count badge shows at most `99+`. The tooltip lists the state, each source's count and the time of the last check.

A left click opens or closes the Updates window, a Hyprland window like any other: Hyprland draws its border and moves it, and Escape closes it. The global shortcut `vgs.updates:toggle`, bound to `SUPER+CTRL+U` by default, opens or closes the same window. A middle click opens the `update` TUI for every source; the window's Update everything button is its keyboard path.

The window has one row per source, in the order the service publishes them. It opens with keyboard focus on the first source row. Each row shows its count badge and its error, if it has one. A source with updates has its own Update, which opens `update-source` with the row's source. A click or Space on a row lists its packages as `name old → new`, or `name: N commits behind` for a plugin or theme. The list holds the twelve packages the shared status keeps and a `+N more` line for the rest.

Update everything opens `update`. The footer has Refresh, the time of the last check, and Open last log. Open last log opens the `log` TUI, `tui/log.sh`. It shows the last run's log in `less -R`, from its end, and names the path when no run has written a log. The window has no command text field.

The widget is always visible by default. `hideWhenCurrent`, off by default, hides it only in the current state. A hidden icon would make "up to date" look the same as "never checked" or "check failed", and the widget is also the way to Refresh and to the time of the last check. A failed, stale, running or missing check always shows, with `hideWhenCurrent` on too.

## Third-party review

Before an update installs packages from outside the distribution's official repositories, an AI agent reviews them for supply-chain risk. On Arch these are AUR packages and packages from a pacman repository other than `core`, `extra`, `multilib` and the CachyOS repositories. The agent runs in a second window. When it is done, it tells the user to close the window, and the update continues.

The update installs what the review allows. A flagged package asks the user to skip it or stop the update. A review that ends without a result asks whether to continue without a review or stop, and stops by default. The agent installs nothing and never gets administrator access. The default commands run the agent in a restricted mode: it asks before it runs a command and writes only in the review directory. An edited command runs as written.

The settings, in the Update options group:

- `reviewThirdParty`, Review third-party packages, on by default.
- `reviewAgent`, AI agent: Claude Code or Codex, from the agents found. Empty takes the first one found, Claude Code first.
- `reviewCommand`, Review command: Automatic runs the agent's default command, and an edited command runs as written. The review instructions, `review/third-party.md`, follow as its first prompt.

With no agent found, the setting does nothing, the `reviewAgent` status says so, and updates install without a review. [pipeline.md § Third-party review](pipeline.md#third-party-review) holds the steps.
