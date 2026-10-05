# Polkit: other agents

Covers: shell/plugins/vgs.polkit/bin/agents, shell/plugins/vgs.polkit/tui/**, shell/plugins/vgs.polkit/Service.qml, shell/plugins/vgs.polkit/PolkitModel.js, shell/plugins/vgs.polkit/manifest.json, scripts/test-polkit-agents.sh, scripts/smoke/fixtures/polkit/**

polkitd accepts one authentication agent per session. This file holds what `vgs.polkit` does when another agent holds the session: how it finds that agent, what its status row offers, and how VGS's agent registers afterwards with no session restart. The agent and the prompt are [lock-polkit.md § Polkit](lock-polkit.md#polkit).

## Finding the agent

- polkitd has no call that names the agent it holds. While polkitd has not accepted VGS's agent, the service runs `bin/agents check`, whose header states each verb, its output and its refusals.
- `bin/agents` reads the user's own processes under `/proc`. A process is another agent when `PolkitModel.otherAgent` admits its name. Its environment must name the script's own system bus and no other Hyprland instance: an agent on another bus registers with another polkitd, and an agent of another instance belongs to another session. An agent that is not dumpable, as `polkit-kde-authentication-agent-1` is, denies its owner its environment and its program's path. It is counted, since nothing else it shows names its bus or instance, and it goes by its process name: no package owns a name, so the row offers Stop. A dumpable process that denies the same reads runs in another user namespace, a container's or a sandbox's, and is not counted. The kernel gives a process's `/proc` files to root when it is not dumpable, which tells the two apart. A process that is not dumpable inside a process namespace under the script's, which `/proc/<pid>/status` shows as a second `NSpid`, is a container's and is not counted either.
- The package that owns the agent's program is `vgshell pkg owner`'s answer. Whether that package can be removed is `vgshell pkg removable`'s answer, the package manager's own dry run ([packages.md § Queries](packages.md#queries)). A program no package owns, a manager with no dry run and a dry run that fails each read not removable.
- The service checks again only for a new agent object. It asks for one only for a reason, each in [Registering again](#registering-again): its own TUI's end, the requirement scan that finds polkit, or its check that ended a recorded program. It runs no timer.

## The status row

`PolkitModel.agentStatus` decides the one `agent` status value from three inputs: whether polkitd accepted the agent, the last check, and whether the requirement scan found `pkexec`.

| Found | Text | Button |
|---|---|---|
| The agent is registered | Ready to show password prompts | none |
| Another agent, every package removable | Another app is showing password prompts: `<name>`. One line per agent. | Uninstall |
| Another agent, one package required, unowned or unknown | the same lines | Stop |
| No other agent, no polkit | Polkit is not installed. | Install |
| No other agent | Password prompts are unavailable. No other app is showing them. | none |
| The check gave no answer | Password prompts are unavailable. VGS could not look for another app. | none |
| Not registered, the first check has not ended | nothing published: the page reads Not reported | none |

- `<name>` is the package, else the program's file name, `PolkitModel.agentName`.
- The three buttons are the entry's named `actions` ([status.md § Declared](status.md#declared)). Uninstall and Stop open the plugin's own floating TUIs, `tui/uninstall.sh` and `tui/stop.sh`. Install raises the requirement notice for `pkexec`.
- Uninstall runs `bin/agents uninstall`. It reads the package manager again in the terminal and removes nothing when one agent's package is required or unowned. Otherwise it runs `vgshell pkg run remove`, then ends each agent.
- Stop runs `bin/agents stop`. It ends each agent and records its program in `${XDG_STATE_HOME:-~/.local/state}/vgshell/polkit/stopped.json`: its path, or its process name where the path cannot be read. It changes no package and no autostart file. In a later session the service's check ends a recorded program again before it reads the session, so the agent does not hold a session VGS runs in, however that agent is started. The other desktop that needs it starts it as before.

## Registering again

- A Quickshell `PolkitAgent` asks polkitd once, when it is built ([runtime-qml.md](runtime-qml.md)). The `polkit` capability's `register` destroys an unregistered agent and builds the next one in a later turn: [capabilities.md](capabilities.md).
- The service calls `register` when its uninstall or stop TUI ends, when the requirement scan first finds polkit, and when its check ended a recorded program. The new agent's refusal starts the next check, so the row then names what still holds the session.

## Omarchy

Omarchy (basecamp/omarchy `6520ac7d`) runs the same Quickshell `PolkitAgent` in its shell and logs "another agent may be running" when polkitd refuses it (`shell/plugins/polkit/PolkitAgent.qml`). It owns the system's package set, so its one-time upgrade removes `polkit-gnome` and the `hyprpolkitagent.service` unit files (`bin/omarchy-upgrade-to-quattro`), after `pacman -Rs --print` as the dry run. VGS takes that dry run for `vgshell pkg removable`. VGS installs on a system it does not own, so it finds the agent at run time, asks before it removes anything, and offers Stop where another desktop requires the package.

## Invariants

1. A process is another agent only by `PolkitModel.otherAgent`, the row's value follows the table above, Uninstall is offered only when every found package is removable, and each value fits the plugin's manifest under the core's judge. Enforced by `scripts/test-polkit-model.js`, one control per rule.
2. `check` names each agent of this system bus and this Hyprland instance and ends only recorded programs; `uninstall` removes nothing while one package is required or unowned, ends no agent after a failed removal, and ends the agents after a removal; `stop` records and ends them and changes no package; an agent that does not end is refused; an agent that is not dumpable is counted, and recorded by its name, and a process of another user namespace or of a process namespace under the script's is not counted; a process that took an ended agent's pid is left alone; each TUI script runs its own verb under the presenter alone. Enforced by `scripts/test-polkit-agents.sh` in a process namespace of its own with a stand-in `vgshell`, one control per rule.
3. Behind another agent that registered first, the row names it, draws one Badge per agent, offers Uninstall while nothing requires its package and Stop while another package does, each press opens the plugin's own TUI, and VGS's agent registers when the run ends, in the same shell. A recorded program is ended and the agent registers with no press. Enforced by `scripts/smoke/rows/polkit.sh` with the stand-in polkitd and agent of `scripts/smoke/fixtures/polkit/` and a stand-in `pacman`; the two button readings are each other's control, as are the one-Badge and two-Badge readings, and a plugin copy whose service never calls `register` stays unregistered.
