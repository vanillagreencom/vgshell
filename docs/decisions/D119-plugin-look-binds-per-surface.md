# D119: A plugin-owned look binds per surface

[← Decision Index](INDEX.md)

**Date**: 2026-11-02

**Status**: Active

**Research**: [VGS-2210](https://linear.app/vanillagreen/issue/VGS-2210)

**Refines**: [D023](D023-plugin-owned-appearance.md): its "a plugin" becomes the files of that plugin that draw with its look.

**Decision**: A plugin's `appearance` table governs only the files that draw with it: a file that binds it through `Theme.appearance(TOKENS, LIGHT)`, and a file that reads a `look.<path>` its owner hands it. Those read no other `Theme` member and name only the table's paths. The plugin's other files read `Theme` as any plugin does and follow the user's theme. Jarvis's overlay (the bubble, its orb) binds its look; its console, bar widget and power card do not.

**Why**: Jarvis's overlay must look the same under every theme, as vgs.voice's plasma does, while its console and bar widget are ordinary surfaces the theme must restyle. A plugin-wide look forced one choice on both. The binding and the `look.` reads are lines the code already writes, so `scripts/check-design-tokens.py` reads the scope from them and needs no list.

**Rejected**: A core token group for the overlay, which a theme package could set (`ThemeLogic.js` accepts any token path) and so recolour the orb; and a second plugin for the overlay, which would split one Session's views across two plugins.

**Revisit when**: A surface needs part of a look and part of the theme in one file, or two surfaces of one plugin need different looks.
