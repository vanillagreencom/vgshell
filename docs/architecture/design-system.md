# One token table and one component library draw every surface

Read before touching tokens, the theme judge, `Theme`, `qs.Ui`, a plugin-owned look, pointer or keyboard input, focus, Settings fields or user-facing text.

## The approach

Every view meets the polish of Vercel's web app or a standard modern consumer app (owner, 2026-10-06). Values come from `shell/Commons/Tokens.js`; the pure `ThemeLogic.js` judge resolves them and `Theme` publishes frozen groups ([D015](../decisions/D015-tokens-are-a-judged-table.md)). Appearance values resolve once over the theme ([D104](../decisions/D104-appearance-values-over-the-theme.md)).

Screens compose `qs.Ui`. Controls extend QtQuick Templates ([D017](../decisions/D017-templates-and-path-icons.md)); overlays use anchored Quickshell popups ([D018](../decisions/D018-overlays-are-quickshell-popups.md)). Shared components own input, focus, spacing and their own geometry; their source headers state it, and this doc does not repeat it. A plugin-owned appearance table has only the inputs [D023](../decisions/D023-plugin-owned-appearance.md) permits. A look governs only the files that bind it, so one surface of a plugin can own its look while the plugin's other surfaces follow the theme ([D119](../decisions/D119-plugin-look-binds-per-surface.md)). Settings pages come from manifest schema ([D032](../decisions/D032-settings-plugin-and-manifest-settings-convention.md)).

## Why

A private control or literal drawing value creates a second style system that themes and shared accessibility fixes cannot reach. One owner per input behavior gives pointer, keyboard and touchpad users consistent access. Shared layout keeps text and controls aligned as content, fonts and scale change.

## Rules

### Tokens

- Read every drawing value from `Theme`. Publish each table group through a read-only Theme property. `scripts/check-design-tokens.py` checks literals, unknown paths and unpublished groups.
- Keep the table and judge free of imports, Qt objects and I/O. Keep the layout scale on its grid and row heights independent of control size. `scripts/test-theme-logic.js` runs them under Node and owns grid exceptions.
- Give a component-specific text style its own role instead of changing a shared role. Review holds it.
- Draw body and row copy at one text size, the base size the `body` and `item` roles share (owner, Slack 1794977560.761489). A text drawn at another size names its reason and has its own role. Review holds it.
- Keep shipped and catalog themes above `ThemeLogic.readabilityShortfalls`' floors; `scripts/check-theme-contrast.js` checks them. The screensaver canvas stays opaque black, and its inks and gradient phases use the judged screensaver tokens.
- Judge drawn hints at native size against their actual fill, not token contrast alone. Sample straight-stroke interiors at the same positions before and after by median RGB, excluding edges and isolated extremes. Measure stem width by summed coverage; sample a peak-column center only when the stem spans two pixels or both neighbors have under half coverage. Repeat text under its displayed disabled reason is exempt while the reason covers it. Screenshot review holds this; `scripts/test-theme-logic.js` checks rendering margins.
- Identify a labelled button through readable label text; its resting transparent fill and border need not meet the boundary floor. On wallpaper where no modal border can hold, the modal fill carries the layer. `ThemeLogic.readabilityShortfalls` judges modal tokens.
- Over wallpaper, use underlines and distinct indicator thicknesses for hover and selection where colour cannot distinguish them, and put failure and status text on the solid `carousel.failurePlate` with its danger mark. `scripts/test-theme-logic.js` checks the derived inks.
- Place leading icons through `Label.topForLeadingIcon`, never fixed offsets. `scripts/qml-tests/tst_label.qml` checks placement.
- Draw no hover or press on an item whose click changes nothing. Bar items and icon buttons have no hover fill. Review holds composition; `scripts/qml-tests/tst_button.qml` checks the shared state tokens.
- Never replace `IconButton.background` or give an icon toggle a fill or border; its glyph carries the tones. A surface that owns its look passes them through `restColor`, `activeColor`, `onColor` and `ringColor`. `scripts/check-design-tokens.py` checks shared IconButton backgrounds; review holds private icon toggles.

### Appearance values

- Resolve user Appearance values only through `ThemeLogic.withAppearance`. `scripts/test-theme-logic.js` checks resolution.
- Use `radius.glass` for a zero-radius popup, menu, dialog or OSD only while glass is on. Preserve a positive theme or user radius and leave attached panels' `surface.radius` alone.
- Apply interface fonts only to sans and caps families. Accept no colour Appearance value ([D025](../decisions/D025-no-theme-override-layer.md)).
- Draw Hyprland-mapped values through `ValueSourceRow` ([D057](../decisions/D057-one-row-for-hyprland-mapped-values.md)).

