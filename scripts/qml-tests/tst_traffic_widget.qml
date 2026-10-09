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
// where 0 B/s put it, so the bar does not shift, and the held room sits
// before each arrow, so an arrow stays beside its rate. The Stacked layout
// draws the upload line over the download line inside the item, each
// arrow beside its rate. Both stacked arrows start at the block's left
// edge, with the held room before that block.
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
                { tag: "kb-and-mb", down: 999 * 1024, up: 100 * 1048576, texts: ["999 KB/s", "100.0 MB/s"] },
                { tag: "four-digit-kb", down: 1023 * 1024, up: 1023, texts: ["1023 KB/s", "1023 B/s"] },
                { tag: "four-digit-mb", down: 1023.9 * 1048576, up: 1023 * 1024, texts: ["1023.9 MB/s", "1023 KB/s"] },
                { tag: "four-digit-two-decimals", settings: { kbDecimals: 2, mbDecimals: 2 }, down: 1023.99 * 1048576, up: 1023.99 * 1024, texts: ["1023.99 MB/s", "1023.99 KB/s"] },
                { tag: "stacked", settings: { layout: "Stacked" }, down: 123.4 * 1048576, up: 1023 * 1024, texts: ["1023 KB/s", "123.4 MB/s"] },
                { tag: "stacked-four-digit", settings: { layout: "Stacked", kbDecimals: 2, mbDecimals: 2 }, down: 1023.99 * 1048576, up: 1023.99 * 1024, texts: ["1023.99 KB/s", "1023.99 MB/s"] }
            ];
        }
        function test_a_high_rate_keeps_the_width(data) {
            widget.settings = data.settings || {};
            verify(waitForRendering(widget));
            const zero = widget.implicitWidth;
            const nextAt = first.x;
            status.values = { traffic: { down: data.down, up: data.up, interfaces: [] } };
            compare(JSON.stringify(rates().map(label => label.text)), JSON.stringify(data.texts));
            verify(waitForRendering(widget));
            compare(widget.implicitWidth, zero, "the widget keeps its width at a high rate");
            compare(first.x, nextAt, "the next widget does not move");
        }

        // The blank between an arrow's ink and its rate's ink, read on the
        // black canvas, where the accent arrow and the bar text both carry
        // red. At rates whose text starts with the same glyph, the short
        // one and the widest of its unit draw the same blank.
        function arrowGaps(img) {
            return rates().map(label => {
                const arrow = label.parent.children.find(child => child !== label && child.role === "bar");
                const a = arrow.mapToItem(canvas, 0, 0), r = label.mapToItem(canvas, 0, 0);
                const arrowInk = inkRight(img, a.x, a.x + arrow.width, a.y, a.y + arrow.height);
                let rateInk = -1;
                for (let x = Math.floor(r.x); x < Math.ceil(r.x + label.width) && rateInk < 0; x++)
                    for (let y = Math.floor(r.y); y < Math.ceil(r.y + label.height); y++)
                        if (img.red(x, y) > 64) { rateInk = x; break; }
                verify(arrowInk >= 0 && rateInk >= 0, "\"" + label.text + "\" and its arrow draw");
                return rateInk - (arrowInk + 1);
            });
        }
        function test_the_arrow_stays_beside_its_rate_data() {
            return [{ tag: "one-line", settings: {} }, { tag: "stacked", settings: { layout: "Stacked" } }];
        }
        function test_the_arrow_stays_beside_its_rate(data) {
            mouseMove(root, root.width - 1, root.height - 1);
            widget.settings = data.settings;
            status.values = { traffic: { down: 1024, up: 1024, interfaces: [] } };
            compare(JSON.stringify(rates().map(label => label.text)), JSON.stringify(["1 KB/s", "1 KB/s"]));
            verify(waitForRendering(canvas));
            const short = arrowGaps(grabImage(canvas));
            status.values = { traffic: { down: 1023 * 1024, up: 1023 * 1024, interfaces: [] } };
            compare(JSON.stringify(rates().map(label => label.text)), JSON.stringify(["1023 KB/s", "1023 KB/s"]));
            verify(waitForRendering(canvas));
            const widest = arrowGaps(grabImage(canvas));
            for (let index = 0; index < short.length; index++)
                verify(Math.abs(short[index] - widest[index]) <= 1, "the arrow keeps its blank before the rate: short " + short[index] + ", widest " + widest[index]);
        }

        // Each line: its arrow and its rate, in the order the widget draws
        // them.
        function lines() {
            const found = [];
            const walk = node => { for (const child of node.children) { if (child.role === "bar" && child.visible && (child.text === "↑" || child.text === "↓")) found.push(child); walk(child); } };
            walk(widget);
            return found.map(arrow => ({ arrow: arrow, rate: arrow.parent.children.find(child => child !== arrow && child.role === "bar") }));
        }
        function test_the_layout_setting_data() {
            return [
                { tag: "stacked", settings: { layout: "Stacked" }, arrows: ["↑", "↓"], stacked: true },
                { tag: "one-line", settings: { layout: "One line" }, arrows: ["↓", "↑"], stacked: false },
                { tag: "default", settings: {}, arrows: ["↓", "↑"], stacked: false },
                { tag: "stacked-download", settings: { layout: "Stacked", show: "download" }, arrows: ["↓"], stacked: false },
                { tag: "stacked-upload", settings: { layout: "Stacked", show: "upload" }, arrows: ["↑"], stacked: false }
            ];
        }
        function test_the_layout_setting(data) {
            widget.settings = data.settings;
            status.values = { traffic: { down: 2048, up: 1024, interfaces: [] } };
            const found = lines();
            compare(JSON.stringify(found.map(line => line.arrow.text)), JSON.stringify(data.arrows));
            const item = button();
            const size = data.stacked ? Theme.bar.stacked.size : Theme.text.bar.size;
            for (const line of found)
                for (const label of [line.arrow, line.rate]) {
                    compare(label.font.pixelSize, size, "\"" + label.text + "\" draws in its layout's size");
                    const top = label.mapToItem(item, 0, 0).y;
                    verify(top >= 0 && top + label.height <= item.height, "\"" + label.text + "\" lies inside the item: top " + top + ", height " + label.height);
                }
            if (found.length === 2) {
                const tops = found.map(line => line.arrow.mapToItem(item, 0, 0).y);
                if (data.stacked) {
                    verify(tops[1] >= tops[0] + found[0].arrow.height, "the download line is under the upload line");
                    compare(found[0].arrow.mapToItem(item, 0, 0).x, found[1].arrow.mapToItem(item, 0, 0).x, "both arrows start at one left edge");
                } else {
                    compare(tops[1], tops[0], "the two speeds draw on one line");
                }
            }
            compare(item.height, Theme.bar.item.height);
        }

        function test_stacked_arrows_share_a_column_data() {
            return [{ tag: "low", down: 2048, up: 0 },
                { tag: "high", down: 1023 * 1048576, up: 1023 * 1024 }];
        }
        function test_stacked_arrows_share_a_column(data) {
            widget.settings = { layout: "Stacked" };
            verify(waitForRendering(widget));
            const nextAt = first.x;
            status.values = { traffic: { down: data.down, up: data.up, interfaces: [] } };
            verify(waitForRendering(widget));
            const found = lines(), item = button();
            const start = found[1].arrow.mapToItem(item, 0, 0).x;
            compare(found[0].arrow.mapToItem(item, 0, 0).x, start);
            verify(start >= item.leftPadding, "the block stays inside the left padding");
            if (data.tag === "low") verify(start > item.leftPadding, "the spare width sits before the arrows");
            compare(widget.implicitWidth, 102);
            compare(first.x, nextAt, "the next widget does not move");
            for (const line of found)
                compare(line.rate.x, line.arrow.width + Theme.row.lineGap, "the rate follows its arrow");
            const shortLine = found[0].arrow.parent;
            shortLine.parent.width = found[1].arrow.parent.width;
            shortLine.anchors.right = shortLine.parent.right;
            verify(waitForRendering(widget));
            expectFail("", "a right-aligned shorter line breaks the shared arrow column");
            compare(found[0].arrow.mapToItem(item, 0, 0).x, start);
        }
    }
}
