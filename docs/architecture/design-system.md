# One token table and one component library draw every surface

Read before touching a token, the theme judge, `Theme`, a component of `qs.Ui`, a plugin-owned look, a container's inset, a pointer, keyboard, focus or list-selection behaviour, a Settings field, or text a user reads.

## The approach

Every colour, font, size, radius, opacity and duration a surface draws comes from one table, `shell/Commons/Tokens.js`, read as `Theme.<group>.<token>`. One pure judge, `shell/Commons/ThemeLogic.js`, resolves a theme document against that table and runs under node as well as in the shell. `Theme` publishes each group as a deep-frozen object of primitives, and a theme document is accepted whole or refused whole, so the last accepted theme stands ([D015](../decisions/D015-tokens-are-a-judged-table.md)).

The component library `qs.Ui`, listed in `shell/Ui/qmldir`, is the only thing that turns a token into a drawn pixel, and every component meets one contract. A control extends a `QtQuick.Templates` type and supplies only its visuals ([D017](../decisions/D017-templates-and-path-icons.md)); an overlay is a Quickshell `PopupWindow` anchored to the item that declares it ([D018](../decisions/D018-overlays-are-quickshell-popups.md)). One owner draws the pointing hand and one owner moves a view under a touchpad. Every pointer action has a keyboard path ([D068](../decisions/D068-keyboard-first-standard.md)). A list's selection is one cursor that the keyboard writes and the pointer borrows ([D054](../decisions/D054-list-motion-is-one-cursor-in-qs-ui.md)). A container owns one inset box ([D050](../decisions/D050-container-layout-contract.md)). Every component lands in the Gallery before a screen uses it.

The one exception is a plugin whose design must look the same under every theme: it owns its look through an `appearance` table the same judge resolves, fed only the theme's mode, accent and motion scale ([D023](../decisions/D023-plugin-owned-appearance.md)). A plugin's Settings page is built from its manifest schema, and text a user reads tells them the result and the action they need.

## Why

One table is the one place a value changes, so a theme that sets the palette restyles every surface in one commit. A frozen object of primitives is the only thing a plugin cannot mutate, and a QML colour's channels cannot be frozen, so colours are strings until `Theme.toColor` converts one. A judge that is a pure function lets a script run the shell's own judge, so a script and the shell cannot disagree, and whole-document refusal keeps a half-applied theme off the screen. Off-grid lengths put neighbouring components a pixel or two apart and text off the line rhythm, and a row that read the control size would grow every list when buttons grew.

A plugin-owned look names the two theme values its design wants as its only inputs, so a leak of any other theme value is unrepresentable; the motion scale is the reduced-motion control, not styling. A look value that equals a shipped token stays the plugin's own, so a theme that moves the shared value does not move it. Nothing infers a mode from a colour; the theme states `scheme.mode`.

One owner per behaviour means one check covers every site. A mouse drag that scrolls a view undoes text selection, so views take no mouse button. Qt's `Flickable` moves one pixel per pixel of swipe and stops, which no desktop list does, so one owner adds the gain and friction a user expects. A Qt window popup is placed once by Wayland inside the bar and never moves, so an overlay must be its own surface to leave the bar. One keyboard standard replaces per-plugin audits, and host-owned focus keeps the focus reason visible, so a ring shows for key-opened surfaces only. A passive layer that took keys could steal typing from the active client. Two highlights, a hover fill beside a keyboard highlight, come from each list drawing its own; a hover takes the selection only after the pointer has moved, so a list that scrolls under a resting pointer never steals the keyboard's selection. A `ListView` highlight takes no easing and menus lay rows out in a `Column`, so the cursor is a component, not a view feature. The Gallery is where a component is seen in every state before a screen hides one nobody drew.

One inset owner ends per-surface padding arithmetic, so a header, body and footer share one edge and a scroll bar's arrival never moves the layout. Content lower in a rounded container needs less inset, so clearance is computed from the radius rather than kept as a padding token. A gap of any width between a row's fill and a popover's border reads as a gutter.

A schema-built page gives a third-party plugin a full Settings page with no UI code. A user reads a label once: a diagnostic key, a reason code or a library's format syntax asks for knowledge they do not have, and a command in user text asks them to do what the shell can do for them.

## Rules

### Tokens

