# Keyboard

Covers: shell/Ui/foundation/KeyNav.qml, shell/Ui/foundation/KeyNavLogic.js, shell/Ui/feedback/KeyCaps.qml, shell/Ui/controls/**, shell/Ui/layout/**, shell/Ui/overlay/**, shell/Ui/feedback/Dialog.qml, scripts/check-keyboard.py, scripts/test-check-keyboard.py, scripts/test-key-nav-logic.js

Keyboard support is part of the component contract. A component that accepts a pointer action also gives the same action a keyboard path, or names the owning composite that supplies it.

## Standard

[D068](../decisions/D068-keyboard-first-standard.md) records keyboard support as a first-class design system standard.

| Id | Rule |
|---|---|
| F1 | A focusable control draws `FocusRing` while `visualFocus` holds. A text input draws it while `activeFocus` holds. A list, menu, grid or carousel uses its one selection as the focus indicator. |
| F2 | Tab follows reading order. No hidden, disabled or unusable item takes focus. |
| F3 | A surface opens on its primary input, else its list, else its focusable body. It never opens on an action that installs, removes or changes the system. A key-opened surface uses `Qt.ShortcutFocusReason`. A click-opened surface uses `Qt.MouseFocusReason`. |
| F4 | Modal surfaces keep Tab inside and wrap. A `Dialog` traps only while `modal` holds. |
| F5 | A popup restores focus to its opener when the opener still exists. A separate Hyprland surface returns to the previous client. |
| F6 | A composite widget is one tab stop. Lists, menus, tabs, segmented controls, radio groups, carousels and grids move their selection with arrows. |
| K1 | Escape backs out one level. A local edit or search clear may consume Escape before the surface closes. |
| K2 | Enter, Return and Space activate button-like controls. Space toggles checkable controls. Enter toggles them too. |
| K3 | Tab and Shift+Tab move between groups. Ctrl+Tab, Ctrl+Shift+Tab, Ctrl+PageDown and Ctrl+PageUp switch tabs in a tabbed surface. |
| K4 | Arrows move inside composites. An arrow never runs an action. |
| K5 | Home and End move to first and last. PageUp and PageDown move by a visible page. Sliders use Home and End for min and max, and PageUp and PageDown for `pageStep`. |
| K6 | A searchable list sends printable text to its search field. A menu without a search field uses type-ahead. |
| K7 | A full-screen overlay implements `navigate(direction)` when Hyprland directional binds must move inside it. |
| K8 | Shift+F10 and the Menu key open a row context menu where right click opens one. |
| K9 | Delete removes the selected item where the pointer offers removal. |
| D1 | A non-obvious shortcut appears in `KeyCaps`, one footer hint row or the control tooltip. |
| D2 | A surface has at most one hint row. Escape, arrows, Enter, Tab and Space stay implicit in obvious contexts. |
| P1 | Every pointer action has a keyboard path. Hover-only affordances also show for keyboard focus or selection. |
| P2 | The bar takes no keyboard focus. A bar widget action has a global shortcut or launcher path, and the surface it opens is keyboard-driven. |

## Components

| Role | Contract | Proof |
|---|---|---|
| Button-like controls | `Button`, `IconButton`, `ToggleButton`, `Checkbox`, `Radio`, `Switch`, `BarItem`, `Disclosure` and `DeviceRow` activate from Enter and Return as well as Space. | `scripts/qml-tests/tst_button.qml`, `scripts/qml-tests/tst_toggles.qml`, `scripts/qml-tests/tst_disclosure.qml`, `scripts/qml-tests/tst_devicerow.qml` |
| Row menus | `DeviceRow` opens its overflow menu on Shift+F10 and the Menu key, read through `KeyNavLogic.intent`, and its overflow button is a tab stop. | `scripts/qml-tests/tst_devicerow.qml` |
| Device lists | `DeviceList` is one Tab stop, the selected row; `KeyNav` moves the selection and the keyboard with the Tab focus reason, and Delete asks to remove a row of a removable list. | `scripts/qml-tests/tst_devicelist.qml` |
| Composite controls | `KeyNav` owns roving movement, Home, End, PageUp, PageDown, activation, reveal and type-ahead. | `scripts/test-key-nav-logic.js` |
| Shortcut hints | `KeyCaps` converts shortcut strings into `Kbd` chips. | `scripts/test-key-nav-logic.js` |
| Key capture field | `ShortcutField` is one Tab stop. Space, Enter, Return and keypad Enter start a capture through `KeyNavLogic.activate`. While it captures, every key but Escape, Tab and Shift+Tab is the combo's: Escape cancels, and Tab and Shift+Tab cancel and move the focus. Its keyboard and clear buttons are Tab stops after it. Escape in its text entry restores the key in effect, and a second Escape returns to the box. | `scripts/qml-tests/tst_shortcutfield.qml`, `scripts/smoke/rows/key-capture.sh` |
| Sliders | A slider responds to Up, Down, Home, End, PageUp and PageDown. | `scripts/qml-tests/tst_slider.qml` |
| Popups | `Menu`, `Select` and `Popover` keep their own focus while open. | `scripts/qml-tests/tst_overlays.qml` |
| Static check | `scripts/check-keyboard.py` refuses click areas without a key path and focusable items without a focus indicator. | `scripts/test-check-keyboard.py` |

## Static check scope

The validation row runs `scripts/check-keyboard.py shell`. `vgs-plugin check` runs the same rule on a plugin tree before a plugin lands.

## Static markers

Use `// keyboard-path: <how the keyboard reaches this action>` directly above a click-only item when an ancestor or owning composite supplies the key path.

Use `// focus-indicator: <what shows focus>` directly above a focusable item when a `FocusRing` is not the indicator.

The marker names a present mechanism. It does not exempt a missing mechanism.

## Surface proof

Each shipped surface's keyboard path, the row that proves it and what its audit found: [keyboard-surfaces.md](keyboard-surfaces.md).

## Decisions

[D068](../decisions/D068-keyboard-first-standard.md) records the keyboard-first standard, the host focus rule and the shared navigator.
