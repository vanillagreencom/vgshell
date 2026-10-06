# D018: Overlays are Quickshell popup windows anchored to their item

[← Decision Index](INDEX.md)

**Date**: 2026-09-26
**Status**: Active
**Research**: —

**Decision**: Every overlay in `qs.Ui` is a Quickshell `PopupWindow` anchored to its item. `Menu` and `Select` hold their own key handling, and `Select` extends `AbstractButton`, not `ComboBox`, whose list must be a Qt popup.

**Why**: Measured on host cachy with Quickshell 0.3.1 and Qt 6.11.2 on 2026-09-26, a Qt window popup declared in a bar widget landed once at the anchor's right edge, four pixels below the bar's top, whatever position it asked for: Qt leaves repositioning to the Wayland server and never sends one. The Quickshell popup landed under the item and moved with it.

**Rejected**: Qt popups with `popupType: Popup.Window`, the design plan's choice. Its revisit condition held.

**Revisit when**: Qt sends `xdg_popup.reposition` for a window popup and bounds it by the screen, or Quickshell offers a popup type Qt's templates accept.
