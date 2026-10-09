import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.themes"

Item {
    width: 640
    height: 600

    Column {
        id: rows
        width: Theme.size.panel.lg
        spacing: Theme.stack.row
        ThemeRow {
            id: own
            width: parent.width
            name: "catppuccin-macchiato"
            source: "dark, wallpapers 13 MB"
            actionLabel: "Install"
            packageState: "catalog"
            rowKey: "own"
            currentKey: "own"
            listActiveFocus: true
            swatch: ({background: Theme.color.background, foreground: Theme.color.text,
                      accent: Theme.color.accent, success: Theme.color.success,
                      warning: Theme.color.warning, danger: Theme.color.danger, info: Theme.color.info})
        }
        ThemeRow {
            id: next
            width: parent.width
            name: "catppuccin-latte"
            source: "light, wallpapers 13 MB"
            actionLabel: "Install"
            packageState: "catalog"
        }
    }

    TestCase {
        name: "themeRow"
        when: windowShown

        Component { id: detachedAction; RowAction { text: "Install" } }

        function find(item, accepts) {
            if (accepts(item)) return item;
            for (const child of item.children) {
                const match = find(child, accepts);
                if (match !== null) return match;
            }
            return null;
        }

        function item(row) { return find(row, child => child instanceof ListItem); }
        function action(row) { return find(row, child => child instanceof RowAction); }
        function title(row) { return find(item(row).contentItem, child => child instanceof Label && child.role === "item"); }
        function inside(action, item) {
            const p = action.mapToItem(item, 0, 0);
            return p.x >= item.leftPadding && p.y >= item.topPadding
                && p.x + action.width <= item.width - item.rightPadding
                && p.y + action.height <= item.height - item.bottomPadding;
        }
        function nearerOwnName(action) {
            const a = action.mapToItem(rows, 0, action.height / 2);
            const o = title(own).mapToItem(rows, 0, title(own).height / 2);
            const n = title(next).mapToItem(rows, 0, title(next).height / 2);
            return Math.abs(a.y - o.y) < Math.abs(a.y - n.y);
        }

        function test_action_belongs_to_its_theme_data() {
            return [
                {tag: "normal-install", width: Theme.size.panel.lg, installed: false},
                {tag: "narrow-install", width: Theme.size.panel.sm, installed: false},
                {tag: "normal-wallpapers", width: Theme.size.panel.lg, installed: true},
                {tag: "narrow-wallpapers", width: Theme.size.panel.sm, installed: true}
            ];
        }

        function test_action_belongs_to_its_theme(data) {
            rows.width = data.width;
            own.installed = data.installed;
            own.applicable = data.installed;
            own.actionLabel = data.installed ? "Download wallpapers" : "Install";
            wait(0);
            const link = action(own);
            verify(inside(link, item(own)));
            verify(nearerOwnName(link));
            verify(title(own).contentWidth <= title(own).width);
            const subtitle = find(item(own).contentItem, child => child instanceof Label && child.role === "itemHint");
            verify(subtitle.contentWidth <= subtitle.width);
            verify(link.implicitWidth <= link.width);
            compare(own.requestAction(), data.installed);

            // The same geometry assertions must reject an action below its item.
            const detached = createTemporaryObject(detachedAction, rows.parent);
            const below = item(own).mapToItem(rows.parent, item(own).leftPadding, item(own).height + Theme.stack.row);
            detached.x = below.x;
            detached.y = below.y;
            // Qt Quick Test's expectFailContinue reaches both planted checks.
            // https://doc.qt.io/qt-6/qml-qttest-testcase.html#expectFailContinue-method
            expectFailContinue("", "the action below the item is outside its padding");
            verify(inside(detached, item(own)));
            expectFailContinue("", "the detached action is nearer the next theme");
            verify(nearerOwnName(detached));
        }
    }
}
