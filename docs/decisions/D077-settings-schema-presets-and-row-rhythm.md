# D077: Format-like settings declare presets, and every Settings row shares one height

[← Decision Index](INDEX.md)

**Date**: 2026-09-30
**Status**: Active
**Research**: [VGS-686](https://linear.app/vanillagreen/issue/VGS-686)
**Refines**: [D032](D032-settings-plugin-and-manifest-settings-convention.md), [D057](D057-setting-options-from-status.md), [D063](D063-design-scale-on-the-4-px-grid.md)

**Decision**: A string setting whose value is a format, such as a clock format, declares `presets` or a status-fed option list instead of free text, and a format string is judged before it is written. Every inline Settings row uses one row height token.

**Why**: A user must not need to know a library's format syntax to change a setting, and a manifest judge that refuses free-text format strings by one rule beats guessing from key names. One row height keeps the page aligned. `scripts/test-setting-values.js` holds the judge.

**Rejected**: Keeping free-text strings with better descriptions. The description still asks the user to know Qt's date-format letters.

**Revisit when**: A setting needs a structured editor the schema cannot describe, or a string must accept arbitrary text with no preset anchor.
