import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.themes"

// A theme row's action stands inside its own item, nearer its own name than
// the next row's, and the palette icon centres on the name line's x-height
// within half a device pixel, on a whole device pixel, at 1x and at 2x.
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

    Component {
        id: ledScene
        Window {
            width: 460
            height: 160
            color: "black"
            property alias row: ledRow
            property alias metrics: ledMetrics
            ThemeRow {
                id: ledRow
                x: 8
                y: 8
                width: 440
                name: "catppuccin-macchiato"
                source: "dark, wallpapers 13 MB"
                actionLabel: "Install"
                packageState: "catalog"
            }
            FontMetrics { id: ledMetrics }
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

        function test_the_palette_icon_centres_on_the_name_data() {
            return [{ tag: "1x", scale: 1 }, { tag: "2x", scale: 2 }];
        }

        // The x-height centre is read from the drawn name's own baseline
        // and the font's x-height, not from the label's reading of it, in
        // device pixels; the same reading must reject the item's top the
        // icon stood on before, and the capital centre.
        function test_the_palette_icon_centres_on_the_name(data) {
            const screen = Qt.application.screens[data.scale - 1];
            const scene = ledScene.createObject(null, { screen: screen, x: screen.virtualX + 10, y: screen.virtualY + 10 });
            scene.visible = true;
            const content = item(scene.row).contentItem;
            const mark = find(content, child => child instanceof Icon);
            const name = title(scene.row);
            scene.metrics.font = name.font;
            const ratio = name.Screen.devicePixelRatio;
            const baseline = name.mapToItem(content, 0, name.baselineOffset).y;
            const xCentre = baseline - scene.metrics.xHeight / 2;
            const capCentre = baseline - scene.metrics.capitalHeight / 2;
            const off = (top, centre) => Math.abs(top + mark.height / 2 - centre) * ratio;
            const top = mark.mapToItem(scene.contentItem, 0, 0).y;
            const found = [ratio, mark.name, off(mark.y, xCentre), Math.abs(top * ratio - Math.round(top * ratio)),
                off(0, xCentre), off(Math.round((capCentre - mark.height / 2) * ratio) / ratio, xCentre)];
            scene.destroy();
            compare(found[0], data.scale, "the window draws at its screen's scale");
            compare(found[1], "palette");
            verify(found[2] <= 0.5, "the icon is " + found[2] + " device px off the x-height centre");
            verify(found[3] < 0.01, "the icon's top " + top + " is on a whole device pixel");
            verify(found[4] > 0.5, "control: the item's top reads as level");
            verify(found[5] > 0.5, "control: the capital centre reads as level");
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
