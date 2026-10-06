# D023: A plugin may own its look, taking only the theme's mode, accent and motion scale

[← Decision Index](INDEX.md)

**Date**: 2026-09-27
**Status**: Active
**Research**: [VGS-475](https://linear.app/vanillagreen/issue/VGS-475)
**Refines**: [D015](D015-tokens-are-a-judged-table.md)

**Decision**: A plugin that names an `appearance` library in its manifest owns its look through its own token table, judged by the shell's judge, and takes only the theme's mode, accent and motion scale as inputs.

**Why**: Naming the two theme values the design wants as the only inputs makes a leak of any other theme value unrepresentable; the motion scale is the reduced-motion control, not styling. One judge over a second table keeps every value typed and checked. `scripts/check-design-tokens.py` refuses a literal and an unknown look.

**Rejected**: A literal allowance, a plugin-id exemption or values moved into settings, each hiding the look from the judge; and a mode inferred from background luminance, which every plugin would infer differently.

**Revisit when**: A plugin needs a third theme input, a `qs.Ui` component gains a parameterized form such plugins share, or a theme must restyle such a plugin after all.