- Do read every colour, font, metric, radius, opacity and duration from `Theme`. `scripts/check-design-tokens.py` refuses a literal in shipped QML under its `literal-*` rules, and an unknown `Theme` path under `token-unknown`.
- Do publish every top-level group of the table as a read-only property of `Theme`; `group-unpublished` in the same check refuses a group left out, and `scripts/smoke/rows/theme.sh` reads each group back frozen.
- Never give the table or the judge an import, a Qt object or I/O. Both are `.pragma library` files, and `scripts/test-theme-logic.js` runs them under node.
- Do keep every length token on the 4 px grid, outside the optical classes: type, strokes, indicator sizes, 2 px steps inside a component, chip padding and motion distances. Controls are 24, 32 and 40 px, and row heights are their own tokens that never read the control scale. `scripts/test-theme-logic.js` walks every length token: [D063](../decisions/D063-design-scale-on-the-4-px-grid.md).
- Never set a text role below the floors of the shell's own roles, 13 px for reading text and 12 px for chrome; a plugin that owns its look meets the same floor. `type-floor` in `scripts/check-design-tokens.py` reads the floor from the table.
- Do draw rest, hover, pressed, focus, disabled and checked from their own tokens, each different from rest, and never draw hover or press on an item a click cannot change. Review holds this rule; `scripts/qml-tests/tst_button.qml` and `tst_toggles.qml` pin the shipped controls.
- Do keep resting, accent and status text, control borders and selected indicators readable at the floors `ThemeLogic.readabilityShortfalls` states. `scripts/check-theme-contrast.js` runs it over the shipped theme and every catalog entry.
- Do name a font family a theme may lack, and never ship a font file in a theme; the shell bundles Inter and JetBrains Mono and falls back to the bundled family of the token's default, logged once per theme.

### Appearance

- Do let a plugin own its look only through the `appearance` file its manifest names: a `.pragma library` file exporting `TOKENS` and `LIGHT`, judged by `ThemeLogic` against the theme's mode, accent and motion scale alone. `PluginLogic.validateManifest` refuses another shape, pinned by `scripts/test-plugin-logic.js`, and `appearance-refused` in `scripts/check-design-tokens.py` refuses a table the judge refuses.
- Never read a `Theme` member other than `appearance` in such a plugin, and never name a path the look lacks. `theme-read` and `look-unknown` in `scripts/check-design-tokens.py` refuse both.
- Do bind the judged look once and read every value as `look.<path>`; fail loudly on a null look, and never draw what the judge refused.
- Do hand `Pane`, `SlimScrollBar` and `ListCursor` the look's own values, and read no shared spacing token.
- Do stop a non-duration animation while the motion scale is 0.

### Components

- Do extend a `QtQuick.Templates` type and import no Quickshell module except in an overlay, so `scripts/qml-unit.sh` runs every component offscreen.
- Do land a `qs.Ui` guarantee with a test under `scripts/qml-tests/` and one mutation in `scripts/test-qml-unit.sh`.
- Do log an error and draw the default for an unknown `variant`, `size`, `role`, `tone` or `level`, and set `Accessible.name` from the control's text; `IconButton` requires `label`.
- Do open every popover, tooltip, menu and select list as a Quickshell `PopupWindow` with a focus grab, so Escape and a press outside close it; `Tooltip` alone takes no grab. `scripts/smoke/rows/overlays.sh` reads each beside a copy without the grab.
- Do let `Scrim` and a `Dialog` card take the presses, hover and wheel on themselves, so nothing under them answers; a scrim's click-away never answers a click on the card. `scripts/smoke/rows/automations.sh` clicks a card over its scrim.
- Do draw text a caller hands a row as plain text, never markup. `scripts/qml-tests/tst_layout.qml` pins it.
- Do use `InfoButton` for one short explanation beside a row label. Hover and keyboard focus show it in the icon's tooltip; a click opens it in a dialog, which returns focus to the icon when it closes.
- Never give a decorative component such as `VoiceOrb` or `QrMatrix` a pointer handler, a process, a file, a cache or a secret store, so a passive layer that draws it stays input-free ([D026](../decisions/D026-passive-layers-are-a-capability.md)). `scripts/qml-tests/tst_voiceorb.qml` and `tst_qrmatrix.qml` pin it, and a shader's driver stops when the item, its window or `motion.scale` is off.
- Do load every inline image through `ImagePool`, so nothing decodes on the GUI thread. `scripts/qml-tests/tst_imagetext.qml` pins it.
- Do keep `SlimScrollBar` free of theme reads, so a plugin-owned look can draw it; `scripts/qml-tests/tst_slimscrollbar.qml` pins it.
- Do compose `BarItem` for every bar widget and workspace pill, `FormRow` for every key/value row and `BindField` for every bind row, so Settings and the Key Hints window draw one row from one owner. `scripts/smoke/rows/bar.sh` holds every item to the bar's centre within one pixel.
- Do add a new component to the Gallery in the same change, in every variant and state, with a focused example for a focusable control. `scripts/smoke/rows/gallery.sh` refuses a missing component, a missing focus example and an example past the window's edge.
- Never edit `shell/Ui/icons/Lucide.js`; run `scripts/vendor-lucide`. `scripts/test-lucide-data.js` pins the data.

