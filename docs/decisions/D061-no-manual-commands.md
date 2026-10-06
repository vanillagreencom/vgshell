# D061: No manual commands

[← Decision Index](INDEX.md)

**Date**: 2026-09-30
**Status**: Active
**Research**: [VGS-613](https://linear.app/vanillagreen/issue/VGS-613)
**Refines**: [D033](D033-floating-tuis-are-core.md), [D035](D035-manifest-requirements.md), [D037](D037-plugin-status.md)

**Decision**: A user-facing setup step is automatic or one click. A step that asks or elevates runs in a floating TUI or the requirement notice, a secret goes into a masked field the core stores in libsecret, and a command shows only behind "Show command".

**Why**: Pasting a token into a shell command puts it in shell history. The core already owns every route a step needs, so a status action as manifest data gives a plugin a button with no interface code, and the core never runs a manifest command string. `scripts/check-user-commands.py` refuses user-facing text that tells the user to run a command.

**Rejected**: A generic `run` action whose argv the manifest declares. The shell would run plugin commands outside a terminal with no place for a question, a password or an error.

**Revisit when**: A step needs input a masked field or a TUI cannot take, such as a file picker or an OAuth round trip, or a second secret store is needed.
