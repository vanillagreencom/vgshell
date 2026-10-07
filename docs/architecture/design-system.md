# One token table and one component library draw every surface

Read before touching a token, the theme judge, `Theme`, a component of `qs.Ui`, a plugin-owned look, a pointer, keyboard or focus path, a Settings field, or text a user reads.

## The approach

Every value a surface draws with comes from one table, `shell/Commons/Tokens.js`, read as `Theme.<group>.<token>`. One pure judge, `shell/Commons/ThemeLogic.js`, resolves a theme document against the table, and `Theme` publishes each group frozen ([D015](../decisions/D015-tokens-are-a-judged-table.md)).

The component library `qs.Ui`, listed in `shell/Ui/qmldir`, is the only code that turns a token into a drawn pixel. A screen composes its components and draws no control of its own. A control extends a `QtQuick.Templates` type ([D017](../decisions/D017-templates-and-path-icons.md)), and an overlay is a Quickshell `PopupWindow` anchored to the item that declares it ([D018](../decisions/D018-overlays-are-quickshell-popups.md)).

Each input behaviour has one owner in `qs.Ui`. `PointerCursor` draws the pointing hand, `TouchpadScroll` moves a view under a touchpad swipe, `KeyNav` moves through a composite, `FocusRing` shows focus, `ListCursor` draws a list's selection ([D054](../decisions/D054-list-motion-is-one-cursor-in-qs-ui.md)) and `Pane` owns a container's inset ([D050](../decisions/D050-container-layout-contract.md)). Every pointer action has a keyboard path ([D068](../decisions/D068-keyboard-first-standard.md)).

A plugin whose design must look the same under every theme owns its look through an `appearance` table. The same judge resolves it, fed only the theme's mode, accent and motion scale ([D023](../decisions/D023-plugin-owned-appearance.md)). A plugin's Settings page is drawn from its manifest schema ([D032](../decisions/D032-settings-plugin-and-manifest-settings-convention.md)). Text a user reads states the result and the action the user takes.

## Why

One table is the one place a value changes, so a theme restyles every surface at once. A literal value or a private control is a second style system: a theme change misses it, and it draws states nobody checked in the Gallery.

One owner per input behaviour lets one check cover every site. A keyboard, pointer or touchpad user then gets the same behaviour on every screen, and no screen locks one of them out.

A plugin-owned look names the theme values its design takes as its only inputs, so no other theme value can leak into it. The motion scale is one of them because it is the reduced-motion control, not styling.

A schema-built Settings page gives every plugin a full page with no UI code and the same rows. A user reads a label once. A diagnostic key, a reason code, a format syntax or a command asks for knowledge or work the shell should carry.

## Rules

### Tokens

- Do read every colour, font, metric, radius, opacity and duration from `Theme`. `scripts/check-design-tokens.py` refuses a literal in shipped QML under its `literal-*` rules, and an unknown `Theme` path under `token-unknown`.
- Do publish every top-level group of the table as a read-only property of `Theme`. `group-unpublished` in `scripts/check-design-tokens.py` refuses a group left out.
- Never give the table or the judge an import, a Qt object or I/O, so a script runs the shell's own judge. `scripts/test-theme-logic.js` runs both under node.
- Do keep every length token on the 4 px grid or in a named exception ([D063](../decisions/D063-design-scale-on-the-4-px-grid.md)). `scripts/test-theme-logic.js` walks every length token.
- Do keep the shipped theme and every catalog entry readable at the floors `ThemeLogic.readabilityShortfalls` states. `scripts/check-theme-contrast.js` judges them.
- Do draw rest, hover, pressed, focus, disabled and checked from their own tokens, each different from rest, and never draw hover or press on an item a click cannot change. Review holds it; `scripts/qml-tests/tst_button.qml` and `tst_toggles.qml` pin the shipped controls.

### Appearance

- Do let a plugin own its look only through the `appearance` file its manifest names. `PluginLogic.validateManifest` refuses another shape, and `appearance-refused` in `scripts/check-design-tokens.py` refuses a table the judge refuses.
- Never read a `Theme` member other than `appearance` in such a plugin, and never name a path the look lacks. `theme-read` and `look-unknown` in `scripts/check-design-tokens.py` refuse both.
- Do bind the look once through `Theme.appearance`, read every value as `look.<path>`, and draw nothing on a null look. Review holds it.
- Never give a plugin-owned look a text size below the shell's smallest text role. `type-floor` in `scripts/check-design-tokens.py` refuses it.
- Do hand every `qs.Ui` component a plugin-owned look draws with the look's own values; a component left on its defaults draws the shared tokens. Gap: no check reads which values a plugin hands a component.

### Components

