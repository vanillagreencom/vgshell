# Every component of qs.Ui meets one contract

Read before adding or changing a component of `qs.Ui`, or a pointer, scroll or focus behaviour in any surface.

## The approach

`qs.Ui` is the one component library, listed in `shell/Ui/qmldir`. Every control extends a `QtQuick.Templates` type and supplies only its visuals from tokens ([D017](../decisions/D017-templates-and-path-icons.md)). Every overlay is a Quickshell `PopupWindow` anchored to the item that declares it ([D018](../decisions/D018-overlays-are-quickshell-popups.md)). One owner, `PointerCursor`, draws the pointing hand on every click target; no view drags with the mouse; `TouchpadScroll` moves every view the same way; an unknown name logs and draws the default; a focus ring shows for the keyboard alone; and every component lands in the Gallery before a screen uses it.

## Why

One owner of the pointer hand means one check covers every click area, where the literals it replaced had reached seven plugin files and no control. A mouse drag that scrolls a view undoes text selection, so views take no mouse button. Qt's `Flickable` moves one pixel per pixel of swipe and stops, which no desktop list does, so one owner adds the gain and friction a user expects. A Qt window popup is placed once by Wayland inside the bar and never moves, so an overlay must be its own surface to leave the bar. The Gallery is where a component is seen in every state before a screen hides one nobody drew.

## Rules

- Do declare `PointerCursor` in every element that takes a click, a plugin's `MouseArea` included, and never write `Qt.PointingHandCursor`. `scripts/check-pointer-cursor.py` refuses both under `cursor-missing` and `cursor-literal`; a `// pointer-cursor-exempt: <reason>` line directly above a click-away area or a scroll bar exempts it, and a marker with no reason exempts nothing.
- Do set `acceptedButtons: Qt.NoButton` on every `Flickable`, `ListView` or `GridView`; `ScrollArea` sets it once. `mouse-drag` in the same check refuses a view without it, with no exemption.
- Do declare `TouchpadScroll { view: <the view> }` in every view a control or plugin declares. `scripts/qml-tests/tst_touchpadscroll.qml` pins the motion, and `scripts/smoke/rows/settings.sh` and `gallery.sh` send a real swipe.
- Do draw `FocusRing` while `visualFocus` holds, and give every pointer action a keyboard path: [keyboard.md](keyboard.md). `scripts/check-keyboard.py` refuses an exception without its marker.
- Do log an error and draw the default for an unknown `variant`, `size`, `role`, `tone` or `level`, and set `Accessible.name` from the control's text; `IconButton` requires `label`.
- Do extend a `QtQuick.Templates` type and import no Quickshell module except in an overlay, so `scripts/qml-unit.sh` runs every component offscreen.
- Do open every popover, tooltip, menu and select list as a Quickshell `PopupWindow` with a focus grab, so Escape and a press outside close it; `Tooltip` alone takes no grab. `scripts/smoke/rows/overlays.sh` reads each beside a copy without the grab.
- Do draw text a caller hands a row as plain text, never markup. `scripts/qml-tests/tst_layout.qml` pins it.
- Do put `info` on a `Field` or `IconButton` when a row needs one short explanation. The icon opens a dialog and returns focus to itself when it closes.
- Never give a decorative component such as `VoiceOrb` or `QrMatrix` a pointer handler, a process, a file, a cache or a secret store, so a passive layer that draws it stays input-free ([D026](../decisions/D026-passive-layers-are-a-capability.md)). `scripts/qml-tests/tst_voiceorb.qml` and `tst_qrmatrix.qml` pin it, and a shader's driver stops when the item, its window or `motion.scale` is off.
- Do load every inline image through `ImagePool`, so nothing decodes on the GUI thread. `scripts/qml-tests/tst_imagetext.qml` pins it.
- Do let `Scrim` and a `Dialog` card take the presses, hover and wheel on themselves, so nothing under them answers; a scrim's click-away never answers a click on the card. `scripts/smoke/rows/automations.sh` clicks a card over its scrim.
- Do keep `SlimScrollBar` free of theme reads, so a plugin-owned look can draw it; `scripts/qml-tests/tst_slimscrollbar.qml` pins it.
- Do compose `BarItem` for every bar widget and workspace pill, `FormRow` for every key/value row and `BindField` for every bind row, so Settings and the Key Hints window draw one row from one owner. `scripts/smoke/rows/bar.sh` holds every item to the bar's centre within one pixel.
- Do put a "Show command" step in `CommandDisclosure` beside the button that runs it, never alone; `scripts/check-user-commands.py` refuses the text ([D061](../decisions/D061-no-manual-commands.md)).
- Do add a new component to the Gallery in the same change, in every variant and state, with a focused example for a focusable control. `scripts/smoke/rows/gallery.sh` refuses a missing component, a missing focus example and an example past the window's edge.
- Never edit `shell/Ui/icons/Lucide.js`; run `scripts/vendor-lucide`. `scripts/test-lucide-data.js` pins the data.

## The canonical example

`shell/Ui/controls/IconButton.qml`: a `QtQuick.Templates` button, every value from a token, `PointerCursor` and `FocusRing` declared, an `Accessible.name` from its required label, and a gallery entry per variant. Copy it.

## Revisit when

Qt sends `xdg_popup.reposition` for a window popup and bounds it by the screen, the pixel tests show a drawing defect the icon font does not have, or a surface needs an input model the shared owners cannot express.

## Not governed

What each component's properties and signals are: that is each file's header and its `scripts/qml-tests/tst_*.qml`. Where a container places them is [design-layout.md](design-layout.md); a list's selection motion is [motion.md](motion.md).
