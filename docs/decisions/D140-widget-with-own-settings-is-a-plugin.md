# D140: A widget with its own settings or Manage widgets row is its own bar-widget plugin

[← Decision Index](INDEX.md)

**Date**: 2026-11-22

**Status**: Active

**Research**: [VGS-2718](https://linear.app/vanillagreen/issue/VGS-2718): the owner's request for Workspaces in Manage widgets with its own settings, and the reviewer-arch design review of that route.

**Refines**: [D005](D005-kinds-are-surfaces-no-dependencies.md), where the built-in boundary sits, and [D108](D108-renamed-plugin-declares-former-ids.md), what a former id may name.

**Decision**: A widget a plugin draws inside its own surface, with no settings or Manage widgets row of its own, stays a built-in registered through capability `builtins`. A widget that needs its own settings or its own Manage widgets row is its own plugin of the existing kind `bar-widget`, and no new kind. A plugin that leaves a built-in names the built-in's registration id, `<plugin id>/<name>`, in its `formerIds`, so the D108 rename moves each saved `bar.layout` entry to the new plugin in the same section and place. Such a plugin takes no first presence: a saved layout without the built-in's entry keeps it off, and the shipped layout places it for a user with no saved bar.

**Why**: A built-in has no settings row, no enablement and no Manage widgets row: its owner's Settings page holds one placement switch for it, and its owner's settings would hold any value it reads. A `bar-widget` plugin gets all three from the existing manifest, enablement and chooser paths, with no core change and no word outside the closed kind list. The rename keeps the user's bar as it was with no step and no old-form reader ([D107](D107-format-change-ships-its-migration.md)). A built-in keeps no `plugins[]` row, so its hidden state is its absence from the layout alone; first presence would read that absence as a new widget and show a widget the user hid.

**Rejected**: Settings for the built-in on its owner's page, with a Manage widgets row the core draws for built-ins. That adds a second settings and enablement path that only built-ins use, and a user still could not find the widget the way every other widget is found.

**Revisit when**: A widget must share its owner's live surface state that no capability can lend, or a built-in needs settings while its owner must keep drawing it.
