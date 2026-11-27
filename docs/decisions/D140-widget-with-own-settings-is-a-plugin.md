# D140: A widget with its own settings or Manage widgets row is its own bar-widget plugin

[← Decision Index](INDEX.md)

**Date**: 2026-11-22

**Status**: Active

**Research**: [VGS-2718](https://linear.app/vanillagreen/issue/VGS-2718): the owner's request for Workspaces in Manage widgets with its own settings, and the reviewer-arch design review of that route.

**Refines**: [D005](D005-kinds-are-surfaces-no-dependencies.md), where the built-in boundary sits, and [D108](D108-renamed-plugin-declares-former-ids.md), what a former id may name.

**Decision**: A widget a plugin draws inside its own surface, with no settings or Manage widgets row of its own, stays a built-in registered through capability `builtins`. A widget that needs its own settings or its own Manage widgets row is its own plugin of the existing kind `bar-widget`. A plugin extracted from a built-in names the built-in's registration id, `<plugin id>/<name>`, in `formerIds` to suppress first presence. A placement-only extraction uses the D108 rename to keep each saved `bar.layout` entry in the same section and place. When an extraction also moves saved settings, as Clock does in version 8, a retained format converter uses shipped built-in migration context to move the placements in place and copy the saved values from the owner's plugin row. The shell excludes the converter's former id when it applies registry renames. A saved layout that omits both ids keeps the widget off. The shipped layout places it for a user with no saved bar.

**Why**: A built-in has no settings row, independent enablement or Manage widgets row. Its owner holds any settings it reads. The existing `bar-widget` paths provide all three. A retained converter makes the layout and settings conversion run on the same input before either writer advances the format, including when an offline writer reads before the registry has scanned ([D107](D107-format-change-ships-its-migration.md)). A user hides a built-in by removing it from the layout, so first presence would show a widget the user hid. The owner's disablement applies to its whole surface. Re-enabling that surface must restore a widget the user kept in the layout.

**Rejected**: Settings for the built-in on its owner's page, with a Manage widgets row the core draws for built-ins. That adds a second settings and enablement path that only built-ins use, and a user still could not find the widget the way every other widget is found.

**Revisit when**: A widget must share its owner's live surface state that no capability can lend, or a built-in needs settings while its owner must keep drawing it.
