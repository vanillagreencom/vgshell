# shell/

The Quickshell shell root.

## Rules

- Call no JavaScript function the shell's Qt 6.12 engine lacks, such as `flatMap` or `trimEnd`: the call throws, and what it feeds draws nothing. `scripts/check-js-engine.py` refuses each call and names a replacement.

## Read when

- Before changing core boundaries, hosts or capability providers: [overview.md § Core](../docs/architecture/overview.md#core) and [§ Hosts and capabilities](../docs/architecture/overview.md#hosts-and-capabilities).
- Before changing what a plugin receives: the [vgs-plugin API reference](../.agents/skills/vgs-plugin/references/api.md).
- Before editing `Core/Compositor.qml`, `Core/Dispatch.js` or another Hyprland request: [hyprland.md § Dispatch](../docs/architecture/hyprland.md#dispatch).
- Before editing code that relies on a Quickshell or Qt fact, read its local constraint comment and the [code-quality skill's Project Instructions](../.agents/skills/code-quality/SKILL.md#project-instructions).
- Before working in a plugin: [plugins/AGENTS.md](plugins/AGENTS.md). Before changing shared components or helpers: [Ui/AGENTS.md](Ui/AGENTS.md) or [Commons/AGENTS.md](Commons/AGENTS.md).
