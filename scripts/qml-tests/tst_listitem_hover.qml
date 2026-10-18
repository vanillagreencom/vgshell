import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// ListItem's first hover frame uses the theme fill, without a blend from
// transparent black. Google Drive's folder pairs use this shared row.
Rectangle {
    id: root
    width: 520
    height: 180
    color: Theme.color.surface

    ListItem {
        id: row
        x: 24
        y: 24
        width: 472
        text: "Legal Documents"
        secondary: "Both ways"
        iconName: "folder-sync"
    }

    TestCase {
        name: "listitemHover"
        when: windowShown

        function cleanup() {
            mouseMove(root, root.width - 1, root.height - 1);
            UnitTheme.reset();
        }

        function test_hover_uses_its_theme_fill_from_the_first_frame_data() {
            return [{ tag: "dark", theme: "vgs" }, { tag: "light", theme: "catalog/flexoki-light" }];
        }

        function test_hover_uses_its_theme_fill_from_the_first_frame(data) {
            const request = new XMLHttpRequest();
            request.open("GET", Qt.resolvedUrl("../../themes/" + data.theme + "/theme.json"), false);
            request.send();
            compare(UnitTheme.override(JSON.parse(request.responseText).tokens), "ok");
            mouseMove(root, root.width - 1, root.height - 1);
            tryCompare(row, "hovered", false);
            tryCompare(row.background, "color", Qt.rgba(0, 0, 0, 0));
            // QtTest grabImage renders the scene itself, including the
            // transparent row over its parent (tst_grouplist.qml).
            const rest = grabImage(root).pixel(480, 40);
            const fill = Qt.color(Theme.rowFill(Theme.listItem.hover, false));
            const hover = Qt.rgba(fill.r * fill.a + rest.r * (1 - fill.a),
                                  fill.g * fill.a + rest.g * (1 - fill.a),
                                  fill.b * fill.a + rest.b * (1 - fill.a), 1);
            mouseMove(row, row.width - 12, row.height / 2);
            compare(row.hovered, true);
            const first = grabImage(root).pixel(480, 40);
            // Sample during the shipped hover duration as well: a colour
            // blend can reach the right endpoint after a dark middle frame.
            wait(Theme.motion.duration.fast / 5);
            const middle = grabImage(root).pixel(480, 40);
            for (const channel of ["r", "g", "b"]) {
                for (const frame of [first, middle])
                    verify(frame[channel] + 1 / 255 >= Math.min(rest[channel], hover[channel]),
                           data.tag + " frame is darker than rest and hover: " + frame);
                verify(Math.abs(first[channel] - hover[channel]) <= 1 / 255,
                       data.tag + " first frame uses the hover fill: " + first + ", expected " + hover);
            }
        }
    }
}
