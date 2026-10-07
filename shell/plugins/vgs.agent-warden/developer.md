# Agent Warden developer reference

The service's contract, the heartbeat that takes the warden's notices over and the rules for each episode are [D041](../../../docs/decisions/D041-agent-warden-observes-the-vsys-warden.md).

## States

The bar widget draws one shield in the tone of the service's state, with the Lucide icon and the `Theme.badge.tone` group below. The words, icons and tones are `ViewLogic.js`. A count of zero is not drawn.

| State | Icon | Tone | Count | Tooltip, for example |
|---|---|---|---|---|
| `calm` | `shield-check` | neutral | agents running | 3 agents running within their limits |
| `working` | `shield-check` | accent, one pulse on entering | agents running | Moved 1 agent back into limits 2m ago |
| `look` | `shield-alert` | warning | things that need a look | claude in vgs is using a lot of memory |
| `problem` | `shield-x` | danger | things that need attention | Agents are close to their memory limit |
| `not-checking` | `shield-off` | neutral | none | Agent Warden hasn't checked in 3m |
| `not-set-up` | `shield-question-mark` | neutral | none | Agent Warden isn't set up |
| `update-warden` | `shield-alert` | warning | none | Agent Warden needs an update |

## Panel

The panel shows the heading Agents, one sentence for the state, at most three items, most serious first, and the agent group's memory against its slowdown point. It opens with keyboard focus on its primary button when one is shown. The meter is hidden when the warden did not report the memory or a limit. No text names a process id or a scope unit, because the published `detail` holds neither. A footer shows the time of the last check and Open vsys, which opens the `vsys` TUI. While vsys is missing, the link is Install vsys.

When vsys is installed, each open runs vsys once with `--once --summary`, and the panel shows vsys's verdict on the whole computer as one line: nothing wrong, the number of things worth a look, or the number of problems. It reads only the verdict's levels ([vsys verdict.md § Summary JSON](https://github.com/vanillagreencom/vsys/blob/main/docs/architecture/verdict.md#summary-json)) and never shows a verdict's subject. A run that fails, or a summary of another schema, is logged as `agent-warden: summary=...` and shows no line.

A state that needs a setup step shows one button in place of the items:

| State | Button | What it does |
|---|---|---|
| `not-set-up` | Set up | Opens the `setup` TUI, which runs the warden installer of vsys. |
| `update-warden` | Update | The same: the installer rewrites an older warden's units. |
| `not-checking`, stale | Start checks | Starts `agent-warden.timer` in the user's systemd through the `run` capability. |
| `not-set-up` or `update-warden` without vsys | Install vsys | Raises the shell's requirement notice for vsys through `shell.requirements.offer`. |

A press that hands off closes the panel. A refusal stays in the panel as one sentence, such as "The setup window could not open. VGS is missing its terminal launcher, xdg-terminal-exec. Reinstall VGS to restore it.", and is logged as `agent-warden: action=<action> <reply>`.

The Settings page shows Set up while the warden is not installed ([D061](../../../docs/decisions/D061-no-manual-commands.md)).

## Notifications

The service sends one desktop notification when something starts to need a look, and again only after it has cleared and comes back. It takes over from the warden's own notices and words them for people.

| Kind | Scope | Opens when | Title, for example | Urgency | Open vsys |
|---|---|---|---|---|---|
| `tasks` | the lane's unit | an agent's lane is near its task ceiling | An agent is near its process limit | normal | yes |
| `memory` | the lane's unit | an agent's lane is near its memory ceiling | An agent is near its memory limit | normal | yes |
| `not-moving` | `agents.slice` | moves wait for memory headroom | Agents are close to their memory limit | critical | yes |
| `move-failure` | the tree's unit | a move failed or left part behind in the last 5 minutes | Some agent processes still have no limits | normal | yes |
| `reaped` | the leftover unit | leftover work was stopped in the last 5 minutes | Cleaned up after a finished agent | low | no |
| `not-checking` | `agent-warden` | the status is stale | Agent Warden has stopped checking | normal | no |
| `moved` | the tree's unit | an agent was moved back into its limits in the last 5 minutes | Moved an agent back into its limits | low, through `shell.notify.send`, left out of History | no |

`problems`, the default, sends every kind but `moved`, which the panel shows. `everything` also sends each move, through the core's `shell.notify.send` rather than its own notify-send run. `off` sends nothing. The cleanups and the moves one status opens go out as one notice. The body gives the numbers from `status.json`, GB for GiB values through `WardenLogic.gib`, and the tool and worktree as the panel names them, and never a process id or a scope unit.

## IPC

| Name | Reply |
|---|---|
| `status` | The published values as one JSON line. |

```text
vgshell ipc call vgs.agent-warden invoke status
```
