import QtQuick
import QtTest
import Quickshell
import Quickshell.Hyprland
import qs.Commons
import qs.Core
import qs.Ui
import qs.Unit

// The overlays through the stand-in popup window: a popover opens and
// closes and counts in OverlayState, a menu moves its highlight and
// triggers by key and closes on a trigger but that of an entry that opens a
// submenu, which draws a chevron, or keeps the menu open, a select chooses by index and
// reads its text role, an empty select opens no list from a key or a click
// and shows neither the hand nor a chevron in its resting colour, a tooltip opens after the delay while the pointer
// rests and not under an open overlay. A menu
// taller than its maximum scrolls with a key's highlight kept in view, and
// a pointer resting at its edge or over a select entry part way past the
// list's bottom highlights the entry and scrolls nothing; a long select
// list opens with its choice in view. A menu jumps
// to the entry whose text starts with the letters typed, opens on its
// checked entry and draws its mark. A menu and a select's list draw their
// highlight through one ListCursor, which a hover moves only once the
// pointer moved since the last key; when the pointer leaves, a menu's
// highlight goes back to the entry a key chose or clears, and a select's to
// the entry the keyboard left it on. A menu opened by a key highlights its
// checked entry, else its first; one opened by the pointer highlights none
// until the pointer enters an entry or the first Up or Down lands where a
// key opening would have, Enter on it triggers nothing, and an opening
// that names no opener is refused. The first entry's highlight and a
// select's chosen fill meet the list's border at the top and both sides,
// under a square and a rounded theme, and stay inside a rounder corner;
// the bar of an overflowing list draws over a strip each entry keeps clear,
// exactly while the bar shows, and an overflowing menu is as wide as its
// widest entry with that strip once. Under a rounded theme a list is cut to its
// window's rounded interior, so a filled row half scrolled past the top and
// the bar's thumb at the top stay inside the curve; a square list draws no
// layer. An open select list covers a field under it whose bottom border
// ends 1 to 4 px below its entries, read from the page's and the list's
// images in a dark and a light theme. A short menu opens with no entry
// wrapped for a bar it never shows, is as wide as its longest entry, with
// equal side gaps, and only a menu of one short word takes the minimum width; an
// entry's icon is as tall as its text's capitals. A menu entry's text and
// shortcut draw a pixel under a field's, a select's and a list item's.
// A press in the anchor's window closes each overlay and reaches no item
// under it. A menu made and opened in one turn of the event loop, as a bar
// widget's is, shows its window on that first open with the cursor on the
// opening entry. The nested sandbox proves placement, real keys and the
// compositor's dismissal.
Item {
    id: root
    width: 300
    height: 240

    QtObject {
        id: activationOwner
        property var screen: null
        property Item contentItem: root
    }

    Item { id: host; width: 60; height: 26
        Popover { id: popover; width: 120; Item { width: 100; height: 40 } }
        Menu { id: menu
            MenuItem { text: "First"; onTriggered: root.triggered = 0 }
            MenuItem { text: "Second"; onTriggered: root.triggered = 1 }
            MenuItem { text: "Off"; enabled: false; onTriggered: root.triggered = 2 }
            MenuItem { id: wide; text: "An entry far wider than the menu's minimum width, with a shortcut"; shortcut: "Ctrl+Shift+W" }
        }
        Menu { id: nested
            MenuItem { id: submenuEntry; text: "Accounts"; opensSubmenu: true; checked: true; onTriggered: root.triggered = 10 }
            MenuItem { id: backEntry; text: "Back"; keepsOpen: true; onTriggered: root.triggered = 11 }
            MenuItem { id: leafEntry; text: "Quit"; onTriggered: root.triggered = 12 }
            MenuItem { id: uncheckedSubmenu; text: "Devices"; opensSubmenu: true }
        }
        Menu { id: mid
            MenuItem { text: "Rescan every plugin"; iconName: "refresh-cw"; shortcut: "R" }
        }
        // A bar widget's menu, and a menu of one short word.
        Menu { id: barMenu
            MenuItem { id: hideEntry; text: "Hide"; iconName: "eye-off" }
            MenuItem { id: settingsEntry; text: "Settings"; iconName: "settings" }
        }
        Menu { id: oneWord
            MenuItem { text: "Off" }
        }
        // A menu whose owner names its first choice, past a Back entry and
        // a checked one, as the tray's submenu does.
        Menu { id: homed
            home: () => 2
            MenuItem { text: "Back" }
            MenuItem { text: "Checked"; checked: true }
            MenuItem { text: "Chosen" }
        }
        Tooltip { id: tip; text: "hint" }
        Tooltip { id: longTip; text: "method=unknown path=/home/user/.local/share/vgshell/repo is where VGS runs from, and no package manager owns it" }
        Tooltip {
            id: detailsTip
            text: "17 updates waiting"
            details: [
                { label: "System", value: 14 },
                { label: "AUR", value: 2 },
                { label: "mise", value: "check failed" },
                { label: "Themes", value: 0 },
                "Checked 8:54 PM"
            ]
        }
        Menu { id: long
            Repeater {
                model: ["Bar", "Gallery", "Launcher", "Notifications", "Settings", "Themes", "Beta", "Clock", "Dock", "Echo", "Files", "Grid", "Help", "Inbox", "Jobs"]
                MenuItem { required property string modelData; required property int index; text: modelData; checked: index === root.chosen }
            }
        }
    }
    Component { id: transientTooltip; Tooltip { text: "Transient" } }
    Component { id: scaledWindow; Window { width: 400; height: 120; color: "black" } }
    // A bar widget's menu as the bar makes it: its Loader builds the menu
    // on a right click, which opens it in the same turn of the event loop.
    Component {
        id: freshMenu
        Item {
            readonly property alias menu: made
            width: 60
            height: 26
            Menu { id: made
                MenuItem { text: "Hide"; iconName: "eye-off" }
                MenuItem { text: "Settings"; iconName: "settings" }
            }
        }
    }
    // A select whose list opens over a field, as over a settings page's
    // next row.
    Component {
        id: coverScene
        Window {
            readonly property Item select: coverSelect
            readonly property Item field: coverField
            width: 320
            height: 260
            color: Theme.color.surface
            Select { id: coverSelect; x: 20; y: 20; model: ["one", "two", "three"] }
            TextField { id: coverField; x: coverSelect.x; width: coverSelect.width }
        }
    }
    property int chosen: 4
    Select { id: select; y: 40; model: ["one", "two", "three"] }
    Select { id: roled; y: 80; textRole: "name"; model: [{ name: "alpha" }, { name: "beta" }] }
    property int wanted: 0
    Select { id: bound; y: 120; model: ["one", "two", "three"]; currentIndex: root.wanted }
    Select { id: longSelect; y: 160; model: ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p"] }
    Select { id: emptySelect; y: 200; model: []; emptyText: "Nothing to choose" }
    // A select whose offers each play on request, ended by an Add entry
    // that plays nothing, as a voice field draws it (`preview`,
    // `addChoice`).
    Select {
        id: previewing
        y: 240
        textRole: "label"
        iconRole: "icon"
        actionRole: "preview"
        entryAction: ({ iconName: "volume-2", label: "Play" })
        model: [{ label: "Puck", preview: true }, { label: "Kore", preview: true }, { label: "Add a voice", icon: "plus" }]
    }
    SignalSpy { id: previewChoices; target: previewing; signalName: "activated" }
    SignalSpy { id: previewPresses; target: previewing; signalName: "entryActionActivated" }
    property int triggered: -1
    property int reached: 0
    MouseArea { id: under; x: 250; width: 50; height: 30; onPressed: root.reached += 1 }
    SignalSpy { id: activations; target: roled; signalName: "activated" }
    SignalSpy { id: settingsLines; target: settingsEntry.contentItem.children[1]; signalName: "lineCountChanged" }
    TextField { id: field; visible: false }
    ListItem { id: listRow; visible: false; text: "Row"; secondary: "Detail" }
    FontMetrics { id: itemMetrics; font: settingsEntry.contentItem.children[1].font }

    TestCase {
        name: "overlays"
        when: windowShown

        function init() { tip.shown = false; longTip.shown = false; detailsTip.shown = false; host.enabled = true; host.visible = true; UnitTheme.reset(); popover.close(); menu.close(); nested.close(); homed.close(); long.close(); root.chosen = 4; select.choose(0); longSelect.choose(0); root.triggered = -1; Hyprland.monitors = {}; }

        function tooltipDelay(of) {
            return of.resources.find(child => child.running !== undefined && child.interval === Theme.tooltip.delay);
        }

        function test_popover_opens_and_counts() {
            compare(popover.opened, false);
            compare(OverlayState.open, 0);
            popover.open();
            compare(popover.opened, true);
            compare(OverlayState.open, 1);
            popover.close();
            compare(popover.opened, false);
            compare(OverlayState.open, 0);
            popover.toggle();
            compare(popover.opened, true);
            popover.toggle();
            compare(popover.opened, false);
        }

        function test_popover_anchors_to_its_item() {
            let window = null;
            for (let i = 0; i < popover.resources.length; i++)
                if (popover.resources[i].anchor !== undefined) window = popover.resources[i];
            verify(window !== null, "the popover holds a popup window");
            compare(window.anchor.item, host);
            compare(window.anchor.margins.bottom, -Theme.popover.gap);
            compare(window.grabFocus, true);
            const updates = window.anchor.updates;
            popover.open();
            host.x += 10;
            verify(window.anchor.updates > updates, "a moved anchor updates the popup's anchor");
            host.visible = false;
            compare(popover.opened, false);
            host.visible = true;
            host.x = 0;
        }

        function test_menu_moves_and_triggers_by_key() {
            menu.open("key");
            compare(menu.opened, true);
            compare(menu.currentIndex, 0);
            menu.move(1);
            compare(menu.currentIndex, 1);
            compare(menu.items()[0].highlighted, false);
            menu.triggerCurrent();
            compare(root.triggered, 1);
            tryCompare(menu, "opened", false);
        }

        function test_menu_restores_its_owner_only_for_intentional_closes_data() {
            return [
                { tag: "trigger", close: "trigger", restores: true },
                { tag: "escape", close: "escape", restores: true },
                { tag: "outside", close: "outside", restores: false },
                { tag: "programmatic", close: "programmatic", restores: false },
                { tag: "submenu", close: "submenu", restores: false }
            ];
        }

        function test_menu_restores_its_owner_only_for_intentional_closes(data) {
            const saved = QsWindow.window;
            const owner = activationOwner;
            QsWindow.window = owner;
            Compositor.activations = [];
            const target = data.close === "submenu" ? nested : menu;
            try {
                target.open("key");
                if (data.close === "trigger" || data.close === "submenu") target.triggerCurrent();
                else if (data.close === "escape") {
                    target.surface.scope.forceActiveFocus();
                    keyClick(Qt.Key_Escape);
                }
                else if (data.close === "outside") target.surface.visible = false;
                else target.close();
                compare(target.opened, data.close === "submenu");
                compare(Compositor.activations.length, data.restores ? 1 : 0);
                if (data.restores) compare(Compositor.activations[0], owner);
            } finally {
                target.close();
                QsWindow.window = saved;
                Compositor.activations = [];
            }
        }

        function test_native_activation_judges_the_client_and_both_dispatcher_dialects() {
            const clients = [{ mapped: true, pid: 42, title: "Window", address: "0xab" },
                { mapped: true, pid: 99, title: "Window", address: "0xcd" }];
            const state = JSON.stringify(clients) + "\n\n\n" + JSON.stringify({ x: 10, y: 923 });
            const lua = Dispatch.activationRequest(state, 42, "Window", true);
            verify(lua.ok);
            compare(lua.argv[0], "hyprctl");
            verify(lua.argv[2].includes("address:0xab"));
            verify(!lua.argv[2].includes("address:0xcd"));
            verify(lua.argv[2].includes("hl.get_cursor_pos()"));
            const classic = Dispatch.activationRequest(state, 42, "Window", false);
            verify(classic.ok);
            compare(classic.argv, ["hyprctl", "--batch", "dispatch focuswindow address:0xab ; dispatch movecursor 10 923"]);
            verify(!Dispatch.activationRequest(state, 41, "Window", true).ok);
            verify(!Dispatch.activationRequest(state, 42, "Other", true).ok);
            verify(!Dispatch.activationRequest("unread", 42, "Window", true).ok);
            const duplicate = JSON.stringify([clients[0], clients[0]]) + "\n\n\n{}";
            verify(!Dispatch.activationRequest(duplicate, 42, "Window", true).ok);
            const badCursor = JSON.stringify(clients) + '\n\n\n{"x":"bad","y":923}';
            verify(!Dispatch.activationRequest(badCursor, 42, "Window", false).ok);
            compare(Dispatch.activationAnswer("ok", true), "ok");
            compare(Dispatch.activationAnswer("ok\n\n\nok", false), "ok");
            verify(Dispatch.activationAnswer("ok\n\n\nrefused", false) !== "ok");
            verify(Dispatch.activationAnswer("exit=1", true) !== "ok");
        }

        // The bar's path: a menu made and opened in one turn shows its
        // window with the cursor on the opening entry.
        function test_a_menu_opens_in_the_turn_that_made_it() {
            const made = createTemporaryObject(freshMenu, host).menu;
            made.open("key");
            verify(made.opened, "the first open shows the window");
            compare(made.currentIndex, 0, "a key opening highlights the first entry");
            verify(made.items()[0].cursor === made.plate && made.plate.target === made.items()[0], "the cursor sits on the opening entry");
            made.close();
        }

        function test_menu_skips_disabled_entries_and_starts_at_the_ends() {
            menu.open("key");
            menu.move(-1);
            compare(menu.currentIndex, 3, "Up from the first entry wraps to the last reachable one");
            menu.move(1);
            compare(menu.currentIndex, 0, "the highlight wraps over the reachable entries");
            menu.move(-1);
            compare(menu.currentIndex, 3);
            menu.move(-1);
            compare(menu.currentIndex, 1, "the highlight skips the disabled entry going up");
            menu.currentIndex = 2;
            menu.triggerCurrent();
            compare(root.triggered, -1, "a disabled entry never triggers");
            menu.close();
        }

        // A press anywhere in the window an overlay's anchor draws in closes
        // it and reaches no item under it; once it is closed, a press
        // reaches the window again.
        function test_a_press_in_the_anchor_window_closes_the_overlay() {
            const overlays = [
                { name: "popover", open: () => popover.open(), opened: () => popover.opened },
                { name: "menu", open: () => menu.open("key"), opened: () => menu.opened },
                { name: "select", open: () => select.openList(), opened: () => select.listOpen }
            ];
            for (const overlay of overlays) {
                root.reached = 0;
                overlay.open();
                compare(overlay.opened(), true, overlay.name + " opens");
                mouseClick(under);
                compare(overlay.opened(), false, "a press in the window closes the " + overlay.name);
                compare(root.reached, 0, "the press that closes the " + overlay.name + " reaches no item under it");
                mouseClick(under);
                compare(root.reached, 1, "with the " + overlay.name + " closed a press reaches the window");
            }
        }

        // An output's room is its size less `size.window.gutter` a side;
        // with no output there is no bound, and an overlay keeps its cap.
        function test_an_output_leaves_its_room() {
            const gutter = Theme.size.window.gutter;
            const output = { name: "one", width: 480, height: 720 };
            const room = OverlayState.room(output);
            compare(room.width, 480 - 2 * gutter);
            compare(room.height, 720 - 2 * gutter);
            compare(room.x, gutter);
            compare(room.y, gutter);
            compare(OverlayState.room(null).width, Infinity);
            compare(OverlayState.widthFor(null, 360), 360);
            // A monitor Quickshell has not read yet reserves nothing.
            Hyprland.monitors = { one: { lastIpcObject: {} } };
            compare(OverlayState.room(output).height, 720 - 2 * gutter);
            // Quickshell hands the list over as a Qt sequence, an
            // array-like that is no Array.
            Hyprland.monitors = { one: { lastIpcObject: { reserved: { length: 4, 0: 12, 1: 40, 2: 6, 3: 10 } } } };
            const reserved = OverlayState.room(output);
            compare(reserved.x, 12 + gutter);
            compare(reserved.y, 40 + gutter);
            compare(reserved.width, 480 - 12 - 6 - 2 * gutter);
            compare(reserved.height, 720 - 40 - 10 - 2 * gutter);
            Hyprland.monitors = {};
        }

        // The room a shell window takes: the top at `size.window.topShare`
        // of the output's height, rounded to a whole pixel as the window
        // rule's `rint` rounds it, and the height `size.window.tallHeightShare`
        // of the output's height in whole pixels, or from that top to the
        // room's bottom, which the output's reserved bottom edge and the
        // gutter keep from the output's bottom, when that is less; with no
        // output there is no bound.
        function test_a_window_room_starts_at_the_pinned_top() {
            const gutter = Theme.size.window.gutter;
            compare([Theme.size.window.topShare, Theme.size.window.tallHeightShare], [0.2, 0.6], "the worked figures below read the default shares");
            // 0.2 of 1067 is 213.4, so the top rounds down to 213, and 0.6
            // of it is 640.2, so the cap is 640; 0.2 of 1083 is 216.6, so
            // the top rounds up to 217. 0.2 of 720 is 144, and 0.6 of it
            // 432, short of the 576 less the gutter under that top.
            const output = { name: "one", width: 1366, height: 1067 };
            compare(OverlayState.windowRoom(output), { top: 213, height: 640 });
            compare(OverlayState.windowRoom({ name: "one", width: 1366, height: 1083 }).top, 217);
            compare(OverlayState.windowRoom({ name: "one", width: 1280, height: 720 }), { top: 144, height: 432 });
            Hyprland.monitors = { one: { lastIpcObject: { reserved: { length: 4, 0: 0, 1: 40, 2: 0, 3: 300 } } } };
            compare(OverlayState.windowRoom(output), { top: 213, height: 1067 - 300 - gutter - 213 }, "a reserved bottom edge past the cap shortens the room; the reserved top leaves the top where it is");
            Hyprland.monitors = {};
            compare(OverlayState.windowRoom(null), { top: 0, height: Infinity });
        }

        function test_menu_width_follows_its_widest_entry() {
            verify(wide.implicitWidth > Theme.menu.minWidth, "the wide entry passes the minimum: " + wide.implicitWidth);
            menu.open("key");
            const window = windowOf(menu);
            verify(window !== null, "the open menu holds a popup window");
            // Past `menu.maxWidth` the window stops growing; the entries fill
            // it inside the border.
            verify(wide.implicitWidth + 2 * Theme.border.thin > Theme.menu.maxWidth, "the wide entry passes the cap: " + wide.implicitWidth);
            compare(window.width, Theme.menu.maxWidth);
            compare(wide.width, window.width - 2 * Theme.border.thin);
            menu.close();
            // Under the cap no entry elides, whatever fraction of a pixel
            // its text measures: the window rounds its width up.
            mid.open("key");
            const midWindow = windowOf(mid);
            verify(mid.widest > Theme.menu.minWidth && mid.widest !== Math.floor(mid.widest), "the entry passes the minimum by a fraction: " + mid.widest);
            tryVerify(() => mid.items()[0].width >= mid.widest, 1000, "the entry takes its whole width in a window " + midWindow.width + " wide, the entry " + mid.widest);
            compare(mid.items()[0].contentItem.children[1].truncated, false);
            mid.close();
            menu.open("key");
            // The long text wraps and never elides, the entry grows by its
            // lines, and the shortcut keeps its trailing column beside the
            // first line.
            const title = wide.contentItem.children[1];
            const hint = wide.contentItem.children[2];
            compare(title.truncated, false, "the long text elides");
            verify(title.lineCount > 1, "the long text wraps: " + title.lineCount + " line");
            verify(wide.height >= title.contentHeight + wide.topPadding + wide.bottomPadding, "the entry holds every line");
            compare(hint.x + hint.width, wide.contentItem.width);
            verify(title.x + title.width <= hint.x - wide.spacing, "the text stops before the shortcut column");
            fuzzyCompare(hint.y + hint.capCentre, title.y + title.capCentre, 1, "the shortcut's capitals centre on the first line's");
            menu.close();
        }

        // A short menu is as wide as its longest entry: that entry's text
        // ends as far from the right edge as it starts from the left. Only a
        // menu of one short word takes the minimum width. An entry's icon is
        // as tall as its text's capitals and centred on its x-height, and
        // the capitals start a side padding below the entry's top and end as
        // far above its bottom.
        function test_entry_glyphs_centre_on_the_x_height_data() {
            return [{ tag: "1x", scale: 1 }, { tag: "2x", scale: 2 }];
        }

        // An entry's icon, check mark and submenu chevron centre their ink
        // on the text's x-height centre within half a device pixel, each on
        // a whole device pixel, at 1x and at 2x.
        function test_entry_glyphs_centre_on_the_x_height(data) {
            const screen = Qt.application.screens[data.scale - 1];
            const window = scaledWindow.createObject(null, { screen: screen, x: screen.virtualX + 10, y: screen.virtualY + 10 });
            window.visible = true;
            const submenu = Qt.createQmlObject("import qs.Ui\nMenuItem { x: 8; y: 8; width: 200; text: \"Accounts\"; iconName: \"eye-off\"; opensSubmenu: true }", window.contentItem);
            const ticked = Qt.createQmlObject("import qs.Ui\nMenuItem { x: 8; y: 60; width: 200; text: \"Hide\"; iconName: \"settings\"; checked: true }", window.contentItem);
            const ratio = submenu.Screen.devicePixelRatio;
            const rows = [
                ["the icon", submenu, submenu.contentItem.children[0]],
                ["the chevron", submenu, submenu.children.find(child => child.name === "chevron-right")],
                ["the check mark", ticked, ticked.indicator],
                ["the checked entry's icon", ticked, ticked.contentItem.children[0]]
            ];
            const found = [];
            for (const [name, entry, glyph] of rows) {
                const title = entry.contentItem.children[1];
                const xHeight = title.mapToItem(window.contentItem, 0, title.xCentre).y;
                const top = glyph.mapToItem(window.contentItem, 0, 0).y;
                const ink = top + (glyph.painted[1] + glyph.painted[3]) / 2;
                found.push([name, ratio, Math.abs(ink - xHeight) * ratio <= 0.5, Math.abs(top * ratio - Math.round(top * ratio)) < 0.01, ink, xHeight, top]);
            }
            submenu.destroy();
            ticked.destroy();
            window.destroy();
            for (const [name, at, centred, whole, ink, xHeight, top] of found) {
                compare(at, data.scale, "the window draws at its screen's scale");
                verify(centred, name + "'s ink centre " + ink + " lies within half a device pixel of the x-height centre " + xHeight);
                verify(whole, name + "'s top " + top + " is on a whole device pixel");
            }
        }

        function test_a_short_menu_fits_its_entries() {
            settingsLines.clear();
            barMenu.open("key");
            const window = windowOf(barMenu);
            const opening = window.width;
            const longest = settingsEntry;
            tryCompare(longest, "width", window.width - 2 * Theme.border.thin);
            compare(window.width, opening, "the menu opens at the width it settles at");
            // No strip for a bar the menu never shows wraps an entry that
            // fits, even before the list takes its window's size.
            compare(settingsLines.count, 0, "Settings keeps one line while its menu opens");
            verify(longest.implicitWidth > hideEntry.implicitWidth, "Settings is the longest entry");
            compare(window.width, Math.ceil(longest.implicitWidth) + 2 * Theme.border.thin);
            const icon = longest.contentItem.children[0];
            const title = longest.contentItem.children[1];
            const left = Theme.border.thin + longest.contentItem.x + icon.x;
            const right = window.width - (Theme.border.thin + longest.contentItem.x + title.x + title.implicitWidth);
            compare(left, Theme.border.thin + longest.sidePadding);
            verify(Math.abs(right - left) <= 1, "the text ends as far from the right edge as the icon starts from the left: " + left + " and " + right);
            const capitals = itemMetrics.capitalHeight;
            for (const entry of [hideEntry, settingsEntry]) {
                const glyph = entry.contentItem.children[0];
                const ink = glyph.painted[3] - glyph.painted[1];
                verify(Math.abs(ink - capitals) <= 1, entry.text + "'s icon ink " + ink + " is within a pixel of the capitals " + capitals);
            }
            const baseline = longest.contentItem.y + title.y + title.baselineOffset;
            const capTop = baseline - capitals;
            verify(Math.abs(capTop - longest.sidePadding) <= 1, "the capitals start " + capTop + " below the entry's top, its side padding " + longest.sidePadding);
            const below = longest.height - baseline;
            verify(Math.abs(below - capTop) <= 1, "the baseline stands " + below + " above the entry's bottom, the capitals " + capTop + " below its top");
            const inkCentre = longest.contentItem.y + icon.y + (icon.painted[1] + icon.painted[3]) / 2;
            const xHeight = itemMetrics.xHeight;
            verify(Math.abs(inkCentre - (baseline - xHeight / 2)) <= 1, "the icon's ink centre " + inkCentre + " is within a pixel of the x-height centre " + (baseline - xHeight / 2));
            barMenu.close();
            oneWord.open("key");
            verify(oneWord.items()[0].implicitWidth + 2 * Theme.border.thin < Theme.menu.minWidth, "the one word is narrower than the minimum");
            compare(windowOf(oneWord).width, Theme.menu.minWidth);
            oneWord.close();
        }

        function labelsOf(item) {
            let found = [];
            for (const child of item.children) {
                if (child instanceof Label) found.push(child);
                found = found.concat(labelsOf(child));
            }
            return found;
        }

        // At the default 15 px text size a menu entry's text draws at 14 px
        // and its shortcut at 12, while a field, a select and a list item
        // keep the shared row roles at 15 and 13.
        function test_menu_text_draws_a_pixel_under_the_rows() {
            compare(Theme.font.size, 15);
            compare(wide.contentItem.children[1].font.pixelSize, 14);
            compare(wide.contentItem.children[2].text, "Ctrl+Shift+W");
            compare(wide.contentItem.children[2].font.pixelSize, 12);
            compare(field.font.pixelSize, 15);
            compare(select.contentItem.font.pixelSize, 15);
            const rows = labelsOf(listRow);
            compare(rows.find(label => label.text === "Row").font.pixelSize, 15);
            compare(rows.find(label => label.text === "Detail").font.pixelSize, 13);
        }

        function longWindow() { return windowOf(long); }

        function test_a_long_menu_scrolls_inside_its_maximum() {
            compare(UnitTheme.override({ menu: { maxHeight: 90 } }), "ok");
            long.open("key");
            const window = longWindow();
            compare(window.height, 90 + 2 * Theme.border.thin);
            compare(long.scrollArea.overflowing, true);
            compare(long.scrollArea.bar.visible, true);
            // The entries span the list, and each keeps the bar's strip
            // clear at its end: the bar lies inside it.
            const first = long.items()[0];
            // The window's content item takes the window's size a turn
            // after it shows.
            tryCompare(long.scrollArea, "width", window.width - 2 * Theme.border.thin);
            compare(first.width, long.scrollArea.width);
            compare(first.barRoom, Theme.scrollArea.gutter);
            const bar = long.scrollArea.bar;
            verify(bar.x >= first.width - first.barRoom && bar.x + bar.width <= first.width, "the bar lies in the entry's end strip: " + bar.x);
            compare(first.contentItem.x + first.contentItem.width, first.width - first.barRoom - first.sidePadding, "the entry's text stops a side padding before the bar");
            // The menu is as wide as its widest entry with the strip once:
            // that entry's text ends its right padding, the strip in it,
            // from the list's end, within the whole pixel the window
            // rounds up to.
            const widest = long.items().reduce((wide, item) => item.implicitWidth > wide.implicitWidth ? item : wide);
            const text = widest.contentItem.children[1];
            const gap = long.scrollArea.width - (widest.contentItem.x + text.x + text.implicitWidth);
            verify(gap >= widest.rightPadding && gap < widest.rightPadding + 1, widest.text + "'s text ends " + gap + " from the list's end, its right padding " + widest.rightPadding);
            long.close();
            // A menu that fits keeps no strip.
            UnitTheme.reset();
            menu.open("key");
            tryCompare(menu.items()[0], "barRoom", 0);
            compare(menu.items()[0].rightPadding, menu.items()[0].sidePadding);
            menu.close();
        }

        function test_the_highlight_is_kept_in_view() {
            compare(UnitTheme.override({ menu: { maxHeight: 90 } }), "ok");
            root.chosen = -1;
            long.open("key");
            compare(long.scrollArea.contentY, 0);
            for (let i = 0; i < 10; i++) long.move(1);
            const item = long.items()[long.currentIndex];
            verify(item.y + item.height <= long.scrollArea.contentY + long.scrollArea.height, "the highlighted entry's bottom is in view");
            verify(item.y >= long.scrollArea.contentY, "the highlighted entry's top is in view");
            long.move(1);
            long.nav.moveTo(0, true);
            compare(long.scrollArea.contentY, 0, "going back up scrolls the first entry into view");
            long.close();
            root.chosen = 4;
        }

        // A resting pointer never scrolls a list: Qt delivers its hover
        // again each frame to an entry that moves under it, so a hover that
        // revealed its entry clear of the fade band would take the next
        // entry and scroll again, one entry a frame, to the menu's end.
        function test_a_resting_pointer_at_a_long_menus_edge_scrolls_nothing() {
            compare(UnitTheme.override({ menu: { maxHeight: 90 } }), "ok");
            root.chosen = -1;
            long.open("pointer");
            focusMenu(long);
            const scroll = long.scrollArea;
            tryVerify(() => scroll.overflowing, 1000, "the long menu overflows");
            tryCompare(scroll, "height", 90);
            const items = long.items();
            const band = scroll.height - scroll.fadeExtent;
            let edge = -1;
            for (let index = 0; index < items.length; ++index) {
                const bottom = items[index].y + items[index].height;
                if (bottom > band && bottom <= scroll.height) edge = index;
            }
            verify(edge > 0, "an entry ends inside the bottom band, from " + band);
            mouseMove(items[edge], 10, items[edge].height / 2);
            mouseMove(items[edge], 12, items[edge].height / 2);
            // Frames for a hover delivered again to reach the entries.
            wait(100);
            compare(scroll.contentY, 0, "the menu stays where the pointer rests");
            compare(long.currentIndex, edge, "the entry under the pointer is highlighted");
            keyClick(Qt.Key_Down);
            compare(long.currentIndex, edge + 1);
            verify(scroll.contentY > 0, "a key move scrolls its entry into view");
            long.close();
            root.chosen = 4;
        }

        function test_opening_highlights_the_checked_entry_and_draws_its_mark() {
            compare(UnitTheme.override({ menu: { maxHeight: 90 } }), "ok");
            root.chosen = 12;
            long.open("key");
            compare(long.currentIndex, 12);
            const item = long.items()[12];
            verify(item.y + item.height <= long.scrollArea.contentY + long.scrollArea.height && item.y >= long.scrollArea.contentY, "the checked entry opens in view");
            compare(item.indicator.visible, true);
            compare(item.indicator.name, "check");
            compare(item.rightPadding, Theme.menu.item.paddingX + Theme.scrollArea.gutter + Theme.menu.item.icon + item.spacing);
            compare(item.indicator.x + item.indicator.painted[2], item.width - item.sidePadding - item.barRoom, "the check mark's ink ends a side padding before the bar");
            compare(long.items()[0].indicator.visible, false);
            compare(long.items()[0].rightPadding, Theme.menu.item.paddingX + Theme.scrollArea.gutter);
            long.close();
            root.chosen = -1;
            long.open("key");
            compare(long.currentIndex, 0, "with no checked entry the first reachable item is highlighted");
            long.close();
            root.chosen = 4;
        }

        // A highlight moved and dismissed without a choice: the next opening
        // lands the cursor on the checked entry at once, with motion on.
        function test_a_reopened_menu_lands_on_its_checked_entry() {
            compare(UnitTheme.override({ motion: { list: { travel: { duration: 2000 } } } }), "ok");
            long.open("key");
            const items = long.items();
            const plate = items[0].cursor;
            compare(long.currentIndex, 4);
            tryCompare(plate, "opacity", 1);
            long.move(1);
            long.move(1);
            compare(long.currentIndex, 6);
            // The cursor is on its way to the moved highlight.
            tryVerify(() => plate.y > items[4].y, 1000, "the cursor left the checked entry");
            long.close();
            long.open("key");
            compare(long.currentIndex, 4);
            compare(plate.y, items[4].y, "the cursor lands on the checked entry at once");
            long.close();
        }

        function test_a_reopened_select_list_lands_on_the_choice() {
            compare(UnitTheme.override({ motion: { list: { travel: { duration: 2000 } } } }), "ok");
            select.openList();
            const list = selectList(select);
            tryVerify(() => list.itemAtIndex(2) !== null, 1000, "the list builds its entries");
            const plate = list.contentItem.children.find(child => child.follow !== undefined);
            tryCompare(plate, "opacity", 1);
            list.highlightIndex = 2;
            // The cursor is on its way to the moved highlight.
            tryVerify(() => plate.y > list.itemAtIndex(0).y, 1000, "the cursor left the choice");
            list.Window.window.visible = false;
            compare(select.listOpen, false);
            select.openList();
            compare(list.highlightIndex, 0);
            compare(plate.y, list.itemAtIndex(0).y, "the cursor lands on the choice at once");
            select.choose(0);
        }

        function test_closed_select_keys_do_not_wrap() {
            select.forceActiveFocus();
            select.choose(0);
            select.closedNav.moveBy(-1);
            compare(select.currentIndex, 0);
            keyClick(Qt.Key_Up);
            compare(select.currentIndex, 0);
            select.choose(2);
            select.closedNav.moveBy(1);
            compare(select.currentIndex, 2);
            keyClick(Qt.Key_Down);
            compare(select.currentIndex, 2);
        }

        function test_open_select_keys_do_not_wrap() {
            select.openList();
            const list = selectList(select);
            tryVerify(() => list.itemAtIndex(2) !== null, 1000, "the list builds its entries");
            list.highlightIndex = 2;
            keyClick(Qt.Key_Down);
            compare(list.highlightIndex, 2);
            list.highlightIndex = 0;
            keyClick(Qt.Key_Up);
            compare(list.highlightIndex, 0);
            select.choose(0);
        }

        function test_typing_jumps_to_the_entry_starting_with_the_letters() {
            compare(UnitTheme.override({ menu: { typeahead: 200 } }), "ok");
            root.chosen = -1;
            long.open("key");
            compare(long.typeAhead("e"), true);
            compare(long.items()[long.currentIndex].text, "Echo", "the first entry that starts with e, not one that holds it");
            compare(long.typeAhead("T"), true, "no entry starts with et, so t starts a new prefix");
            compare(long.items()[long.currentIndex].text, "Themes");
            compare(long.typeAhead("h"), true);
            compare(long.items()[long.currentIndex].text, "Themes");
            compare(long.typed, "th");
            tryCompare(long, "typed", "", 2000);
            compare(long.typeAhead("b"), true);
            compare(long.items()[long.currentIndex].text, "Beta", "after the pause the letters start again from the current entry");
            compare(long.typeAhead("e"), true);
            compare(long.items()[long.currentIndex].text, "Beta", "two letters narrow the jump");
            long.close();
            root.chosen = 4;
        }

        function test_destroyed_overlay_releases_its_count() {
            const made = Qt.createQmlObject("import qs.Ui\nPopover { width: 80 }", host);
            made.open();
            compare(OverlayState.open, 1);
            made.destroy();
            tryCompare(OverlayState, "open", 0);
        }

        // An entry that opens a submenu draws a chevron where the check
        // mark stands and leaves the menu open, by click and by key, as an
        // entry that keeps it open does; any other entry still closes it.
        function test_a_submenu_entry_keeps_the_menu_open() {
            const chevron = entry => entry.children.find(child => child.name === "chevron-right");
            nested.open("key");
            compare(chevron(submenuEntry).visible, true);
            compare(chevron(submenuEntry).x + chevron(submenuEntry).painted[2], submenuEntry.width - submenuEntry.sidePadding - submenuEntry.barRoom, "the chevron's ink ends a side padding before the bar");
            // The chevron's ink ends as far from the window's right edge as
            // the text's ink starts from its left edge.
            const window = windowOf(nested);
            tryCompare(submenuEntry, "width", window.width - 2 * Theme.border.thin);
            const title = submenuEntry.contentItem.children[1];
            const textLeft = Theme.border.thin + submenuEntry.contentItem.x + title.x + itemMetrics.tightBoundingRect(title.text).x;
            const inkRight = window.width - (Theme.border.thin + chevron(submenuEntry).x + chevron(submenuEntry).painted[2]);
            verify(Math.abs(inkRight - textLeft) <= 1, "the chevron's ink gap " + inkRight + " matches the text's " + textLeft);
            compare(uncheckedSubmenu.rightPadding, uncheckedSubmenu.sidePadding + uncheckedSubmenu.barRoom + Theme.menu.item.icon + uncheckedSubmenu.spacing, "the chevron takes the check mark's room");
            compare(chevron(uncheckedSubmenu).visible, true);
            compare(submenuEntry.indicator.visible, false, "a checked submenu entry draws its chevron, not its check mark");
            compare(chevron(backEntry).visible, false);
            compare(chevron(leafEntry).visible, false);
            submenuEntry.clicked();
            compare(root.triggered, 10);
            compare(nested.opened, true, "a submenu entry's click leaves the menu open");
            root.triggered = -1;
            nested.currentIndex = 0;
            nested.triggerCurrent();
            compare(root.triggered, 10, "the key triggers the submenu entry");
            compare(nested.opened, true, "a submenu entry's key leaves the menu open");
            backEntry.clicked();
            compare(root.triggered, 11);
            compare(nested.opened, true, "an entry that keeps the menu open leaves it open");
            leafEntry.clicked();
            compare(root.triggered, 12);
            tryCompare(nested, "opened", false);
        }

        // Each opener's highlight: a key opening the checked entry, else the
        // first reachable one; a pointer opening none, checked or not.
        function test_an_opening_highlights_by_its_opener_data() {
            return [
                { tag: "key, nothing checked", opener: "key", chosen: -1, index: 0 },
                { tag: "key, a checked entry", opener: "key", chosen: 4, index: 4 },
                { tag: "pointer, nothing checked", opener: "pointer", chosen: -1, index: -1 },
                { tag: "pointer, a checked entry", opener: "pointer", chosen: 4, index: -1 }
            ];
        }

        function test_an_opening_highlights_by_its_opener(data) {
            root.chosen = data.chosen;
            long.open(data.opener);
            const items = long.items();
            compare(long.currentIndex, data.index);
            compare(items.findIndex(item => item.highlighted), data.index, "the highlighted entry");
            const plate = items[0].cursor;
            verify(plate.target === (data.index === -1 ? null : items[data.index]), "the cursor holds the highlighted entry, or none");
        }

        // An owner's `home` decides where a key opening and the first
        // arrow from a pointer opening land, over the checked entry.
        function test_an_owners_home_takes_the_opening_entry() {
            homed.open("key");
            compare(homed.currentIndex, 2, "a key opening lands on the owner's home");
            homed.close();
            homed.open("pointer");
            compare(homed.currentIndex, -1);
            focusMenu(homed);
            keyClick(Qt.Key_Down);
            compare(homed.currentIndex, 2, "the first arrow lands on the owner's home");
        }

        function test_an_opening_names_its_opener() {
            let refused = "";
            try { menu.open(); } catch (error) { refused = error.message; }
            verify(refused.startsWith("menu-opener: undefined"), "an opening with no opener is refused: " + refused);
            compare(menu.opened, false);
        }

        // Hand the keyboard to `owner`'s open popup, as its DismissScope
        // takes it on open.
        function focusMenu(owner) {
            const scope = windowOf(owner).contentItem.children.find(child => child.popup !== undefined);
            scope.Window.window.requestActivate();
            scope.forceActiveFocus();
            tryCompare(scope.Window, "active", true);
            tryCompare(scope, "activeFocus", true);
            // One event-loop turn lets the offscreen window finish activating before the first key.
            wait(0);
        }

        // Enter with no entry highlighted triggers nothing and leaves the
        // menu open. The control: Down then Enter on the same menu
        // triggers the entry Down landed on, so the keys reach it.
        function test_enter_on_a_pointer_opening_triggers_nothing() {
            menu.open("pointer");
            focusMenu(menu);
            keyClick(Qt.Key_Return);
            compare(root.triggered, -1, "Enter with no highlight triggers nothing");
            compare(menu.opened, true, "Enter with no highlight leaves the menu open");
            keyClick(Qt.Key_Down);
            compare(menu.currentIndex, 0);
            keyClick(Qt.Key_Return);
            compare(root.triggered, 0, "control: Enter on the highlighted entry triggers it");
            tryCompare(menu, "opened", false);
        }

        // On a pointer opening the first Up or Down lands where a key
        // opening would have; the next Down steps on from there.
        function test_the_first_arrow_lands_on_the_opening_entry_data() {
            return [
                { tag: "Down, nothing checked", key: Qt.Key_Down, chosen: -1, index: 0 },
                { tag: "Up, nothing checked", key: Qt.Key_Up, chosen: -1, index: 0 },
                { tag: "Down, a checked entry", key: Qt.Key_Down, chosen: 4, index: 4 },
                { tag: "Up, a checked entry", key: Qt.Key_Up, chosen: 4, index: 4 }
            ];
        }

        function test_the_first_arrow_lands_on_the_opening_entry(data) {
            root.chosen = data.chosen;
            long.open("pointer");
            compare(long.currentIndex, -1);
            focusMenu(long);
            keyClick(data.key);
            compare(long.currentIndex, data.index, "the first arrow lands on the opening entry");
            compare(long.items()[data.index].highlighted, true);
            keyClick(Qt.Key_Down);
            compare(long.currentIndex, data.index + 1, "the next Down steps on");
        }

        // Arrowing down a long menu keeps the highlighted entry clear of
        // each fade band while content lies beyond that edge, so the band
        // never fades it; the last entry rests flush at the end.
        function test_arrowing_keeps_the_highlight_clear_of_the_fade() {
            root.chosen = -1;
            long.open("pointer");
            focusMenu(long);
            const scroll = long.scrollArea;
            tryVerify(() => scroll.overflowing, 1000, "the long menu overflows");
            const items = long.items();
            for (let index = 0; index < items.length; ++index) {
                keyClick(Qt.Key_Down);
                compare(long.currentIndex, index);
                const top = items[index].mapToItem(scroll, 0, 0).y;
                const bottom = top + items[index].height;
                if (scroll.fadeBelow > 0)
                    verify(bottom <= scroll.height - scroll.fadeExtent + 0.5, "entry " + index + " ends at " + bottom + ", clear of the bottom band from " + (scroll.height - scroll.fadeExtent));
                if (scroll.fadeAbove > 0)
                    verify(top >= scroll.fadeExtent - 0.5, "entry " + index + " starts at " + top + ", clear of the top band to " + scroll.fadeExtent);
                verify(top >= -0.5 && bottom <= scroll.height + 0.5, "entry " + index + " lies in the view: " + top + ".." + bottom);
            }
            compare(scroll.fadeBelow, 0, "the last entry rests at the end, with no band below");
            fuzzyCompare(scroll.contentY, scroll.contentHeight - scroll.height, 0.5, "the band's margin scrolls no further than the content's end");
        }

        // On a pointer opening the entry the pointer enters takes the
        // highlight.
        function test_the_pointer_entering_an_entry_highlights_it() {
            menu.open("pointer");
            const items = menu.items();
            compare(menu.currentIndex, -1);
            mouseMove(items[1], 10, 5);
            mouseMove(items[1], 12, 5);
            compare(menu.currentIndex, 1, "the entry under the pointer is highlighted");
            verify(items[1].cursor.target === items[1], "the cursor holds the entry under the pointer");
            menu.close();
        }

        function test_menu_click_triggers_and_closes() {
            menu.open("key");
            menu.items()[0].clicked();
            compare(root.triggered, 0);
            tryCompare(menu, "opened", false);
        }

        function test_menu_highlights_through_its_cursor() {
            menu.open("key");
            const items = menu.items();
            const plate = items[0].cursor;
            verify(plate !== null, "the menu hands its entries a cursor");
            compare(plate.shown, true, "an open menu highlights its first reachable entry");
            // Every list's plate, on glass or not.
            compare(String(plate.color), String(Qt.color(Theme.listItem.selected)));
            compare(String(plate.pressedColor), String(Qt.color(Theme.listItem.selectedPressed)));
            Theme.appearanceInput = JSON.stringify({ glass: "on" });
            try {
                compare(String(plate.color), String(Qt.color(Theme.listItem.selected)), "glass on draws the same plate");
            } finally {
                Theme.appearanceInput = "";
            }
            verify(plate.target === items[0], "the highlighted entry holds the cursor");
            compare(items[0].background, null, "the entry draws no fill of its own");
            const accent = String(Qt.color(Theme.listItem.selectedForeground));
            compare(String(items[0].contentItem.children[1].color), accent, "the entry under the plate draws its text in the accent");
            compare(String(items[1].contentItem.children[1].color), String(Qt.color(Theme.menu.item.foreground)), "an entry the plate is not on keeps its text");
            mouseMove(items[1], 10, 5);
            compare(menu.currentIndex, 0, "the first reading after a key moves nothing");
            mouseMove(items[1], 12, 5);
            compare(menu.currentIndex, 1, "a moved pointer highlights the entry under it");
            compare(String(items[1].contentItem.children[1].color), accent, "the pointed entry takes the accent");
            compare(String(items[0].contentItem.children[1].color), String(Qt.color(Theme.menu.item.foreground)), "the entry the plate left drops it");
            menu.move(-1);
            compare(menu.currentIndex, 0);
            // The pointer rests where it was: Qt delivers it hover again
            // while the cursor travels, and a resting pointer must not take
            // the highlight back from the key.
            mouseMove(items[1], 12, 5);
            compare(menu.currentIndex, 0, "a key disarms the pointer");
            mouseMove(items[2], 12, 5);
            compare(menu.currentIndex, 0, "a hover highlights no disabled entry");
            verify(plate.hovered !== items[2], "a disabled entry takes no plate");
            menu.close();
        }

        // A pointer move outside the window that holds `item`.
        function leaveWindow(item) {
            const window = item.Window.window;
            mouseMove(window.contentItem, window.width + 20, window.height + 20);
        }

        function test_menu_highlight_leaves_with_the_pointer() {
            menu.open("key");
            const items = menu.items();
            const plate = items[0].cursor;
            compare(menu.currentIndex, 0, "the menu opens on its first entry");
            mouseMove(items[1], 10, 5);
            mouseMove(items[1], 12, 5);
            compare(menu.currentIndex, 1, "a moved pointer highlights the entry under it");
            leaveWindow(items[1]);
            compare(menu.currentIndex, -1, "with no key's choice, leaving clears the highlight");
            verify(plate.target === null && plate.hovered === null, "no entry keeps the plate");
            menu.close();
            menu.open("key");
            menu.move(1);
            compare(menu.currentIndex, 1, "a key chooses the second entry");
            mouseMove(items[0], 10, 5);
            mouseMove(items[0], 12, 5);
            compare(menu.currentIndex, 0);
            leaveWindow(items[0]);
            compare(menu.currentIndex, 1, "leaving returns the highlight to the key's choice");
            verify(plate.target === items[1] && plate.hovered === null);
            menu.close();
        }

        function test_select_highlight_returns_when_the_pointer_leaves() {
            select.choose(0);
            select.openList();
            const list = selectList(select);
            tryVerify(() => list.itemAtIndex(2) !== null, 1000, "the list builds its entries");
            compare(list.highlightIndex, 0, "the list opens on the chosen entry");
            mouseMove(list.itemAtIndex(2), 10, 5);
            mouseMove(list.itemAtIndex(2), 12, 5);
            compare(list.highlightIndex, 2, "a moved pointer highlights the entry under it");
            leaveWindow(list);
            compare(list.highlightIndex, 0, "leaving returns the highlight to the keyboard's entry");
            select.choose(0);
        }

        function selectList(owner) {
            let window = null;
            for (let i = 0; i < owner.resources.length; i++)
                if (owner.resources[i].anchor !== undefined) window = owner.resources[i];
            // The list's content sits in the popup's DismissScope.
            const scope = window.contentItem.children.find(child => child.popup !== undefined);
            return scope.children.find(child => child.currentIndex !== undefined);
        }

        // The open previewing list, its window active and its keys its own.
        function openPreviewing() {
            previewing.choose(0);
            previewChoices.clear();
            previewPresses.clear();
            previewing.openList();
            const list = selectList(previewing);
            tryVerify(() => list.itemAtIndex(2) !== null, 1000, "the list builds its entries");
            list.Window.window.requestActivate();
            list.forceActiveFocus();
            tryCompare(list.Window, "active", true);
            tryCompare(list, "activeFocus", true);
            wait(0);
            return list;
        }
        function entryButton(list, index) {
            const entry = list.itemAtIndex(index);
            let found = [entry];
            for (let i = 0; i < found.length; i++) for (const child of found[i].children || []) found.push(child);
            return found.find(child => child instanceof IconButton && child.visible);
        }
        function pressIndexes() {
            const out = [];
            for (let i = 0; i < previewPresses.count; i++) out.push(previewPresses.signalArguments[i][0]);
            return out;
        }

        // In the open list Right moves the keyboard to the highlighted
        // entry's button, and Enter or Space presses it: the entry's action
        // runs, nothing is chosen and the list stays open. Left takes the
        // keyboard back, where Enter chooses the entry.
        function test_right_reaches_an_entry_button_and_enter_presses_it() {
            const list = openPreviewing();
            compare([entryButton(list, 0) !== undefined, entryButton(list, 1) !== undefined, entryButton(list, 2)], [true, true, undefined], "each offer draws its button, the Add entry none");
            compare(entryButton(list, 0).label, "Play Puck");
            keyClick(Qt.Key_Right);
            verify(previewing.entryActionFocused, "Right moves the keyboard to the button");
            verify(entryButton(list, 0).focusPreview, "the button shows the keyboard");
            keyClick(Qt.Key_Return);
            keyClick(Qt.Key_Space);
            compare(pressIndexes(), [0, 0], "Enter and Space press the button");
            compare(previewChoices.count, 0, "the press chooses nothing");
            verify(previewing.listOpen, "the list stays open");
            verify(entryButton(list, 0).checked, "the pressed button reads checked");
            keyClick(Qt.Key_Left);
            verify(!previewing.entryActionFocused, "Left takes the keyboard back to the entry");
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Return);
            compare([previewChoices.count, previewing.currentIndex, previewing.listOpen, pressIndexes()], [1, 1, false, [0, 0]], "Enter on the entry chooses it");
        }

        // No arrow presses a button: Up and Down move the highlight and
        // take the keyboard back to the entry, at the list's end too, and
        // Right on an entry with no button stays on the entry.
        function test_arrows_never_press_an_entry_button() {
            const list = openPreviewing();
            keyClick(Qt.Key_Right);
            verify(previewing.entryActionFocused, "Right moves the keyboard to the button");
            keyClick(Qt.Key_Down);
            compare([list.highlightIndex, previewing.entryActionFocused], [1, false], "Down moves the highlight and leaves the button");
            keyClick(Qt.Key_Right);
            keyClick(Qt.Key_Up);
            compare([list.highlightIndex, previewing.entryActionFocused], [0, false], "Up moves the highlight and leaves the button");
            keyClick(Qt.Key_Right);
            keyClick(Qt.Key_Up);
            compare([list.highlightIndex, previewing.entryActionFocused], [0, false], "Up at the list's start leaves the button too");
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Right);
            compare([list.highlightIndex, previewing.entryActionFocused], [2, false], "an entry with no button keeps the keyboard");
            keyClick(Qt.Key_Left);
            compare(pressIndexes(), [], "no arrow pressed a button");
            compare(previewChoices.count, 0);
            previewing.choose(0);
        }

        // A pointer over an entry's button highlights that entry, as over
        // the entry, and presses nothing; a click on the button runs its
        // action, chooses nothing and keeps the list open.
        function test_an_entry_button_takes_the_pointer_as_its_entry_does() {
            const list = openPreviewing();
            const button = entryButton(list, 1);
            mouseMove(button, 4, 4);
            mouseMove(button, 6, 4);
            compare(list.highlightIndex, 1, "a hover over the button highlights its entry");
            compare(pressIndexes(), [], "a hover presses nothing");
            mouseClick(button);
            compare([pressIndexes(), previewChoices.count, previewing.listOpen], [[1], 0, true], "a click presses the button alone");
            leaveWindow(list);
            previewing.choose(0);
        }

        function test_select_list_highlights_through_its_cursor() {
            select.openList();
            const list = selectList(select);
            tryVerify(() => list.itemAtIndex(1) !== null, 1000, "the list builds its entries");
            const first = list.itemAtIndex(0);
            const second = list.itemAtIndex(1);
            // The keys go to the list's own window, which takes the focus
            // before the pointer moves: activating it delivers a hover.
            list.Window.window.requestActivate();
            list.forceActiveFocus();
            tryCompare(list.Window, "active", true);
            tryCompare(list, "activeFocus", true);
            // One event-loop turn lets the offscreen window finish activating before the first key.
            wait(0);
            keyClick(Qt.Key_Down);
            compare(list.highlightIndex, 1);
            mouseMove(second, 10, 5);
            compare(list.highlightIndex, 1, "the first reading after a key moves nothing");
            mouseMove(first, 12, 5);
            compare(list.highlightIndex, 0, "a moved pointer highlights the entry under it");
            compare(String(first.contentItem.children[1].color), String(Qt.color(Theme.listItem.selectedForeground)), "the pointed entry takes the accent");
            compare(first.indicator.visible, true, "the chosen entry keeps its check mark");
            compare(second.indicator.visible, false, "another entry draws no mark");
            keyClick(Qt.Key_Down);
            compare(list.highlightIndex, 1);
            compare(second.background, null, "the highlighted entry draws no fill of its own");
            compare(String(first.contentItem.children[1].color), String(Qt.color(Theme.menu.item.foreground)), "the chosen entry the plate left draws its resting text");
            // The pointer rests where it was: Qt delivers it hover again
            // while the cursor travels, and a resting pointer must not take
            // the highlight back from the key.
            mouseMove(first, 12, 5);
            compare(list.highlightIndex, 1, "a key disarms the pointer");
            select.choose(0);
        }

        // The list the pointer rests over keeps its place: a hover over an
        // entry part way past the list's bottom highlights it and scrolls
        // nothing, while Down scrolls the next entry into view.
        function test_a_hover_over_a_part_hidden_select_entry_scrolls_nothing() {
            compare(UnitTheme.override({ menu: { maxHeight: Theme.menu.item.height * 2.5 } }), "ok");
            longSelect.choose(0);
            longSelect.openList();
            const list = selectList(longSelect);
            tryCompare(list, "height", Theme.menu.item.height * 2.5);
            tryVerify(() => list.itemAtIndex(2) !== null, 1000, "the list builds its entries");
            compare(list.contentY, 0);
            const part = list.itemAtIndex(2);
            verify(part.y < list.height && part.y + part.height > list.height, "the third entry lies part way past the bottom: " + part.y);
            list.Window.window.requestActivate();
            list.forceActiveFocus();
            tryCompare(list.Window, "active", true);
            tryCompare(list, "activeFocus", true);
            wait(0);
            mouseMove(part, 10, (list.height - part.y) / 2);
            mouseMove(part, 12, (list.height - part.y) / 2);
            // A ListView scrolls to its current item over its highlight's
            // move, 400 px/s by default (highlightMoveVelocity): a second
            // covers that move across the rows above the entry.
            wait(1000);
            compare(list.contentY, 0, "the list stays where the pointer rests");
            compare(part.highlighted, true, "the entry under the pointer is highlighted");
            keyClick(Qt.Key_Down);
            compare(list.itemAtIndex(3).highlighted, true);
            verify(list.contentY > 0, "a key move scrolls its entry into view");
            longSelect.choose(0);
        }

        // An opening scrolls the choice into view, here one far below the
        // list's first page.
        function test_a_long_select_list_opens_on_its_choice() {
            compare(UnitTheme.override({ menu: { maxHeight: Theme.menu.item.height * 2.5 } }), "ok");
            longSelect.choose(12);
            longSelect.openList();
            const list = selectList(longSelect);
            tryCompare(list, "height", Theme.menu.item.height * 2.5);
            tryVerify(() => list.itemAtIndex(12) !== null, 1000, "the list builds the chosen entry");
            const chosen = list.itemAtIndex(12);
            tryVerify(() => chosen.y >= list.contentY - 0.5 && chosen.y + chosen.height <= list.contentY + list.height + 0.5, 1000, "the choice lies in view: " + chosen.y + " at " + list.contentY);
            compare(chosen.highlighted, true);
            longSelect.choose(0);
        }

        // A fill's box in its window's content item.
        function boxIn(item, window) {
            const p = item.mapToItem(window.contentItem, 0, 0);
            return { x: p.x, y: p.y, width: item.width, height: item.height };
        }
        // Whether a fill `radius` round stays inside the top corners of a
        // container `width` by `height` whose corner is `containerRadius`
        // inside a `border`: every point of the fill's top corner arcs that
        // lies in a corner's square is no farther from that corner's
        // centre than its inner radius, half a pixel allowed.
        function insideCorner(box, radius, width, height, containerRadius, border) {
            const outer = Math.min(containerRadius, width / 2, height / 2);
            const inner = Math.max(0, outer - border);
            const own = Math.min(radius, box.width / 2, box.height / 2);
            for (let i = 0; i <= 32; i++) {
                const angle = Math.PI / 2 * i / 32;
                const y = box.y + own - own * Math.sin(angle);
                for (const [x, centre] of [[box.x + own - own * Math.cos(angle), outer], [box.x + box.width - own + own * Math.cos(angle), width - outer]]) {
                    const inSquare = y < outer && (x < outer || x > width - outer);
                    if (inSquare && Math.hypot(x - centre, y - outer) > inner + 0.5) return false;
                }
            }
            return true;
        }

        function test_the_first_menu_entry_meets_the_border_data() {
            return [
                { tag: "square", theme: {}, flush: true },
                { tag: "rounded", theme: { radius: { sm: 6, md: 12, lg: 16 } }, flush: true },
                { tag: "square entries in a round menu", theme: { radius: { md: 12 }, menu: { item: { radius: 0 } } }, flush: false }
            ];
        }

        // The first entry's highlight reaches the list's border at the top
        // and both sides, with no gutter, and stays inside the menu's drawn
        // corner; entries less round than the corner start lower, inside it.
        function test_the_first_menu_entry_meets_the_border(data) {
            compare(UnitTheme.override(data.theme), "ok");
            menu.open("key");
            const window = windowOf(menu);
            const plate = menu.items()[0].cursor;
            tryCompare(plate, "opacity", 1);
            tryVerify(() => plate.target === menu.items()[0] && plate.height === menu.items()[0].height, 2000, "the cursor holds the first entry");
            const fill = boxIn(plate, window);
            const border = Theme.border.thin;
            compare(fill.x, border, "the fill meets the left border");
            compare(fill.x + fill.width, window.width - border, "the fill meets the right border");
            if (data.flush) compare(fill.y, border, "the fill meets the top border");
            else verify(fill.y > border, "a square entry starts below a round corner: " + fill.y);
            compare(plate.radius, Theme.menu.item.radius);
            verify(insideCorner(fill, plate.radius, window.width, window.height, Theme.menu.radius, border), "the fill's corners stay inside the menu's corner: " + JSON.stringify(fill));
            menu.close();
        }

        function test_the_first_select_entry_meets_the_border_data() {
            return test_the_first_menu_entry_meets_the_border_data();
        }

        // The list opens on the control's edges, as wide as it; the
        // highlight on the chosen entry reaches the border at the top and
        // both sides and stays inside the list's corner, and the entry's
        // text starts where the field's does.
        function test_the_first_select_entry_meets_the_border(data) {
            compare(UnitTheme.override(data.theme), "ok");
            select.choose(0);
            select.openList();
            const list = selectList(select);
            tryVerify(() => list.itemAtIndex(0) !== null, 1000, "the list builds its entries");
            const entry = list.itemAtIndex(0);
            let popup = null;
            for (let i = 0; i < select.resources.length; i++)
                if (select.resources[i].anchor !== undefined) popup = select.resources[i];
            const border = Theme.border.thin;
            compare(popup.anchor.margins.left, 0);
            compare(popup.width, select.width);
            const plate = list.contentItem.children.find(child => child.follow !== undefined);
            tryVerify(() => plate.target === entry && plate.height === entry.height, 2000, "the cursor holds the chosen entry");
            const fill = boxIn(plate, popup);
            compare(fill.x, border, "the highlight meets the left border");
            compare(fill.x + fill.width, popup.width - border, "the highlight meets the right border");
            if (data.flush) compare(fill.y, border, "the highlight meets the top border");
            else verify(fill.y > border, "a square entry starts below a round corner: " + fill.y);
            compare(plate.radius, Theme.menu.item.radius);
            verify(insideCorner(fill, plate.radius, popup.width, popup.height, Theme.menu.radius, border), "the highlight's corners stay inside the list's corner: " + JSON.stringify(fill));
            const text = entry.contentItem.mapToItem(popup.contentItem, 0, 0);
            compare(text.x, select.contentItem.x, "the entry's text starts where the field's does");
            select.choose(select.currentIndex);
        }

        function test_an_open_list_covers_the_field_under_it_data() {
            const out = [];
            for (const [mode, theme] of [["dark", {}], ["light", { scheme: { mode: "light" } }]])
                for (let below = 1; below <= 4; below++)
                    out.push({ tag: mode + " " + below + "px", theme: theme, below: below });
            return out;
        }

        // A field whose bottom border ends 1 to 4 px below the edge the
        // entries alone put the list at, their height inside its inset,
        // draws none of its rows outside the list: the composite of the
        // page's image and the list's, placed where the popup's anchor puts
        // it, shows the list's opaque fill over each of them.
        function test_an_open_list_covers_the_field_under_it(data) {
            compare(UnitTheme.override(data.theme), "ok");
            const scene = createTemporaryObject(coverScene, root);
            scene.visible = true;
            const select = scene.select, field = scene.field;
            select.openList();
            const popup = windowOf(select);
            const list = selectList(select);
            tryVerify(() => list.itemAtIndex(2) !== null && list.height > 0, 1000, "the list builds its entries");
            const listTop = select.y + select.height - popup.anchor.margins.bottom;
            const edge = listTop + 2 * select.listInset + list.contentHeight;
            field.y = edge + data.below - field.height;
            verify(field.y > listTop, "the field starts under the list's top");
            const page = grabImage(scene.contentItem);
            const shown = grabImage(popup.contentItem);
            const background = Qt.color(Theme.color.surface);
            const middle = Math.round(field.x + field.width / 2);
            const drawn = y => Math.abs(page.red(middle, y) - background.r * 255) + Math.abs(page.green(middle, y) - background.g * 255) + Math.abs(page.blue(middle, y) - background.b * 255) > 6;
            let lowest = Math.ceil(field.y + field.height) + 2;
            while (lowest > field.y && !drawn(lowest)) lowest--;
            compare(lowest, Math.ceil(edge + data.below) - 1, "the page image draws the field's bottom border " + data.below + " px under the entries' edge");
            const out = [];
            for (let y = Math.floor(field.y); y <= lowest; y++) {
                const row = y - listTop;
                for (let x = Math.ceil(field.x); x < field.x + field.width; x++) {
                    const column = x - select.x;
                    if (row >= shown.height || column >= shown.width || shown.alpha(column, row) < 255) { out.push(x + "," + y); break; }
                }
            }
            select.choose(select.currentIndex);
            compare(out, [], "every row of the field lies under the list's opaque fill");
        }

        // The window of an overlay that declares it: a menu's `surface`,
        // which its first open builds.
        function windowOf(owner) {
            if (owner.surface !== undefined) return owner.surface;
            for (let i = 0; i < owner.resources.length; i++)
                if (owner.resources[i].anchor !== undefined) return owner.resources[i];
            return null;
        }

        // Whether a point lies inside a rounded rectangle, half a pixel
        // allowed.
        function inRounded(x, y, box) {
            if (x < box.x - 0.5 || x > box.x + box.width + 0.5 || y < box.y - 0.5 || y > box.y + box.height + 0.5) return false;
            const cx = Math.min(Math.max(x, box.x + box.radius), box.x + box.width - box.radius);
            const cy = Math.min(Math.max(y, box.y + box.radius), box.y + box.height - box.radius);
            return Math.hypot(x - cx, y - cy) <= box.radius + 0.5;
        }

        // Points along the four corners of a rounded rectangle, each corner
        // `radii` round in the order top left, top right, bottom right,
        // bottom left.
        function cornerPoints(left, top, right, bottom, radii) {
            const out = [];
            const corners = [[left, top, 1, 1], [right, top, -1, 1], [right, bottom, -1, -1], [left, bottom, 1, -1]];
            for (let c = 0; c < 4; c++) {
                const [x, y, sx, sy] = corners[c];
                const r = radii[c];
                for (let i = 0; i <= 16; i++) {
                    const angle = Math.PI / 2 * i / 16;
                    out.push([x + sx * (r - r * Math.cos(angle)), y + sy * (r - r * Math.sin(angle))]);
                }
            }
            return out;
        }

        // Whether `item`, drawn `radius` round, shows only inside its
        // window's rounded interior: inside the border, the window's drawn
        // `menu.radius` less the border round. What shows is the item's box
        // cut by each clipping ancestor, whose cut edges draw square, and,
        // when an ancestor's layer masks it through a MultiEffect, cut to
        // that mask too; a mask inside the interior keeps it there. A mask
        // that is not, such as a scroll area's square edge fade, proves
        // nothing, and an outer mask or clip may still keep it inside.
        function drawsInside(item, radius, window) {
            const border = Theme.border.thin;
            const outer = Math.min(Theme.menu.radius, window.width / 2, window.height / 2);
            const inner = { x: border, y: border, width: window.width - 2 * border, height: window.height - 2 * border, radius: Math.max(0, outer - border) };
            const at = boxIn(item, window);
            let left = at.x, top = at.y, right = at.x + at.width, bottom = at.y + at.height;
            const cut = { left: false, top: false, right: false, bottom: false };
            for (let a = item.parent; a !== null && a !== window.contentItem; a = a.parent) {
                if (a.layer.enabled) {
                    const effect = a.parent.children.find(child => String(child).startsWith("QQuickMultiEffect(") && child.maskEnabled);
                    if (effect !== undefined) {
                        const mask = boxIn(effect.maskSource, window);
                        const r = Math.min(effect.maskSource.radius, mask.width / 2, mask.height / 2);
                        if (cornerPoints(mask.x, mask.y, mask.x + mask.width, mask.y + mask.height, [r, r, r, r]).every(([x, y]) => inRounded(x, y, inner))) return true;
                    }
                }
                if (a.clip) {
                    const c = boxIn(a, window);
                    if (top < c.y) { top = c.y; cut.top = true; }
                    if (left < c.x) { left = c.x; cut.left = true; }
                    if (bottom > c.y + c.height) { bottom = c.y + c.height; cut.bottom = true; }
                    if (right > c.x + c.width) { right = c.x + c.width; cut.right = true; }
                }
            }
            if (right <= left || bottom <= top) return true;
            const own = Math.min(radius, at.width / 2, at.height / 2);
            const radii = [cut.top || cut.left ? 0 : own, cut.top || cut.right ? 0 : own, cut.bottom || cut.right ? 0 : own, cut.bottom || cut.left ? 0 : own];
            return cornerPoints(left, top, right, bottom, radii).every(([x, y]) => inRounded(x, y, inner));
        }

        // A long menu open under a rounded theme, nothing checked, its
        // list at its window's size.
        function openRoundedLong() {
            compare(UnitTheme.override({ radius: { sm: 6, md: 12, lg: 16 }, menu: { maxHeight: 90 } }), "ok");
            root.chosen = -1;
            long.open("key");
            const window = longWindow();
            // The window's content item takes the window's size a turn after
            // it shows.
            tryCompare(long.scrollArea, "width", window.width - 2 * Theme.border.thin);
            tryCompare(long.scrollArea, "height", window.height - 2 * long.listInset);
            return window;
        }

        // A highlighted entry scrolled half a row past the top stays inside
        // a rounded menu's interior.
        function test_a_rounded_menu_cuts_a_half_scrolled_highlight() {
            const window = openRoundedLong();
            const items = long.items();
            long.currentIndex = 1;
            const plate = items[1].cursor;
            tryVerify(() => plate.target === items[1] && plate.y === items[1].y && plate.opacity === 1, 2000, "the cursor holds the second entry");
            long.scrollArea.contentY = items[1].y + items[1].height / 2;
            const inside = drawsInside(plate, plate.radius, window);
            long.close();
            root.chosen = 4;
            verify(inside, "the highlight half past the top stays inside the corner");
        }

        // The bar's thumb at the top stays inside a rounded menu's interior.
        function test_a_rounded_menu_cuts_its_thumb() {
            const window = openRoundedLong();
            long.scrollArea.bar.hovered = true;
            const thumb = long.scrollArea.bar.thumb;
            compare(thumb.y, 0, "the thumb is at the top");
            const inside = drawsInside(thumb, thumb.radius, window);
            long.scrollArea.bar.hovered = false;
            long.close();
            root.chosen = 4;
            verify(inside, "the thumb at the top stays inside the corner");
        }

        // The long select open on its second entry under a rounded theme,
        // its list at its window's size.
        function openRoundedSelect() {
            compare(UnitTheme.override({ radius: { sm: 6, md: 12, lg: 16 } }), "ok");
            longSelect.choose(1);
            longSelect.openList();
            const window = windowOf(longSelect);
            const list = selectList(longSelect);
            tryVerify(() => list.itemAtIndex(1) !== null && list.height === window.height - 2 * longSelect.listInset - longSelect.listCover, 1000, "the list builds its entries and takes its window's height");
            compare(list.overflowing, true);
            return [window, list];
        }

        // The highlight on the chosen entry, scrolled half a row past the
        // top, stays inside a rounded select list's interior.
        function test_a_rounded_select_cuts_a_half_scrolled_choice() {
            const [window, list] = openRoundedSelect();
            const entry = list.itemAtIndex(1);
            const plate = list.contentItem.children.find(child => child.follow !== undefined);
            tryVerify(() => plate.target === entry && plate.y === entry.y && plate.opacity === 1, 2000, "the cursor holds the chosen entry");
            list.contentY = entry.y + entry.height / 2;
            const highlight = drawsInside(plate, plate.radius, window);
            longSelect.choose(0);
            verify(highlight, "the highlight half past the top stays inside the corner");
        }

        // The bar's thumb at the top stays inside a rounded select list's
        // interior.
        function test_a_rounded_select_cuts_its_thumb() {
            const [window, list] = openRoundedSelect();
            const bar = list.children.find(child => child.thumb !== undefined);
            list.contentY = 0;
            bar.hovered = true;
            compare(bar.thumb.y, 0, "the thumb is at the top");
            const inside = drawsInside(bar.thumb, bar.thumb.radius, window);
            bar.hovered = false;
            longSelect.choose(0);
            verify(inside, "the thumb at the top stays inside the corner");
        }

        // A square list keeps its rectangular clip and draws no layer.
        function test_a_square_list_draws_no_layer() {
            menu.open("key");
            compare(menu.scrollArea.layer.enabled, false);
            menu.close();
            select.openList();
            compare(selectList(select).layer.enabled, false);
            select.choose(select.currentIndex);
        }

        // An entry keeps the bar's strip exactly while the bar shows: a
        // list less than half a pixel past its view shows no bar and keeps
        // no strip.
        function test_a_select_entry_keeps_the_strip_while_the_bar_shows() {
            select.openList();
            const list = selectList(select);
            tryVerify(() => list.itemAtIndex(0) !== null && list.height > 0, 1000, "the list builds its entries");
            const bar = list.children.find(child => child.thumb !== undefined);
            const margin = list.anchors.bottomMargin;
            list.anchors.bottomMargin = margin + 0.3;
            tryVerify(() => list.contentHeight - list.height > 0.2, 1000, "the content passes the view by a fraction: " + (list.contentHeight - list.height));
            compare(bar.visible, false, "no bar for a fraction of a pixel");
            const entry = list.itemAtIndex(1);
            compare(entry.barRoom, 0, "no strip without a bar");
            compare(entry.rightPadding, entry.sidePadding, "an entry keeps only its side padding");
            list.anchors.bottomMargin = Qt.binding(() => select.listInset + select.listCover);
            select.choose(select.currentIndex);
        }

        function test_select_chooses_and_reads_its_role() {
            compare(select.count, 3);
            compare(select.currentText, "one");
            select.choose(2);
            compare(select.currentIndex, 2);
            compare(select.currentText, "three");
            select.choose(7);
            compare(select.currentIndex, 2);
            compare(roled.currentText, "alpha");
            roled.choose(1);
            compare(roled.currentText, "beta");
            select.openList();
            compare(select.listOpen, true);
            compare(OverlayState.open, 1);
            select.choose(1);
            compare(select.listOpen, false);
            compare(OverlayState.open, 0);
        }

        function test_select_activation_is_a_user_choice_only() {
            roled.model = [{ name: "alpha" }, { name: "beta" }];
            roled.currentIndex = 0;
            activations.clear();
            roled.choose(1);
            compare(activations.count, 1);
            compare(activations.signalArguments[0][0], 1);
            roled.choose(1);
            compare(activations.count, 2, "the current entry is still a user choice");
            roled.choose(-1);
            roled.choose(2);
            compare(activations.count, 2, "invalid entries emit nothing");
            roled.model = [{ name: "new alpha" }, { name: "new beta" }];
            roled.currentIndex = 0;
            compare(activations.count, 2, "model and index updates do not activate");
            roled.model = [{ name: "alpha" }, { name: "beta" }];
        }

        function test_choosing_the_current_entry_keeps_the_index_binding() {
            root.wanted = 0;
            bound.choose(0);
            root.wanted = 2;
            compare(bound.currentIndex, 2);
            bound.choose(1);
            root.wanted = 0;
            compare(bound.currentIndex, 1);
        }

        function test_enter_opens_the_closed_select() {
            root.Window.window.requestActivate();
            select.forceActiveFocus();
            tryCompare(select, "activeFocus", true);
            keyClick(Qt.Key_Return);
            compare(select.listOpen, true);
            select.choose(0);
            compare(select.listOpen, false);
        }

        // With nothing to choose the closed control reads its empty text,
        // and no key, click or call opens a list that would repeat it; the
        // control keeps the keyboard.
        function test_an_empty_select_opens_no_list() {
            root.Window.window.requestActivate();
            emptySelect.forceActiveFocus();
            tryCompare(emptySelect, "activeFocus", true);
            compare(emptySelect.contentItem.text, emptySelect.emptyText);
            for (const key of [Qt.Key_Return, Qt.Key_Space, Qt.Key_Down]) {
                keyClick(key);
                compare(emptySelect.listOpen, false, "key " + key + " leaves the empty select closed");
            }
            mouseClick(emptySelect);
            compare(emptySelect.listOpen, false, "a click leaves the empty select closed");
            emptySelect.openList();
            compare(emptySelect.listOpen, false, "openList leaves the empty select closed");
            compare(OverlayState.open, 0);
            compare(emptySelect.activeFocus, true, "the empty select keeps the keyboard");
            // Nothing promises the click that does nothing: the pointer stays
            // the arrow and the chevron draws in the disabled text colour,
            // while a select with entries keeps the hand and its icon colour.
            verify(!Qt.colorEqual(Theme.color.textDisabled, Theme.textField.icon), "the disabled colour differs from the chevron's");
            compare(showsHand(emptySelect), false, "the empty select shows the arrow");
            verify(Qt.colorEqual(emptySelect.indicator.color, Theme.color.textDisabled), "the empty select's chevron draws disabled");
            compare(showsHand(select), true, "a select with entries shows the hand");
            verify(Qt.colorEqual(select.indicator.color, Theme.textField.icon), "a select with entries draws its chevron in its icon colour");
            mouseMove(root, root.width - 1, root.height - 1);
        }

        // Qt takes the cursor over an item from a handler of the item that
        // sets a cursor shape and is hovered; with none, the arrow shows.
        function showsHand(item) {
            mouseMove(item, item.width / 2, item.height / 2);
            for (const child of item.data) {
                if (child instanceof HoverHandler && child.cursorShape === Qt.PointingHandCursor && child.hovered) return true;
            }
            return false;
        }

        function test_select_keys_move_the_choice_while_closed() {
            // A popup window shown by an earlier test may still hold the
            // window focus; the keys go to the test window.
            root.Window.window.requestActivate();
            select.forceActiveFocus();
            tryCompare(select, "activeFocus", true);
            keyClick(Qt.Key_Down);
            compare(select.currentIndex, 1);
            keyClick(Qt.Key_Up);
            compare(select.currentIndex, 0);
        }

        function tipWindow(owner) {
            owner.shown = true;
            verify(owner.tracker !== null);
            return owner.tracker.popup;
        }

        function descendants(node) {
            let out = [];
            for (const child of node.children) {
                out.push(child);
                out = out.concat(descendants(child));
            }
            return out;
        }
        function firstDescendant(node, test) {
            const all = descendants(node);
            for (const child of all)
                if (test(child)) return child;
            return null;
        }
        function descendantsWhere(node, test) {
            return descendants(node).filter(test);
        }

        // A short tip is its text's width; a long one stops at
        // `tooltip.maxWidth` and wraps inside the padding.
        function test_tooltip_wraps_past_its_maximum_width() {
            const short = tipWindow(tip);
            const long = tipWindow(longTip);
            const shortContent = firstDescendant(short.contentItem, child => child.objectName === "tooltipContent");
            const longContent = firstDescendant(long.contentItem, child => child.objectName === "tooltipContent");
            const shortLabel = firstDescendant(short.contentItem, child => child.objectName === "tooltipTitle");
            const longLabel = firstDescendant(long.contentItem, child => child.objectName === "tooltipTitle");
            compare(short.width, Math.ceil(shortLabel.implicitWidth) + 2 * Theme.tooltip.paddingX);
            compare(long.width, Theme.tooltip.maxWidth + 2 * Theme.tooltip.paddingX);
            verify(longLabel.lineCount > 1, "the long tip wraps: " + longLabel.lineCount);
            compare(long.height, longContent.height + 2 * Theme.tooltip.paddingY);
            compare(longContent.x, Theme.tooltip.paddingX);
            // Under a pill theme with a small pad the text moves in until it
            // clears the round end.
            compare(UnitTheme.override({ tooltip: { radius: 4096, paddingX: 2 } }), "ok");
            tryVerify(() => shortContent.x > 2, 1000, "the rounded tip's text moved in: " + shortContent.x);
        }

        function test_tooltip_draws_no_key_caps() {
            const window = tipWindow(detailsTip);
            const caps = descendantsWhere(window.contentItem, child => child.caps !== undefined);
            compare(caps.length, 0);
        }

        function test_tooltip_title_and_details_use_their_roles() {
            const window = tipWindow(detailsTip);
            const title = firstDescendant(window.contentItem, child => child.objectName === "tooltipTitle");
            const details = descendantsWhere(window.contentItem, child => child.objectName.indexOf("tooltipDetail") === 0 || child.objectName.indexOf("tooltipCount") === 0)
                .filter(child => child.role !== undefined);
            compare(title.role, "tooltip");
            verify(details.length > 0, "the tooltip has detail labels");
            for (const label of details)
                compare(label.role, "itemHint", label.objectName + " " + label.text);
        }

        function test_tooltip_count_rows_align_and_hide_zeroes() {
            const window = tipWindow(detailsTip);
            const values = descendantsWhere(window.contentItem, child => child.objectName === "tooltipCountValue" && child.text !== "0");
            verify(values.length >= 3, "the tooltip has visible count values");
            const edge = values[0].mapToItem(window.contentItem, values[0].width, 0).x;
            for (const value of values)
                fuzzyCompare(value.mapToItem(window.contentItem, value.width, 0).x, edge, 0.5, value.text);
            const zero = firstDescendant(window.contentItem, child => child.objectName === "tooltipCountLabel" && child.text === "Themes");
            verify(zero !== null, "the zero count row exists as data");
            compare(zero.parent.height, 0);
            compare(zero.parent.visible, false);
        }

        function test_tooltip_padding_uses_tokens() {
            const window = tipWindow(detailsTip);
            const content = firstDescendant(window.contentItem, child => child.objectName === "tooltipContent");
            compare(content.x, Theme.tooltip.paddingX);
            compare(content.y, Theme.tooltip.paddingY);
            compare(window.height, content.height + 2 * Theme.tooltip.paddingY);
        }

        function test_a_tooltip_removed_from_a_live_anchor_releases_its_handlers() {
            const handlers = () => host.resources.filter(item => String(item).indexOf("QQuickHoverHandler") === 0 || String(item).indexOf("QQuickTapHandler") === 0).length;
            const count = handlers();
            const transient = transientTooltip.createObject(host);
            verify(transient !== null);
            compare(handlers(), count + 2);
            transient.destroy();
            tryVerify(() => handlers() === count);
        }

        function test_idle_tooltip_builds_no_popup_and_close_destroys_it() {
            mouseMove(root, root.width - 1, root.height - 1);
            compare(tip.tracker, null);
            compare(UnitTheme.override({ tooltip: { delay: 20 } }), "ok");
            mouseMove(host, host.width / 2, host.height / 2);
            tryCompare(tip, "opened", true);
            verify(tip.tracker !== null);
            mouseMove(root, root.width - 1, root.height - 1);
            tryCompare(tip, "opened", false);
            compare(tip.tracker, null);
        }

        function test_hidden_or_disabled_anchor_closes_and_destroys_the_popup() {
            compare(UnitTheme.override({ tooltip: { delay: 20 } }), "ok");
            for (const property of ["visible", "enabled"]) {
                mouseMove(host, host.width / 2, host.height / 2);
                tryCompare(tip, "opened", true);
                host[property] = false;
                tryCompare(tip, "opened", false);
                compare(tip.tracker, null);
                mouseMove(root, root.width - 1, root.height - 1);
                host[property] = true;
            }
        }

        function test_tooltip_opens_after_the_delay_and_not_under_an_overlay() {
            compare(UnitTheme.override({ tooltip: { delay: 50 } }), "ok");
            mouseMove(host, host.width / 2, host.height / 2);
            tryCompare(tip, "opened", true, 2000);
            mouseMove(root, root.width - 1, root.height - 1);
            tryCompare(tip, "opened", false);
            popover.open();
            mouseMove(host, host.width / 2, host.height / 2);
            tryCompare(tooltipDelay(tip), "running", false);
            compare(tip.opened, false);
            popover.close();
            mouseMove(root, root.width - 1, root.height - 1);
            // The other order: a shown tooltip closes when an overlay opens.
            mouseMove(host, host.width / 2, host.height / 2);
            tryCompare(tip, "opened", true, 2000);
            popover.open();
            compare(tip.opened, false);
            popover.close();
            mouseMove(root, root.width - 1, root.height - 1);
        }

        // A press closes the tooltip and it stays closed while the pointer
        // rests, so it never covers what the press opened; it opens again
        // once the pointer left the item and came back.
        function test_tooltip_stays_closed_after_a_press_until_the_pointer_leaves() {
            compare(UnitTheme.override({ tooltip: { delay: 50 } }), "ok");
            mouseMove(host, host.width / 2, host.height / 2);
            tryCompare(tip, "opened", true, 2000);
            mouseClick(host, host.width / 2, host.height / 2);
            compare(tip.opened, false);
            tryCompare(tooltipDelay(tip), "running", false);
            compare(tip.opened, false);
            mouseMove(root, root.width - 1, root.height - 1);
            mouseMove(host, host.width / 2, host.height / 2);
            tryCompare(tip, "opened", true, 2000);
            mouseMove(root, root.width - 1, root.height - 1);
        }
    }
}
