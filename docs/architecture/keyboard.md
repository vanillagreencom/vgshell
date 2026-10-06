# Every pointer action has a keyboard path

Read before adding a pointer action, a focusable control, a keyboard path, or changing how a surface is reached from the keyboard.

## The approach

Keyboard support is part of the component contract: a component that accepts a pointer action gives the same action a keyboard path or names the composite that supplies it. A focusable control draws `FocusRing` while `visualFocus` holds; Tab follows reading order and skips hidden, disabled or unusable items; a composite is one tab stop whose arrows move its selection; a modal keeps Tab inside; a popup restores focus to its opener; Escape backs out one level; Enter, Return and Space activate button-like controls. `shell/Ui/foundation/KeyNav.qml` is the one navigator for movement, Home, End, pages, activation and type-ahead. The choice is [D068](../decisions/D068-keyboard-first-standard.md).

## Why

Surfaces looked complete while a keyboard user could not reach the same action or see focus. One standard replaces per-plugin audits, and host-owned focus keeps the focus reason visible, so a ring shows for key-opened surfaces only. A passive layer that took keys could steal typing from the active client, so toasts take no keyboard focus and the inbox is their keyboard path.

## Rules

- Never ship a click area without a key path, or a focusable item without a focus indicator. `scripts/check-keyboard.py` refuses both, planted by `scripts/test-check-keyboard.py`, and `vgs-plugin check` runs it on a plugin tree.
- Do mark `// keyboard-path: <how>` or `// focus-indicator: <what>` above the item only when a present mechanism supplies it; the marker exempts nothing missing. The same check reads the marker.
- Do open a surface on its primary input, else its list, else its body, with `Qt.ShortcutFocusReason` for a key or IPC and `Qt.MouseFocusReason` for an anchored click; never on an action that installs, removes or changes the system. `scripts/smoke/rows/surfaces.sh` pins it.
- Do make a composite one tab stop with arrows inside; an arrow never runs an action. Route movement, Home, End, pages, activation and type-ahead through `KeyNav`. `scripts/test-key-nav-logic.js` pins both.
- Do let Escape back out one level; a local edit or search clear may consume it first.
- Never give the bar keyboard focus; a widget action has a global shortcut or a launcher path. `scripts/smoke/rows/bar.sh` pins it.
- Do keep a modal's Tab inside with `Keys.onTabPressed` on each action. `scripts/qml-tests/tst_dialog.qml` pins it.
- Do give a surface at most one hint row; obvious keys stay implicit.

## The canonical example

`shell/Ui/overlay/Menu.qml`: one tab stop, arrows and type-ahead through `KeyNav`, Escape closes, Enter activates, the ring from `visualFocus`. Copy it.

## Revisit when

Quickshell gives passive layers reliable focus without a prime, Qt changes its default button activation keys, or a surface needs a model the navigator cannot express.

## Not governed

The compositor-side capture of keys, which is [hyprland-shortcuts.md](hyprland-shortcuts.md); each surface's own path, which is its smoke row.