### Appearance

- Load a plugin-owned look only from its declared appearance file. Bind once through `Theme.appearance`, use `look` paths and draw nothing on a null look. `PluginLogic.validateManifest` and `scripts/check-design-tokens.py` judge declarations and paths.
- Bind a look per surface: only files that bind `Theme.appearance` or read a `look` path their owner passes draw with the look, and they read no other Theme member ([D119](../decisions/D119-plugin-look-binds-per-surface.md)). Keep look text above the shell's smallest text-role floor, except the hint-only key-name role and the owner-requested calendar weekday and path chip roles. `scripts/check-design-tokens.py` and `scripts/test-check-design-tokens.py` check these boundaries.
- Keep launcher detail at least 4.5:1 against its fill and 1.25:1 apart from its resting title as drawn. `scripts/test-theme-logic.js` holds it.
- Use shadows only to lift light ink from dark glass; draw none for dark ink on light cards. `scripts/test-notifications-logic.js` checks notification shadows.
- Pass the look's own values to composed controls, except the shared system key hint. Draw a look's own button through `Button` with the look's values, never a private control. Review holds supplied values; `scripts/qml-tests/tst_button.qml` checks the inputs.
- Draw Jarvis's overlay on lens-form glass plates in its look's `plate` values, each card in one plain ink, with no text shadow and nothing behind the orb. `scripts/qml-tests/tst_jarvis_plates.qml` checks the plates and `scripts/check-theme-contrast.js` holds every ink on its plate; rendered UI review judges the orb.
- Pad Jarvis's words' card by the look's side padding; on a narrow side it gives up only what its widest word needs, so lines break only at spaces. Review holds the words' card; `scripts/qml-tests/tst_jarvis_bubble.qml` checks the state card.
- Change the glass tint's strength only in `plate.tint` in `shell/plugins/vgs.jarvis/Appearance.js`, and derive every other glass value from it. `scripts/qml-tests/tst_jarvis_plates.qml` checks it has one source.
- Draw a held request's answers as two equal capsules, the declining answer first, the confirming one in the accent, except on a request that needs a press, where both draw quiet (Jarvis decision for the owner, 2026-11-12). `scripts/qml-tests/tst_jarvis_prompt.qml` checks the answers.

### Glass plates over wallpaper

- Give text, icons and fine drawing over the wallpaper a `GlassSurface` plate as their ground, in new work and when a surface is next redrawn. A fading field or a shadow does not bound content.
- Keep Jarvis's material and light inks the same in both modes, chosen against the brightest ground ([D132](../decisions/D132-look-owned-glass-inputs.md)). `scripts/qml-tests/tst_jarvis_plates.qml` checks both modes.
- Choose each ink against its plate's worst ground: the fill over white for a dark plate, over black for a light plate. Judge a label on a filled control on that fill over the plate. `scripts/check-theme-contrast.js` holds 4.5:1 for the looks it judges.
- Hand each plate `lens`, `elevation: "none"` and `standard` from the look. `scripts/qml-tests/tst_glasssurface.qml` checks the form.
- Ask the compositor for blur through a layer rule in the plugin's manifest, with `ignoreAlpha` under every plate's body alpha and over its band's, and keep the body's alpha above the core rule's 0.7. The fill alone carries the contrast, since blur can be off. `scripts/qml-tests/tst_jarvis_plates.qml` reads both alphas.
- Pad content that stands beside a plate past its band. `scripts/qml-tests/tst_glasssurface.qml` checks `contentInset`.
- The lens form is the material. The notification card and inbox header, the launcher card, `Menu`, `Popover`, `Tooltip`, `Select`, the floating `Card`, `ModalDialog`, the level OSD and the display trial banner still draw the flat form; move each in its own item. The last one deletes the sheen, the hairline and their `Theme.glass` tokens, and gives `lens` a `Theme.glass` default.
- Keep each plate's box clear of every other plate's, and never fade a plate's own opacity; fade its content.

### Components