- Do compose `qs.Ui` components, and never write a private control for something a component draws. Review holds it.
- Do add a new component to the Gallery in the same change, in every variant and state, with a focus example for a focusable control. `scripts/smoke/rows/gallery.sh` refuses a component `qmldir` lists that the Gallery lacks, and a missing focus example.
- Never give a decorative component, such as `VoiceOrb` or `QrMatrix`, a pointer handler, a process, a file, a cache or a secret store, so a passive layer that draws it stays input-free ([D026](../decisions/D026-passive-layers-are-a-capability.md)). `scripts/qml-tests/tst_voiceorb.qml` and `tst_qrmatrix.qml` pin it.

### Pointer

- Do declare `PointerCursor` in every element that takes a click, a plugin's `MouseArea` included, and never write `Qt.PointingHandCursor`. `scripts/check-pointer-cursor.py` refuses both under `cursor-missing` and `cursor-literal`; a `// pointer-cursor-exempt: <reason>` line exempts a click-away area or a scroll bar.
- Do set `acceptedButtons: Qt.NoButton` on every `Flickable`, `ListView` or `GridView`, so a mouse drag selects text instead of scrolling. `mouse-drag` in `scripts/check-pointer-cursor.py` refuses a view without it.
- Do declare `TouchpadScroll { view: <the view> }` in every view. `touchpad-scroll` in `scripts/check-pointer-cursor.py` refuses a view without it.

### Keyboard

- Never ship a click area without a keyboard path, or a focusable item without a focus indicator. `scripts/check-keyboard.py` refuses both, and `vgs-plugin check` runs it on a plugin tree.
- Do mark `// keyboard-path: <how>` or `// focus-indicator: <what>` only where a present mechanism supplies it; the marker exempts nothing missing. Review holds it.
- Do make a composite one Tab stop whose arrows move through `KeyNav`, and never let an arrow run an action. Review holds it; `scripts/test-key-nav-logic.js` pins `KeyNav`.
- Do give a surface its initial focus on its primary input, else its list, else its body, and never on an action that installs, removes or changes the system. Review holds it.
- Never give the bar keyboard focus; a widget action has a global shortcut or a launcher path. Gap: no check reads the bar window's keyboard focus.
- Never give a passive layer the keyboard; the inbox is a toast's keyboard path. `scripts/smoke/rows/layers.sh` pins the layer host.

### Motion

- Do make every animation read a `motion` token, so `motion.scale` 0 stills the shell. `literal-duration` in `scripts/check-design-tokens.py` refuses a literal duration.
- Do stop an animation no duration drives, such as a shader clock, while `motion.scale` is 0. Review holds it.
- Do give a list of selectable rows one `ListCursor`, and never a per-row hover fill beside it. `scripts/qml-tests/tst_listcursor.qml` and `tst_overlays.qml` pin it.

### Layout

- Do compose `Pane` for every window, dialog, panel, popover and overlay, and never write a second inset. `scripts/qml-tests/tst_pane.qml` pins the box.
- Do clear a rounded corner through `Inset.clearing` in `shell/Commons/Inset.js`, and never hand-pad for a curve. `scripts/test-inset.js` pins the rule.

### Copy

- Do write text a user reads in ASD-STE100 Simplified Technical English. Name the result of a check or the action the user takes, never the internal operation. Review holds it.
- Do keep a plugin description to one or two short sentences with no feature list, and a hint to one sentence; longer help goes behind an `InfoButton`. Review holds it.
- Do keep diagnostic keys, reason codes and command errors in the log, and map a plugin's own messages to a plain sentence before the plugin shows them. A user's own commands and their output stay unchanged. Review holds it.
- Never tell the user to run a command ([D061](../decisions/D061-no-manual-commands.md)). `scripts/check-user-commands.py` refuses the text.
- Never show an unsupported extra to a consumer ([D075](../decisions/D075-consumer-features-need-no-developer-setup.md)). `scripts/test-plugin-extras.js` pins it.

### Settings pages

- Do declare a plugin's settings in its manifest schema, and never ship page code for its Settings page. `scripts/test-plugin-logic.js` pins the schema.
- Never make a user type a library's format syntax ([D077](../decisions/D077-settings-schema-presets-and-row-rhythm.md)). `PluginLogic.validateManifest` refuses a string setting without `presets` or `optionsFrom`, and `scripts/test-setting-values.js` holds the format judge.

## The canonical example

`shell/Ui/controls/IconButton.qml` is a control that meets every rule above. Copy it. For a plugin-owned look, copy `shell/plugins/vgs.launcher/Appearance.js` with `Launcher.qml`.

## Revisit when

A value a surface needs cannot be a token; a surface needs an input or keyboard model the shared owners cannot express; a plugin-owned look needs a third theme input, or a theme must restyle it after all; a Settings field needs a control the manifest schema cannot declare.

## Not governed

The theme package format, apply and targets, which are [themes.md](themes.md). The compositor-side capture of keys, which is [hyprland.md](hyprland.md). Each component's properties, signals and key handling, which are its file header, its test under `scripts/qml-tests/` and the vgs-plugin skill's API reference. A plugin-owned look's own values, which its appearance table holds. Developer logs, code comments, developer documentation and machine-readable output, which stay technical; a Gallery preview may name the component, property or state it shows.