### Pointer

- Do declare `PointerCursor` in every element that takes a click, a plugin's `MouseArea` included, and never write `Qt.PointingHandCursor`. `scripts/check-pointer-cursor.py` refuses both under `cursor-missing` and `cursor-literal`; a `// pointer-cursor-exempt: <reason>` line directly above a click-away area or a scroll bar exempts it, and a marker with no reason exempts nothing.
- Do set `acceptedButtons: Qt.NoButton` on every `Flickable`, `ListView` or `GridView`; `ScrollArea` sets it once. `mouse-drag` in the same check refuses a view without it, with no exemption.
- Do declare `TouchpadScroll { view: <the view> }` in every view a control or plugin declares. `scripts/qml-tests/tst_touchpadscroll.qml` pins the motion, and `scripts/smoke/rows/settings.sh` and `gallery.sh` send a real swipe.

### Keyboard

- Never ship a click area without a key path, or a focusable item without a focus indicator: draw `FocusRing` while `visualFocus` holds. `scripts/check-keyboard.py` refuses both, planted by `scripts/test-check-keyboard.py`, and `vgs-plugin check` runs it on a plugin tree.
- Do mark `// keyboard-path: <how>` or `// focus-indicator: <what>` above the item only when a present mechanism supplies it; the marker exempts nothing missing. The same check reads the marker.
- Do let Tab follow reading order and skip hidden, disabled or unusable items, restore focus to a popup's opener when it closes, and activate a button-like control on Enter, Return and Space.
- Do open a surface on its primary input, else its list, else its body, with `Qt.ShortcutFocusReason` for a key or IPC and `Qt.MouseFocusReason` for an anchored click; never on an action that installs, removes or changes the system. `scripts/smoke/rows/surfaces.sh` pins it.
- Do make a composite one tab stop with arrows inside; an arrow never runs an action. Route movement, Home, End, pages, activation and type-ahead through `KeyNav`. `scripts/test-key-nav-logic.js` pins both.
- Do let Escape back out one level; a local edit or search clear may consume it first.
- Do keep a modal's Tab inside with `Keys.onTabPressed` on each action. `scripts/qml-tests/tst_dialog.qml` pins it.
- Never give the bar keyboard focus; a widget action has a global shortcut or a launcher path. `scripts/smoke/rows/bar.sh` pins it.
- Never give a passive layer such as a toast the keyboard; the inbox is a toast's keyboard path.
- Do give a surface at most one hint row; obvious keys stay implicit.

### Motion

- Do make every animation read a `motion` token, so `motion.scale` 0 stills the shell; a wait that is not an animation is a `number` token. `literal-duration` in `scripts/check-design-tokens.py` refuses a literal duration.
- Do give a list of selectable rows one `ListCursor` and let rows enter through `ListEntrance`; never a per-row hover fill beside it. `scripts/qml-tests/tst_listcursor.qml` and `tst_overlays.qml` pin it, with one mutation each in `scripts/test-qml-unit.sh`.
- Never give a cursor to a list whose highlight marks a state, or whose rows are rows of controls.
- Do declare the cursor in an item that paints nothing; it draws under the rows, and logs an error for a parent that paints a fill.
- Do call `snap()` before an opening or a rebuild sets the selection, `disarm()` on a keyboard step, a rebuild or a filter, and `arm()` to let the next hover take the plate at once. `tst_listcursor.qml` pins each.
- Do let a pick list move its selection on hover and a navigation list keep it.
- Do take every cursor timing from the `motion.list` tokens; a plugin-owned look hands its own table in the shape of `motion.list`.
- Do land every step at once at `motion.scale` 0. `scripts/smoke/rows/list-motion.sh` reads it.

### Layout