- Compose shared controls instead of private equivalents. `FormRow` allocates each boxed settings input the available value-column room up to `control.maxWidth`; every box shares that column's start and end edges. A shortcut's tools stay outside its box, beyond the shared end edge while trailing room permits, else below the box. Sliders and their readings share the allocation, and switches keep their compact shape. An input outside a settings row, such as the Capture panel's target tiles or a standalone search, keeps the width its layout gives it. Pages and plugins set no settings input width. `scripts/check-design-tokens.py` checks page-owned widths; the QML and Settings smoke checks hold allocation and geometry. Review holds composition.
- Give a button beside an input the input's height, `Button.size: "md"` beside a field (owner, Slack 1794266396.003919), as the Jarvis console's round Send and Stop match the model and effort choices inside its message box. A one-line field's own buttons, such as Clear, stay small, and a text-link `RowAction` after a reading stays text height. `scripts/qml-tests/tst_power_view.qml` checks the Stay awake control; review holds the rest.
- Compose a list row from `ContentRow`, or `NavigationRow` for a row whose whole box takes the click, such as a page row, a `Disclosure` or a `DeviceRow`, and give no row its own `contentItem`. Put a row's state, needed actions and removing action in `ContentRow`'s `status`, `detail`, `actions` and `menuActions`: the state with its tone's mark, never a chip; each needed action a small secondary Button; the removing action in the row menu, its entry the label alone led by the trash mark (owner, Slack 1794380399.262309; Jarvis decision 1794380517; [VGS-2458](https://linear.app/vanillagreen/issue/VGS-2458)). Screens still on a bare `ListItem` move in [VGS-2364](https://linear.app/vanillagreen/issue/VGS-2364). `scripts/qml-tests/tst_settings_rows.qml` checks the layout; review holds composition.
- Put a navigation row's badges and switches in `accessories`, never `trailing`. Review holds it.
- Use `TextField`'s `search` variant for standalone search, at the top of its content box and spanning its width, except the launcher's own pill field. The Plugins search sets `searchUnderline: false`. Form and password fields keep the default variant; Theme and Wallpaper browsers keep fieldless typing-to-filter. Review holds placement.
- Give every input control's resting border `color.borderControl` through its role token; an open dropdown list uses the menu border. `ThemeLogic.readabilityShortfalls` judges the roles.
- Use `MessageRow` for conversations and asks, `ResultsFilter` for result filtering beside search, and `Badge`'s unread variant for unread counts. Keep accessible names complete.
- Draw a conversation's turns through `MessageRow`'s `turn`: the person's own turns right-aligned on the low-emphasis fill, `color.surfaceRaised`, with no border or time, and the other side's as text across the row. The Jarvis console draws Chat and History this way and shows no time on any row (owner, Slack 1794266396.003919). Review holds it.
- Stand an empty section's short line under its heading through `EmptyState`'s top placement, with no icon, as the console's History does; a view with nothing yet, such as the console's empty Chat, stays blank. `scripts/qml-tests/tst_emptystate.qml` checks the placement.
- Draw backgrounds through `Surface` or `GlassSurface` with the surface's standard token group; `glass-bypass` in `scripts/check-design-tokens.py` checks it. A `Card` alone in its own popup sets `floating`.
- Show widget counts only through `BarItem.count`, a second reading through `detail` (owner, Slack 1793643412.880369). Show a held state as the item's own icon in `bar.active` through `BarItem.iconTone`, the values keeping the bar's colour, never a second icon or a badge (Jarvis note 1793716109; owner, Slack 1794789633.431859). Show a live state through `BarItem.stateDot` in a `Theme.color` role. Name each state in the label. `scripts/qml-tests/tst_baritem.qml` checks the forms.
- Show an error, warning or information notice through `Callout`, never as tinted text. Use `danger` when something stops a feature, `warning` when something limits or delays one, and `info` for neutral information the reader needs first. The banner reads its container's ground and blends the shared `callout.background` over it; callers declare no level or fill. Only the title is bold; messages and links use regular weight. Put actions at the bottom as `RowAction` links, never a trailing button; a title-less one-line notice may keep its page link in the text. The caller owns hiding and any saved choice. Words another program supplies use `plain`. `scripts/qml-tests/tst_callout.qml` checks the component.
- Draw hints through `KeyHints`, without a private backing or shadow, and keep the shared theme hint on plugin-owned looks, the narrow D023 exception. Supply `backgroundContext` only for a plate, private fill or outside surface the ancestor cannot publish. `scripts/qml-tests/tst_hintground.qml` checks ground inheritance.
- Add every new component to the Gallery in all variants and states, with a focus example when focusable. `scripts/smoke/rows/gallery.sh` checks coverage.
- Keep notification cards bounded in toasts and lists: one title line and at most two body lines, with ellipsis, centered media and a centered right-side tray. Hover and selection overlay full-label actions at the right, over a soft Qt Quick gradient, without changing the title or body geometry. Keep the text column at its resting width through both fades; put actions after the first two in the shared Menu when more than three exist. `scripts/qml-tests/tst_notification_tray.qml` and `tst_notification_scroll.qml` check the contract.
- Wrap values and menu choices instead of eliding them, through `LineBreak.atSpaces` (Jarvis decision 1792672338-3717266-30335). Jarvis's reply card under the bar J is one exception: it cuts an answer at 4 lines and says how to read the rest (owner, Slack 1793989894). `scripts/qml-tests/tst_settingfield.qml`, `tst_overlays.qml` and `tst_message_row.qml` check them.
- Disable through `disabledReason`, not `enabled: false` alone, with a plain cause and next step. Offer `unlock` only for a single action that removes the condition. `scripts/check-disabled-reasons.py` reports missing reasons.
- Keep decorative components free of pointer handlers, processes, files, caches and secret stores ([D026](../decisions/D026-passive-layers-are-a-capability.md)). Review holds this boundary.
- Draw a fading field behind a passive layer's decoration through `RadialBackdrop`, passing every input from the look. `scripts/qml-tests/tst_radialbackdrop.qml` checks it.

