# Agent Warden

Agent Warden shows whether your AI coding agents stay within their memory and process limits. It is for people who run several agents on one computer. [vsys](https://github.com/vanillagreencom/vsys) provides the warden it reads.

![The Agent Warden panel, open from its shield, reporting two problems](../../../docs/images/plugins/vgs.agent-warden-panel.webp)

## Features

- A shield in the bar that shows the agents' state: grey while nothing needs you, yellow for a warning, red for a problem, and crossed out while Agent Warden is not checking. The number on it counts the running agents, or the warnings and problems while there are any.
- A panel that describes the state in one sentence and lists each warning and problem, most serious first, in vsys's own words, with the button that acts on it. It shows how close the agents' memory is to the point where they slow down.
- The warnings vsys finds on the rest of the computer, in the same list, with the programs involved.
- Open vsys in the panel opens the vsys dashboard.
- A notification for each warning and problem the warden reports, with its level and its buttons, and one when Agent Warden stops checking.
- Click the shield to open and close the panel. Choose a key under Keys on the plugin's Settings page to open it with a key.

## How it works

Agent Warden only reports. The vsys warden checks your agents and tries to move them back into their limits on its own schedule, so it keeps working when VGS restarts or stops. Agent Warden reads what the warden found and shows it.

## Setup

While a setup step is needed, the plugin's Setup tab and its panel show it as a button. Install vsys opens the install notice for vsys. Set up opens a floating terminal that starts the warden's checks.

<details><summary>Show command</summary>

```bash
vsys warden install
```

</details>

| Setting | What it changes |
| --- | --- |
| Show count | Shows the number of running agents, or of warnings and problems while there are any, on the corner of the shield. |
| Hide when idle | Hides the shield when no agents run and nothing needs attention. |
| Notifications | Alerts for problems, all events or none. |

[developer.md](developer.md) states each state, notification and IPC function.
