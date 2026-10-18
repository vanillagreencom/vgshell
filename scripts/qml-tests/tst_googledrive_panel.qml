import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.google-drive" as Drive
import "../../shell/plugins/vgs.google-drive/GoogleDriveLogic.js" as Logic

// The Google Drive popover by keyboard alone, over a stub status value:
// one folder pair whose hourly sync is out of date (so the callout shows
// its fix), one file that needs the user with a kept copy, and two notes.
// Tab and Backtab reach every control in reading order, each with its
// focus ring: the gear, the callout's fix, the kept-copy info, Show older
// copy, the notes fold line, Pause and Sync now. On the fold line Return,
// Enter and Space toggle the notes, Right opens and Left closes them. Return
// on each action asks the stub shell exactly what a click asks. The slot
// that hosts a summoned plugin is a stand-in naming the plugin's Settings
// page, as in tst_pane.
Item {
    id: root
    width: 800
    height: 600

    // Each request the panel makes of the stub shell, in order.
    property var calls: []
    property int settingsOpened: 0

    function record(call) {
        root.calls = root.calls.concat([call]);
        return "ok";
    }

    Button { id: outside; text: "Outside" }

    Component {
        id: hostComponent
        Item {
            id: host
            y: outside.height + Theme.space.md
            width: panel.implicitWidth
            height: panel.implicitHeight
            property string settingsPage: "vgs.google-drive"
            property alias panel: panel
            function openSettingsPage() { root.settingsOpened += 1; }
            Drive.Panel { id: panel; anchors.fill: parent }
        }
    }

    TestCase {
        name: "googledrive_panel"
        when: windowShown

        property Item host: null
        property Item panel: null

        // A status record as bin/google-drive writes it, with times read
        // from the clock the panel reads (test-google-drive-logic.js holds
        // the same shapes): the both-changed row whose older copy VGS kept
        // needs the user; a removal on each side is a note.
        function cloud() {
            const now = Time.now.getTime(), hour = 3600 * 1000;
            const iso = ms => new Date(ms).toISOString();
            const pair = { id: "docs", label: "Documents", remote: "Docs", local: "/home/me/gdrive", state: "idle", lastSuccess: iso(now - hour), staleAfter: iso(now + hour), lastError: null, changes: { added: 1, updated: 0 } };
            const conflicts = [
                { kind: "both-changed", pair: "docs", pairLabel: "Documents", path: "taxes/2025.xlsx", localPath: "/home/me/gdrive/taxes/2025.xlsx", storedPath: "/home/me/.local/state/vgshell/google-drive/pairs/docs/conflicts/20261010T110000Z-7/taxes/2025.xlsx", since: iso(now - hour), needs: "you" },
                { kind: "removed-on-drive", pair: "docs", pairLabel: "Documents", path: "old.txt", localPath: "/home/me/gdrive/old.txt", since: iso(now - hour), needs: "nothing" },
                { kind: "removed-locally", pair: "docs", pairLabel: "Documents", path: "taxes/receipts.pdf", localPath: "/home/me/gdrive/taxes/receipts.pdf", since: iso(now - hour), needs: "nothing" }
            ];
            const record = { state: "idle", paused: false, units: "stale", lastSuccess: iso(now - hour), staleAfter: iso(now + hour), lastError: null, pairs: [pair], conflicts: conflicts, needsYou: 1, attention: { reasons: ["conflicts", "units-stale"], key: "0123456789abcdef", notified: false }, writtenAt: iso(now) };
            const parsed = Logic.parseStatus(JSON.stringify(record));
            verify(parsed.ok, "the stub record is one the runner writes: " + JSON.stringify(parsed));
            return Logic.cloudValue(parsed.record, "");
        }

        function shell() {
            return {
                status: { values: { cloud: cloud() } },
                ipc: { call: (name, payload) => root.record(["ipc", name, payload]) },
                tui: { edit: file => root.record(["edit", file]), run: name => root.record(["tui", name]) },
                surfaces: { openPage: (page, tab) => root.record(["openPage", page, tab]), hide: kind => root.record(["hide", kind]) }
            };
        }

        function init() {
            root.Window.window.requestActivate();
            tryCompare(root.Window.window, "active", true);
            root.calls = [];
            root.settingsOpened = 0;
            host = createTemporaryObject(hostComponent, root);
            verify(host !== null);
            panel = host.panel;
            panel.shell = shell();
            waitForRendering(panel);
            outside.forceActiveFocus(Qt.OtherFocusReason);
        }

        function cleanup() {
            host = null;
            panel = null;
        }

        function find(item, wanted) {
            for (const child of item.children) {
                if (child.visible && wanted(child)) return child;
                const found = find(child, wanted);
                if (found !== null) return found;
            }
            return null;
        }

        // A shown control whose text is TEXT, as the logic words it.
        function control(text) {
            const found = find(panel, item => "focusPolicy" in item && item.text === text);
            verify(found !== null, "a control reads " + JSON.stringify(text));
            return found;
        }

        // Every focus stop of the popover in reading order, found by what
        // each one is, never by a word the test states.
        function stops() {
            const gear = find(panel, item => "focusPolicy" in item && item.iconName === "settings");
            verify(gear !== null, "the gear shows");
            const info = find(panel, item => "infoOpen" in item);
            verify(info !== null, "the kept-copy info shows");
            return [gear, control(panel.callout.action.label), info, control(panel.review.needs[0].action.label),
                control(panel.review.notesLine), control(panel.footer.pause.text), control(panel.footer.sync.text)];
        }

        function rings(item, target) {
            let found = [];
            for (const child of item.children) {
                if ("keyboardFocus" in child && child.target === target) found.push(child);
                found = found.concat(rings(child, target));
            }
            return found;
        }

        function focused() { return root.Window.window.activeFocusItem; }

        // Tab from the control before the popover onto STOP.
        function tabTo(stop) {
            for (let presses = 0; focused() !== stop; presses++) {
                verify(presses < 20, "Tab reaches " + stop);
                keyClick(Qt.Key_Tab);
            }
        }

        // The note rows show while the fold is open, and only then.
        function notesShown() {
            const name = find(panel, item => item.text === panel.review.notes[0].name && "role" in item);
            return name !== null;
        }

        function test_tab_reaches_every_control_in_reading_order_data() {
            return [{ tag: "tab", key: Qt.Key_Tab, reason: Qt.TabFocusReason }, { tag: "backtab", key: Qt.Key_Backtab, reason: Qt.BacktabFocusReason }];
        }

        function test_tab_reaches_every_control_in_reading_order(data) {
            const order = stops();
            const expected = data.key === Qt.Key_Tab ? order : order.slice().reverse();
            for (const stop of expected) {
                keyClick(data.key);
                compare(focused(), stop, "the next stop is " + stop);
                compare(stop.activeFocus, true);
                compare(stop.focusReason, data.reason);
                const ring = rings(stop, stop).concat(rings(stop.parent, stop));
                verify(ring.length > 0, "the stop draws a focus ring: " + stop);
                verify(ring.some(r => r.visible), "the focus ring shows on " + stop);
            }
            keyClick(data.key);
            compare(focused(), outside, "the popover holds no other stop");
        }

        function test_fold_line_keys() {
            const fold = control(panel.review.notesLine);
            tabTo(fold);
            compare([panel.notesOpen, notesShown()], [false, false], "the notes start folded");
            const steps = [
                [Qt.Key_Return, true], [Qt.Key_Return, false],
                [Qt.Key_Enter, true], [Qt.Key_Enter, false],
                [Qt.Key_Space, true], [Qt.Key_Space, false],
                [Qt.Key_Right, true], [Qt.Key_Right, true],
                [Qt.Key_Left, false], [Qt.Key_Left, false]
            ];
            for (const [key, open] of steps) {
                keyClick(key);
                compare(panel.notesOpen, open, "key " + key);
                compare(notesShown(), open, "the notes list follows the fold after key " + key);
                compare(focused(), fold, "the fold line keeps focus");
            }
            compare(root.calls, [], "the fold asks the shell nothing");
        }

        // A click and Return on each action make the same requests.
        function test_return_does_what_a_click_does_data() {
            return [
                { tag: "gear", which: 0 },
                { tag: "callout fix", which: 1 },
                { tag: "show older copy", which: 3 },
                { tag: "pause", which: 5 },
                { tag: "sync now", which: 6 }
            ];
        }

        function test_return_does_what_a_click_does(data) {
            const stop = stops()[data.which];
            mouseClick(stop);
            const clicked = [root.calls, root.settingsOpened];
            verify(root.calls.length > 0 || root.settingsOpened > 0, "a click asks something");
            root.calls = [];
            root.settingsOpened = 0;
            outside.forceActiveFocus(Qt.OtherFocusReason);
            tabTo(stop);
            keyClick(Qt.Key_Return);
            compare([root.calls, root.settingsOpened], clicked);
        }

        // The requests themselves, held apart from the panel's code.
        function test_each_action_asks_its_owner() {
            const order = stops();
            const folder = panel.review.needs[0].action.folder;
            const rows = [
                [1, [["openPage", "vgs.google-drive", "Details"], ["hide", "panel"]]],
                [3, [["edit", folder + "/"]]],
                [5, [["ipc", "pause", ""]]],
                [6, [["ipc", "sync", ""]]]
            ];
            for (const [which, wanted] of rows) {
                root.calls = [];
                outside.forceActiveFocus(Qt.OtherFocusReason);
                tabTo(order[which]);
                keyClick(Qt.Key_Return);
                compare(root.calls, wanted);
            }
            outside.forceActiveFocus(Qt.OtherFocusReason);
            tabTo(order[0]);
            keyClick(Qt.Key_Return);
            compare(root.settingsOpened, 1, "the gear opens the Settings page");
        }
    }
}