### Pointer

- Put `PointerCursor` on click targets and write no literal pointing-hand cursor. Exempt only click-away areas and scroll bars with a reason. Set views' `acceptedButtons` to `Qt.NoButton` and give each a `TouchpadScroll`. `scripts/check-pointer-cursor.py` checks these boundaries.
- Scroll only for keyboard navigation, focus change, opening or explicit jump. Hover never moves keyboard focus or scroll position. `scripts/qml-tests/tst_overlays.qml` checks hover.
- Give a passive layer's decoration pointer input only while it offers an action, and only on the part that offers it ([D026](../decisions/D026-passive-layers-are-a-capability.md)). `scripts/qml-tests/tst_jarvis_overlay.qml` and `scripts/smoke/rows/jarvis-bubble.sh` check Jarvis's region.

### Keyboard

- Give every click a keyboard path and every focusable item a focus indicator. `scripts/check-keyboard.py` checks them. Use a keyboard-path or focus-indicator marker only for an existing mechanism; review holds the marker's truth.
- Make a composite one Tab stop and move within it through `KeyNav`. Arrows never run actions. Hosts own Escape and initial focus: primary input, else list, else body, never an installing, removing or system-changing action. Review holds these choices.
- Keep the bar unfocused except the widget-drag grab and its remove question. Give widget actions global shortcuts or launcher paths. Passive layers take no keyboard; the inbox supplies a toast's keyboard path. `scripts/smoke/rows/layers.sh` checks passive hosting; review holds bar focus.

### Motion

- Read animation durations from motion tokens and stop untimed clocks when motion scale is zero. `scripts/check-design-tokens.py` checks literal durations; review holds untimed animation.
- Run a shader clock only while its surface shows and motion scale is above zero, at the rate its look sets for the state. A state that can stay up all day moves slowly: Jarvis's orb moves in every state and only its rate changes (owner, overseer directive 1793742833; [jarvis.md § Overlay motion](jarvis.md#overlay-motion)). A paced look runs no FrameAnimation. `scripts/qml-tests/tst_jarvis_orb.qml` and `scripts/smoke/rows/jarvis-bubble.sh` check it.
- Open and close bar flyouts and `PassivePopup` with the shared fade and anchor-edge slide. `scripts/smoke/rows/surfaces.sh` and `scripts/qml-tests/tst_passive_popup.qml` check stillness.
- Give each clickable list one `ListCursor` for hover and press, declared beside positioners, never as a laid-out child. Keep content padded inside its row plate through the shared row, and report the plate box to a card or pane even while the pointer is away; no page adds a row margin. Rows use `lit` for selected ink and draw no hover fill. Only Menu and Select change selection on hover. Pass plugin-owned timing and plate values into shared motion. `scripts/check-pointer-cursor.py` checks row hover and placement.
- Call `rebuilt()` on row changes and `disarm()` for key steps or opening. Key models that would recreate every row. `scripts/qml-tests/tst_listcursor.qml` checks ownership.
- Draw one hover plate per panel. `scripts/qml-tests/tst_disclosure.qml` checks nested hover.

### Layout

