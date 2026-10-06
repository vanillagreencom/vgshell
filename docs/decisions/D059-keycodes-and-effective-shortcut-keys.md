# D059: Keycodes and effective shortcut keys use the generated layer's judges

[← Decision Index](INDEX.md)

**Date**: 2026-09-30
**Status**: Active
**Research**: [VGS-614](https://linear.app/vanillagreen/issue/VGS-614)
**Refines**: [D028](D028-one-generated-hyprland-layer.md)

**Decision**: A manifest key may be a decimal keycode, normalized to `code:<n>`, and a plugin reads its effective keys through the same configuration and conflict judges that write the Hyprland layer.

**Why**: A keysym changes with the layout while a keycode does not. Hyprland reports Lua binds opaquely, so scraping the compositor cannot recover shortcut names, defaults or skipped conflicts. `scripts/qml-tests/tst_shortcutregistry.qml` holds the read.

**Rejected**: Reading the compositor's bind JSON. It omits Lua's parsed keycodes and cannot represent shell defaults.

**Revisit when**: Hyprland changes keycode syntax, or exposes shortcut identity and parsed keys through a readback API.
