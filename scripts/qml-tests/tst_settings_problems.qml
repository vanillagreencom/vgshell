import QtQuick
import QtQuick.Window
import QtTest
import qs.Unit
import qs.Commons
import qs.Core
import qs.Ui
import "../../shell/plugins/vgs.settings"

// Drive the real list badge and page. One Registry start error checks
// content geometry and pixels on each tab. The list's real shortcut
// diagnostic checks the badge's accessible result and shared tooltip
// routing through pointer and keyboard, without a private problem view.
Item {
    id: root
    width: 720
    height: 520
    readonly property string startError: "build failed: service: file:///fixture/Service.qml:12: No such type"
    readonly property string shortcutError: "hyprland: SUPER+COMMA for acme.problem:toggle skipped: already bound by acme.holder"

    function row(errors) {
        // A fitting page isolates the opaque strip's coverage from the
        // scrolling fade's GPU mask, which the offscreen backend does not
        // draw. tst_scroll and nested settings smoke own that mask.
        const schema = { option: { type: "boolean", label: "Option", group: "Options" } };
        const settings = { option: true };
        return {
            id: "acme.problem", name: "Problem app", version: "1", description: "", author: "VGS", license: "", icon: "package", source: "bundled",
            enabled: true, alwaysOn: false, placed: false, kinds: ["service"], capabilities: [],
            schema: schema, settings: settings, settingChoices: {}, fieldRows: PluginLogic.fieldRows(schema, {}),
            withheldFields: [], fieldProblems: {}, status: [], secretLabel: "", guide: null,
            tuis: [], builtins: [], opens: "", paneHolder: "", binds: [], requirements: [], errors: errors
        };
    }
    Item {
        id: manager
        property var shell: null
        property string title: "Plugins"
        property string notice: ""
        property var plugins: []
        property var installFailures: ({})
        property var opened: []
        function replyOf() { return ""; }
        function headReplies() { return []; }
        function openPage(id, tab) { opened = [id, tab]; }
        function openRow(id) { opened = [id, ""]; }
    }
    Component {
        id: pageComponent
        PluginPage { width: root.width; height: root.height; maximumHeight: root.height; panel: manager }
    }
    Component {
        id: listComponent
        ListPage { width: root.width; height: root.height; maximumHeight: root.height; panel: manager }
    }

    UnitCase {
        name: "SettingsProblems"
        when: windowShown

        function descendants(item) {
            let out = [];
            for (const child of item.children) out = out.concat([child], descendants(child));
            return out;
        }
        function init() {
            compare(Theme.fileState, "unit");
            UnitTheme.reset();
            compare(UnitTheme.override({ tooltip: { delay: 10 }, motion: { scale: 0 } }), "ok");
            manager.plugins = [];
            manager.opened = [];
            ShortcutLabels.names = Object.assign({}, ShortcutLabels.names, {
                "CODE:44": { keysym: "Cyrillic_zhe", codepoint: 0x0436 }
            });
            root.forceActiveFocus();
            mouseMove(root, root.width - 1, root.height - 1);
        }
        function test_problem_is_first_visible_content_below_pinned_tabs_data() {
            return [{ tag: "Settings", tab: 0 }, { tag: "Details", tab: 1 }];
        }
        function test_problem_is_first_visible_content_below_pinned_tabs(data) {
            const row = root.row([root.startError]);
            manager.plugins = [row];
            const page = createTemporaryObject(pageComponent, root, { row: row });
            verify(page !== null);
            const tabs = descendants(page).find(item => item instanceof TabPages);
            tabs.currentIndex = data.tab;
            verify(renderedFrame(page));
            const line = descendants(page).find(item => item.text === Reply.line(root.startError));
            verify(line !== undefined, "the existing problem line is drawn");
            const barBottom = tabs.tabs.mapToItem(page, 0, tabs.tabs.height).y;
            const lineTop = line.mapToItem(page, 0, 0).y;
            fuzzyCompare(lineTop, barBottom + Theme.stack.section, 1, "problem content starts at the normal tab gap");
            verify(line.visible && lineTop >= barBottom, "the pinned strip does not cover the line");
            const contentTop = tabs.currentPage.mapToItem(page, 0, 0).y;
            fuzzyCompare(contentTop, lineTop + line.height + Theme.stack.page, 1, "content follows the visible problem without a blank band");
            const image = grabImage(page);
            const color = Qt.color(Theme.color.danger);
            const at = line.mapToItem(page, 0, 0);
            let ink = 0;
            for (let y = Math.ceil(at.y); y < Math.min(image.height, at.y + line.height); y++)
                for (let x = Math.ceil(at.x); x < Math.min(image.width, at.x + line.width); x++)
                    if (Math.abs(image.red(x, y) - color.r * 255) < 12
                        && Math.abs(image.green(x, y) - color.g * 255) < 12
                        && Math.abs(image.blue(x, y) - color.b * 255) < 12) ink++;
            verify(ink > 0, "the error text is visible in the rendered page, not behind the opaque cover");
        }
        function problemBadge(list) {
            return descendants(list).find(item => item instanceof Badge && item.visible && item.text === "1");
        }
        function tooltipOf(badge) { return descendants(badge).find(item => item instanceof Tooltip); }
        function popupLink(tip) {
            return descendants(tip.tracker.popup.contentItem).find(item => item instanceof LinkText && item.visible && item.text.indexOf("Settings/Keys") !== -1);
        }
        function opened(tip) {
            tryCompare(tip, "opened", true);
            mouseMove(tip.tracker.popup.contentItem, -10, -10);
        }
        function test_badge_help_and_link_are_reachable_data() {
            return [
                { tag: "hover and pointer", keyboard: false, shortcut: root.shortcutError, displayed: "Super+," },
                { tag: "focus and keyboard", keyboard: true, shortcut: root.shortcutError, displayed: "Super+," },
                { tag: "active layout key", keyboard: true, shortcut: "hyprland: SUPER+code:44 for acme.problem:toggle skipped: already bound by acme.holder", displayed: "Super+Ж" }
            ];
        }
        function test_badge_help_and_link_are_reachable(data) {
            const row = root.row([data.shortcut]);
            manager.plugins = [row, Object.assign({}, root.row([]), { id: "acme.holder", name: "Holding app" })];
            const list = createTemporaryObject(listComponent, root);
            verify(list !== null);
            verify(renderedFrame(list));
            const badge = problemBadge(list);
            verify(badge !== undefined);
            compare(badge.tone, "warning");
            compare(badge.activeFocusOnTab, true, "the explanation is reachable by Tab, not only forced focus");
            const words = Reply.line(data.shortcut, manager.plugins, ShortcutLabels.keyCaps);
            verify(words.indexOf(data.displayed) !== -1, "the actual badge uses the shared printable layout name");
            compare(badge.Accessible.name, PageReference.plain(words), "the badge reads its complete problem explanation");
            const tip = tooltipOf(badge);
            verify(tip !== undefined, "Badge composes the shared Tooltip");
            compare(tip.text, words);
            if (data.keyboard) badge.forceActiveFocus(Qt.TabFocusReason);
            else mouseMove(badge, badge.width / 2, badge.height / 2);
            opened(tip);
            const link = popupLink(tip);
            verify(link !== undefined);
            if (data.keyboard) {
                keyClick(Qt.Key_Return);
                compare(manager.opened, [], "Enter on the help source does not open the list's unrelated current row");
                keyClick(Qt.Key_Tab);
                compare(badge.activeFocus, true, "the source keeps keyboard ownership");
                compare(tip.currentLine, 0);
                const ring = descendants(link).find(item => item instanceof FocusRing && item.visible);
                verify(ring !== undefined, "the current link shows its focus ring");
                compare(descendants(badge).find(item => item instanceof FocusRing).visible, false, "only the current link draws a ring");
                keyClick(Qt.Key_Return);
            } else {
                const popup = tip.tracker.popup;
                mouseMove(popup.contentItem, popup.width / 2, popup.height / 2);
                tryCompare(popup, "pointerOver", true, 5000, "the pointer crosses to the tooltip");
                const box = link.linkBox;
                mouseClick(link, box.x + box.width / 2, box.y + box.height / 2);
            }
            compare(manager.opened, ["acme.problem", "Settings/Keys"]);
            tryCompare(tip, "opened", false);
        }
    }
}