- Keep a box's inner gap equal on all four sides, measured to drawn ink or the first control's box, never to a text line box. Use `ClearingInset` and one padding value per box group, never a private surface inset; plugin-owned looks pass their own padding. `scripts/qml-tests/tst_box_ink.qml` checks the drawn gaps.
- Compose `Pane` for windows, dialogs, panels, popovers and overlays. Put titles and descriptions in its title slot, align children to its content edge and use `Inset.clearing` for rounded corners. Never add a private inset or title margin. `scripts/qml-tests/tst_pane.qml` and `scripts/test-inset.js` check shared geometry.
- Put pending changes in the shared footer and timed trials or mandatory confirmations in centered modals. Review holds composition.
- Fit dialogs and popovers to content up to their height cap, then scroll. A fitted list of evenly pitched rows sets Pane's `bodyRowHeight`. `scripts/qml-tests/tst_scroll.qml` and `tst_pane.qml` check it.
- Place shell windows through token-derived output geometry and the one `OverlayState.windowRoom` cap; content beyond it scrolls. The launcher retains its own layer anchoring (owner, 2026-10-18). Resize mapped windows through compositor `placeWindow`. `scripts/smoke/app-window.sh` checks the cap.
- Animate summoned card height through `SurfaceHeight`. Mask flyout input to their cards. `scripts/qml-tests/tst_surfaceheight.qml` checks the shared owner; review holds host composition.
- Use SectionHeader for heading spacing, TabPages below tabs and shared FormRow/Field ink measurements between key/value rows. Never hand-space headings, rows or individual controls. Use `SavedSlider` for a plugin slider with a reading. `scripts/qml-tests/tst_section_spacing.qml` and `tst_settingfield.qml` check shared spacing. Owner authority for ink-to-ink Settings rows is Slack 1792188454.
- A status line that clears on a timer keeps its room, at the height of its tallest line, until its section is left. `scripts/qml-tests/tst_bluetooth_pair_line.qml` checks the Bluetooth pairing line; review holds the rest.
- Preserve text-row pitch independently of glyph content and recompute adjacency when rows move. No check covers a reordered SettingField.
- Use `GroupList` for groups and its shared dividers. Give popover lists no outer inset. `scripts/qml-tests/tst_grouplist.qml` checks them.
- Draw floating-terminal blocks through `bin/lib/tui.sh` and print no private blank line. `scripts/test-tui.sh` checks spacing.

### Copy

- Write user text in ASD-STE100 Simplified Technical English. State results and user actions, not diagnostic keys or internal operations. Map plugin messages to plain sentences; preserve user commands and output. Review holds wording.
- Use short action labels as icon-button tooltips. Use shared Tooltip, FormRow and disabled-reason placement instead of local positioning. `scripts/qml-tests/tst_formrow.qml` and `tst_reasontip.qml` check clearance.
- Keep descriptions to one or two short sentences and hints to one necessary sentence that adds a limit, side effect or condition, never a label restatement. Put further help behind InfoButton, each line one idea in at most two short sentences, with no blank lines in the source (owner, Slack 1792469888 and 1792470048). `PluginLogic.infoError` judges the source; `bin/lib/check-manifests.js` checks redundant hints; review holds meaning.
- Make info help explain the setting and the user's action in new-user terms, not implementation (owner, Slack 1792182387.487899 and 1792182511.072549). A one-sentence Settings hint has no full stop; longer hints end each sentence with one (Jarvis delegated ruling, 2026-10-13). `PluginLogic.validateManifest` checks punctuation.
- Never tell users to run commands ([D061](../decisions/D061-no-manual-commands.md)). A setup step requiring the user must have a clear Settings path or the feature does not ship ([D075](../decisions/D075-consumer-features-need-no-developer-setup.md)). `scripts/check-user-commands.py` checks command text; review checks the path.
- Link page, tab and section references through the shared page-reference form, a plugin's Keys section as `Settings/Keys`, and file and folder references through `PageReference.fileReference`, never a private opener (owner, Slack 1792189443). `scripts/test-page-reference.js` checks routing; `scripts/check-user-commands.py` checks page references.
- Give user-facing limits, sizes, counts and times help that explains why (owner, Slack 1792189443). Draw help as a dotted underline on the label through `InfoButton`, with no icon or help copy on hover. The label takes its own focus and click, separate from a toggle or other setting control, and opens the screen-centred `ModalDialog` (owner, Slack 1794964461.459499). `scripts/qml-tests/tst_infobutton.qml` checks the independent label; nested surface checks hold the modal path.
- Use shared link components, never Qt anchors or font underlining (owner, Slack 1792451091; Jarvis decisions 1792464386-2557738-17858 and 1792451829-3591639-28142). `scripts/check-design-tokens.py` checks forbidden forms.