- Do compose `Pane` for every window, dialog, panel, popover and overlay, and hand it `padding`, `cornerRadius`, `bodySpacing` and `gap` only from a plugin-owned look; never a second inset implementation. `scripts/qml-tests/tst_pane.qml` pins the box and the footer.
- Do put a boxed child's box, and unboxed text, on the inset edge, and let each child pad itself; never add a second inset inside a container. `scripts/smoke/rows/manager.sh` holds every Settings field to one label edge and one control edge.
- Do keep a scroll bar inside the right inset strip and a footer outside the scrolling body.
- Do clear a rounded corner through `Inset.clearing` in `shell/Commons/Inset.js`; never hand-pad for a curve. `scripts/test-inset.js` pins the rule and `scripts/qml-tests/tst_spacing.qml` reads `Toast`.
- Do let a header's leading `IconButton` put its glyph, not its box, on the content edge; it is the one child that may reach into the inset.
- Do make every one-line control `size.control.md` tall with `control.gap` between icon and text, and every row `row.paddingX` a side and one `row.height`, Settings rows included, so metadata and setting rows align. `tst_spacing.qml` reads them under the defaults and a moved theme; `scripts/smoke/rows/manager.sh` reads every field row's height.
- Do put a group's lines in a `GroupList`; a surface states no gap and no divider colour. `scripts/qml-tests/tst_grouplist.qml` pins it.
- Do fill a popover list's rows to the border, with the row's own side padding carrying the text inset, and cut the list under a rounded corner through `ListMask`; never a gutter. `scripts/qml-tests/tst_overlays.qml` reads a square and a rounded theme.
- Do size a summoned popup to `OverlayState.room`, so it fits its content up to its share of the screen and then scrolls.
- Do give form feedback as plain sentence-case text under the control; a chip, a fill or capitals only for a state the user must act on now.
- Do pair `text.label` with `text.value` in a key/value row, and use `windowTitle` for a window title and `h3` elsewhere; `h1` and `h2` are for documents.

### Copy

- Do write text a user reads in ASD-STE100 Simplified Technical English: short sentences, one idea each, active voice, one word per thing. Say what the feature does for the user or what the user must do, and name the result of a check, never its internal operation.
- Do give a plugin description one or two short sentences with no command and no feature list.
- Do give a hint one short sentence, and remove it when the label already says it; longer help goes in an info dialog.
- Do keep diagnostic keys, reason codes and command errors in logs; show a plain sentence that explains the result or the action. A field made to show a technical value may name it.
- Never tell the user to run a command, except a by-hand requirement notice for a step VGS cannot run on this system ([D061](../decisions/D061-no-manual-commands.md)). `scripts/check-user-commands.py` refuses the text elsewhere. A plugin README keeps button commands behind Show command details.
- Never show an unsupported extra to a consumer ([D075](../decisions/D075-consumer-features-need-no-developer-setup.md)). `scripts/test-plugin-extras.js` pins it.
- Do map plugin-owned messages before the plugin shows them; keep a user's own commands, their output and child command streams unchanged.
- Do keep developer logs, code comments, developer documentation and machine-readable output technical; a component preview may name the component, property or state it shows.

### Settings pages

- Do build every Settings page and field from the plugin's manifest schema; no plugin ships page code, and the widget each entry type draws stays in the code of `shell/plugins/vgs.settings/` ([D032](../decisions/D032-settings-plugin-and-manifest-settings-convention.md)). `scripts/test-plugin-logic.js` pins the schema, and `scripts/smoke/rows/settings.sh` reads the drawn page back.
- Never make a user type a library's format syntax: a format-like string setting declares `presets` or a status-fed option list, and a format string is judged before it is written ([D077](../decisions/D077-settings-schema-presets-and-row-rhythm.md)). `PluginLogic.validateManifest` refuses a `format` without `presets`, pinned by `scripts/test-plugin-logic.js`, and `scripts/test-setting-values.js` holds the format judge.

## The canonical example

`shell/Ui/controls/IconButton.qml`: a `QtQuick.Templates` button, every value from a token, `PointerCursor` and `FocusRing` declared, an `Accessible.name` from its required label, and a Gallery entry per variant. Copy it. For a plugin-owned look, copy `shell/plugins/vgs.launcher/Appearance.js` with `Launcher.qml`: one table, one bind, every value through `look`.

## Revisit when

An editor resolves `qs` modules for plugin authors so typed properties would give completion; a judge needs a QML type node cannot host; a theme package format ships font files; a plugin-owned look needs a third theme input or a theme must restyle it after all; Qt sends `xdg_popup.reposition` for a window popup and bounds it by the screen; a surface needs an input or keyboard model the shared owners cannot express; a list needs more than one selection plate; a child must bleed outside the inset box or a popover list gains a header or footer; a setup step needs input a masked field or a TUI cannot take.

## Not governed

The theme package format, apply and targets, which are [themes.md](themes.md). Each component's properties and signals, which are its file header and its `scripts/qml-tests/tst_*.qml`. The compositor-side capture of keys, which is [hyprland.md](hyprland.md). The launcher's own curves, slide and edge light, which its appearance table owns. The wording of a decision record or an architecture doc, which the docs-writing skill holds.
