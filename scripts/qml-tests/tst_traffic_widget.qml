import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.traffic" as Traffic

// The Network Traffic bar widget holds its rates' widest form inside the
// item: a short rate draws right aligned, so the blank between its last
// glyph and the next widget is the item's right padding and the bar gap,
// the outer room of every bar item, and the boxes stand the bar gap
// apart, as two icon-only items do. A high rate leaves the widget's width
// where 0 B/s put it, so the bar does not shift.
Item {
    id: root
    width: 600
    height: 120
    QtObject { id: status; property var values: ({}) }

    Rectangle {
        id: canvas
        width: root.width
        height: root.height
        color: "black"

        Row {
            id: strip
            spacing: Theme.bar.gap
            Traffic.Widget { id: widget }
            BarItem { id: first; iconName: "settings"; label: "Settings"; tone: "#ff0000" }
            BarItem { id: second; iconName: "settings"; label: "Settings"; tone: "#ff0000" }
        }
        // The same rate in the same font with no held width: its own
        // blank after the last glyph, which the widget's blank must add
        // to the outer room and nothing more.
        BarItem.Reading { id: bare; y: 60; color: "#ff0000"; font.capitalization: Font.MixedCase }
    }

    TestCase {
        name: "traffic_widget"
        when: windowShown

        function scope() {
            return { status: status, settings: {},
                ipc: { call: function () { return "ok"; } },
                surfaces: { toggle: function () { return "ok"; } } };
        }
        function init() {
            UnitTheme.reset();
            status.values = { traffic: { down: 0, up: 0, interfaces: [] } };
            widget.settings = {};
            widget.shell = scope();
        }
        function button() { return widget.children.find(child => child.label === "Network Traffic"); }
        function rates() {
            const found = [];
            const walk = node => { for (const child of node.children) { if (child.role === "bar" && String(child.text).indexOf("/s") >= 0) found.push(child); walk(child); } };
            walk(widget);
            return found;
        }
        // The rightmost column holding ink between x0 and x1 in rows y0
        // to y1 of the canvas, -1 when none does.
        function inkRight(img, x0, x1, y0, y1) {
            for (let x = Math.min(img.width, Math.ceil(x1)) - 1; x >= Math.max(0, Math.floor(x0)); x--)
                for (let y = Math.max(0, Math.floor(y0)); y < Math.min(img.height, Math.ceil(y1)); y++)
                    if (img.red(x, y) > 64) return x;
            return -1;
        }

        function test_a_short_rate_keeps_the_outer_room_of_every_bar_item() {
            mouseMove(root, root.width - 1, root.height - 1);
            const shown = rates();
            compare(JSON.stringify(shown.map(label => label.text)), JSON.stringify(["0 B/s", "0 B/s"]));
            for (const label of shown) label.color = "#ff0000";
            bare.text = "0 B/s";
            verify(waitForRendering(canvas));
            const img = grabImage(canvas);
            compare(img.width, canvas.width, "the canvas grabs at one pixel a point");
            const item = button();
            const box = item.mapToItem(canvas, 0, 0);
            const next = first.mapToItem(canvas, 0, 0);
            const upload = shown[1];
            const glyphs = upload.mapToItem(canvas, 0, 0);
            const last = inkRight(img, box.x, box.x + item.width, glyphs.y, glyphs.y + upload.height);
            verify(last >= 0, "the upload rate draws");
            const own = inkRight(img, bare.x, bare.x + bare.width, bare.y, bare.y + bare.height);
            verify(own >= 0, "the bare rate draws");
            const trailing = bare.x + bare.width - (own + 1);
            const blank = next.x - (last + 1);
            // Two ink edges read to a whole pixel, and the rates centre in
            // a content box rounded up to a whole pixel, half a pixel at
            // most on each side: two pixels of slack, against the five
            // character advances a left-aligned 0 B/s leaves.
            verify(Math.abs(blank - (trailing + item.rightPadding + Theme.bar.gap)) <= 2,
                "the blank after 0 B/s is the right padding and the bar gap: blank " + blank + ", trailing " + trailing);
            compare(item.rightPadding, Theme.bar.item.paddingX);
            const boxGap = next.x - (box.x + item.width);
            compare(boxGap, second.mapToItem(canvas, 0, 0).x - (next.x + first.width), "the box gap equals the gap between two icon-only items");
            compare(boxGap, Theme.bar.gap);
        }

        function test_a_high_rate_keeps_the_width_data() {
            return [
                { tag: "mb-and-kb", down: 123.4 * 1048576, up: 1023 * 1024, texts: ["123.4 MB/s", "1023 KB/s"] },
                { tag: "kb-and-mb", down: 999 * 1024, up: 100 * 1048576, texts: ["999 KB/s", "100.0 MB/s"] }
            ];
        }
        function test_a_high_rate_keeps_the_width(data) {
            verify(waitForRendering(widget));
            const zero = widget.implicitWidth;
            const nextAt = first.x;
            status.values = { traffic: { down: data.down, up: data.up, interfaces: [] } };
            compare(JSON.stringify(rates().map(label => label.text)), JSON.stringify(data.texts));
            verify(waitForRendering(widget));
            compare(widget.implicitWidth, zero, "the widget keeps its width at a high rate");
            compare(first.x, nextAt, "the next widget does not move");
        }
    }
}