### Settings pages

- Take spacing from the shared rhythm and row owners. A toggle is its own label-and-switch row. Keep the tab strip pinned below the title while content scrolls. `settings-gap` in `scripts/check-design-tokens.py` checks gaps; review holds composition.
- Declare Settings pages through manifest schema, never plugin page code. Settings contains only values the user changes there, including editable lists and stored keys beside their setting (owner, Slack 1792189351). Keep each field in its group and common widget fields in the shared order. `PluginLogic.validateManifest` judges placement; `bin/lib/check-manifests.js` checks widget order.
- Keep setup actions on Setup and passive readings on Details, and declare placement rather than infer it from names (owner, Slack 1792469982). `PluginLogic.statusPlacement` and `shell/plugins/vgs.settings/Steps.js` own classification.
- Give unfinished actionable steps one clear action. An unavailable step states why, what must change and the page where it changes. Never show To do with no action while a plugin is on (owner, Slack 1792182387.487899 and 1792182511.072549). `scripts/test-settings-steps.js` checks state and action consistency; review holds explanations.
- Keep all Setup actions as RowAction links. Route tool installation through the combined Tools notice, and show failed installs on the affected steps, never reopening the notice automatically (owner, Slack 1793683831). Show a disabled plugin's page-wide state once (owner, Slack 1792637978). `scripts/test-settings-steps.js` and `scripts/qml-tests/tst_settings_setup.qml` check them.
- Show secrets once in masked fields using the existing keyring. Presence reports storage state, never credential validity. `scripts/test-settings-steps.js` checks it.
- Offer presets or runtime choices instead of library format syntax, with same-plugin `choices` and stable ids. Preserve unavailable saved choices. `PluginLogic.validateManifest` and `scripts/test-setting-values.js` check declarations and values.
- Use declared `addChoice` and preview actions for discovery and previews; they choose no value. Start work caused by a setting only from the user's own page choice, never config reads, reloads or migrations ([VGS-1953](https://linear.app/vanillagreen/issue/VGS-1953), ruling 7). `scripts/test-plugin-status.js` checks handlers.
- Use Select for a setting that picks one value from a list. Keep SegmentedControl for a view filter that stores no setting and for previews. Labels fit the default label column; extra explanation goes in tooltip or info. `PluginLogic.validateManifest` and `scripts/qml-tests/tst_settingfield.qml` check those contracts.
- Use RowAction after a key/value reading and RowActions for several, never boxed buttons in a key/value line. Draw a `rows` field's whole-list `action` below its list as a secondary Button. Mark danger with a distinct icon as well as colour: trash alone only at the end of the item being removed, trash before other remove text. Place no icon-only control alone on a line (owner, Slack 1792184728 and 1792452164). `scripts/qml-tests/tst_rowaction.qml` and `tst_settings_rows.qml` check shared controls.
- Keep published row lists passive unless `folderProperty` declares a row's folder path. `scripts/qml-tests/tst_settings_rows.qml` checks the paths.
- Use shared BindField and ShortcutField for key editing. `scripts/qml-tests/tst_shortcutfield.qml` checks the shared control.

### Independent tools

- Present Settings' Open through the normal window host, even when its content entry is a panel. `PluginLogic.openRequest` and `summonSurface` own this choice; `scripts/test-plugin-logic.js` checks it.
- Draw no private window border or drag behavior; the compositor owns focus indication, move, tiling and close. Keep anchored bar flyouts and generic IPC summons on their declared hosts.
- Replace an existing flyout or layer when Open requests a window, without a second instance or discarding held work. Host lifetime review holds these boundaries.

## The canonical example

Copy `shell/Ui/controls/IconButton.qml` for a control. For a plugin-owned look, copy `shell/plugins/vgs.launcher/Appearance.js` with `Launcher.qml`.

## Revisit when

A value cannot be a token, shared input or layout owners cannot express a needed behavior, a plugin look needs another theme input, or schema cannot describe a Settings control. Revisit for content outside its inset, several simultaneous list plates, discovery beyond bounded choices or an owner change to the layout grid.

## Not governed

Theme packaging and targets belong to [themes.md](themes.md); compositor capture belongs to [hyprland.md](hyprland.md). Component contracts, geometry and interaction belong to their source headers and the vgs-plugin API. A plugin's own layout, such as notification cards and Jarvis's capsule placement, belongs to its code and tests. Developer logs, comments, documentation and machine-readable output remain technical; Gallery previews may name components and properties.
