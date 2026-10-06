# D032: A Settings plugin lists every plugin, and the manifest alone declares each settings page

[← Decision Index](INDEX.md)

**Date**: 2026-09-28
**Status**: Active (window → [D044](D044-application-windows-are-hyprland-toplevels.md))
**Research**: [VGS-508](https://linear.app/vanillagreen/issue/VGS-508)

**Decision**: The manager's whole user interface is a first-party plugin, `vgs.settings`, and each plugin's page is drawn from its manifest and the configuration alone: schema entries become fields and `hyprland.binds` become the Keys section. No plugin ships page code.

**Why**: One judged source per page gives a third-party plugin a full page with no UI code. A key in `shell.json` has one writer, the Hyprland layer, so a key is never a schema entry. `scripts/test-plugin-logic.js` pins the schema; `scripts/smoke/rows/settings.sh` reads the drawn page back.

**Rejected**: Plugin-supplied settings pages in QML. Third-party UI code would sit inside the settings window with one style per author.

**Revisit when**: A plugin needs a setting no schema type can hold, such as a list or a colour.
