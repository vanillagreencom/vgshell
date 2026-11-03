# Agent Debug

Agent Debug tells you when a program crashes or a VGS setup task fails, and offers Diagnose. Diagnose opens the AI agent you choose with the facts of the failure, so you get an explanation without searching logs yourself.

![The Agent Debug Settings tab with Claude Code chosen and its Muted programs list](../../../docs/images/plugins/vgs.agent-debug-settings.webp)

## Features

- A notification when one of your programs crashes, with Diagnose and Mute.
- A notification when a VGS setup task, the install or update of a plugin's tools, fails, with Diagnose.
- Diagnose opens Claude Code, Codex, Copilot, Pi or OpenCode in a floating terminal. The agent asks you before it runs a command.
- At most one notification for each program or task in a minute.
- Muted programs on the Settings tab, each with Unmute.

## How it works

Agent Debug notifies you only after you choose an agent on its Settings tab. It reads the crash records systemd-coredump writes to the system journal for your own programs, and the failed setup tasks VGS keeps.

The agent gets only facts: the program or task, the time, the signal and where the record of the failure is. It never gets the content of a log. The agent also gets the `vgs-diagnose` skill, which tells it to read the records on this computer, change nothing, and keep what it proved apart from what it thinks. VGS copies the skill into the agent's own skills folder when you press Diagnose, and never writes over a skill file it did not write.

At the end of a crash diagnosis the agent asks whether to mute that program, and mutes it only when you say yes.

## Setup

Choose an agent on the Settings tab. The select lists the agents installed on this computer. The Setup tab offers to install an agent or the system journal tool when one is missing.

| Setting | What it changes |
| --- | --- |
| Enabled | Turns Agent Debug on or off. It is on by default. |
| Agent | The agent Diagnose opens. Until you choose one, Agent Debug shows no notification. |
| Muted programs | The programs whose crashes do not notify you. Unmute asks before it removes a program from the list. |
