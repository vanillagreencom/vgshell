# D105: Jarvis's knowledge lives in one home folder that grants no authority

[← Decision Index](INDEX.md)

**Date**: 2026-10-09

**Status**: Active

**Research**: the Jarvis plan attached to [VGS-1194](https://linear.app/vanillagreen/issue/VGS-1194)

**Refines**: [D070](D070-jarvis-action-policy.md), which stays the only source of permission, and [D079](D079-brains-wire-and-harness-adapters.md), whose harness program keeps its private working folder

**Decision**: One folder the user picks holds what Jarvis knows: `AGENTS.md`, the skills under `skills/base/` and `skills/own/`, `memory/` and `state/`. Its text reaches every brain by one route. `Guidance.compose` adds `AGENTS.md` and an index of the skills to the shipped guidance, and each skill body is a `help` topic read through the router. A harness program never runs in the home, so it loads none of the home's settings, hooks or MCP servers, and each vendor's own memory is off at launch. Home text carries the release label `home`: it taints no turn and goes to the conversation's recipients without a grant. The gate protects the whole home folder through `Denied`: a model's file tool, shell command or harness approval reaches no path in it but `state/`.

**Why**: A wire brain has no working folder, so only the instruction route gives every brain the same knowledge. A program started in the home would load its hooks, extensions and MCP servers outside the gate, and each vendor loads a different part of a folder. A vendor's memory is a second store that one brain reads and Jarvis cannot audit. The label `file` on home text would taint every turn and raise every changing action to a confirmation; `home` is safe only while the user and VGS are the text's sole writers, which the protected folder holds. The rule names no entry, so a file a model adds beside the layout, such as a harness program's own settings, is refused as `AGENTS.md` is.

**Rejected**: Each harness program with the home as its working folder, reading `AGENTS.md` and skills its own way. It reaches no wire brain, and the home's hooks and servers would act without the gate.

**Revisit when**: A vendor's program reads a folder's instructions without its settings, hooks and servers, home text gains a writer other than the user and VGS, or a brain needs home knowledge the instruction route cannot carry.
