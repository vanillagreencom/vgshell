# Consumer text names the result, never the operation

Read before writing text a user reads: a plugin description, a Settings row, a window, a panel, a tooltip, a message or a setup screen.

## The approach

Consumer text follows ASD-STE100 Simplified Technical English: short sentences, one idea each, active voice, one word per thing. It says what the feature does for the user or what the user must do, and names the result of a check, never its internal operation. A setup step is automatic or one click, and no text tells the user to run a command ([D061](../decisions/D061-no-manual-commands.md)). An extra that needs developer setup is never shown to a consumer ([D075](../decisions/D075-consumer-features-need-no-developer-setup.md)).

## Why

A user reads a label once; a diagnostic key or a reason code sends them to a log they do not have. A command in user text puts a token into shell history and asks the user to do what the shell can do for them.

## Rules

- Do give a plugin description one or two short sentences with no command and no feature list.
- Do give a hint one short sentence, and remove it when the label already says it; longer help goes in an info dialog.
- Do keep diagnostic keys, reason codes and command errors in logs; show a plain sentence that explains the result or the action. A field made to show a technical value may name it.
- Never tell the user to run a command. `scripts/check-user-commands.py` refuses the text, and a command shows only behind "Show command".
- Never show an unsupported extra to a consumer. `scripts/test-plugin-extras.js` pins it.
- Do map plugin-owned messages before the plugin shows them; keep a user's own commands, their output and child command streams unchanged.
- Do keep developer logs, code comments, developer documentation and machine-readable output technical; a component preview may name the component, property or state it shows.

## The canonical example

The `description` and `status` labels in `shell/plugins/vgs.updates/manifest.json`: what the plugin does, what a row's state means, no command. Copy their tone.

## Revisit when

A step needs input a masked field or a TUI cannot take, such as a file picker or an OAuth round trip.

## Not governed

The wording of a decision record or an architecture doc, which the docs-writing skill holds.
