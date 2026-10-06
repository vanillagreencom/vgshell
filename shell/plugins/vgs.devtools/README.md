# Dev Tools

Dev Tools installs, updates and removes developer tools: coding agents, apps, command-line tools, languages, editors, databases and terminals. Its window also shows the VGS version and the tools VGS is missing.

![The Dev Tools window listing coding agents](../../../docs/images/plugins/vgs.devtools-window.webp)

Screenshot made with `scripts/readme-shots.sh` in the nested sandbox, with the default theme at scale 2.

## Features

- One row per tool with its version, where it comes from, and Install, Update or Remove. Each action runs in a floating terminal.
- A VGS section with how VGS is installed and its version, Update when VGS is behind, and Install for each missing requirement of VGS and its enabled plugins.
- Install a developer tool, Update a developer tool and Remove a developer tool in the launcher. Each offers the tools its action accepts now.
- A tool that something outside VGS provides shows Managed outside VGS and offers no action.
- mise manages the tools. The plugin's Settings page offers Install mise while it is missing.

## Settings

| Setting | What it changes |
| --- | --- |
| Create tool launchers | Install each tool the first time you open its launcher. |

[developer.md](developer.md) states the catalog, the engine, the window and the launchers.
