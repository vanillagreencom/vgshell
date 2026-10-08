import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// The actual title block and its next item share one gap. The nested
// surfaces row checks the same Dialog inside the real ModalDialog host.
Item {
    id: root
    width: 600
    height: 600

    Label { id: bodyLine; role: "body"; text: "Body line" }

    TestCase {
        name: "TitleSpace"
        when: windowShown

        function cleanup() { UnitTheme.reset(); }

        function titleBlock(pane) { return pane.children[0]; }
        function headerSlot(pane) { return pane.children[2]; }
        function itemTop(item, pane) { return item.mapToItem(pane, 0, 0).y; }

        function test_pane_title_block_gap_data() {
            return [
                { tag: "header", variant: "header" },
                { tag: "description", variant: "description" },
                { tag: "bare body", variant: "body" },
                { tag: "custom title", variant: "custom" },
                { tag: "theme title space", variant: "description", titleSpace: 32 }
            ];
        }

        function test_pane_title_block_gap(data) {
            if (data.titleSpace)
                compare(UnitTheme.override({ stack: { titleSpace: data.titleSpace } }), "ok");
            const title = data.variant === "custom"
                ? 'titleContent: [ Label { text: "Custom title"; role: "h3" } ]'
                : 'title: "Title"';
            const description = data.variant === "description"
                ? 'subtitle: [ Label { text: "Description"; role: "body"; width: parent.width } ]' : "";
            const header = data.variant === "header"
                ? 'header: [ Label { text: "Header"; role: "body"; width: parent.width } ]' : "";
            const made = Qt.createQmlObject('import QtQuick\nimport qs.Ui\nPane { width: 300; fitToContent: true; '
                + [title, description, header].filter(part => part !== "").join("\n")
                + '\nItem { objectName: "bodyMarker"; width: parent.width; height: 20 } }', root);
            verify(made instanceof Pane);
            const marker = findChild(made, "bodyMarker");
            verify(marker instanceof Item);
            waitForRendering(made);
            verify(Theme.stack.titleSpace >= bodyLine.lineBox, "the title space contains a drawn body line");
            const block = titleBlock(made);
            const next = data.variant === "header" ? headerSlot(made) : marker;
            compare(itemTop(next, made) - (itemTop(block, made) + block.height), Theme.stack.titleSpace);
            if (data.variant === "description") {
                const subtitle = block.children[4];
                compare(subtitle.y - made.titleRowHeight, Theme.row.lineGap);
                verify(subtitle.implicitHeight > 0);
                compare(block.height, made.titleRowHeight + Theme.row.lineGap + subtitle.implicitHeight);
            }
            made.destroy();
        }

        function test_dialog_title_block_gap_data() {
            return [
                { tag: "description", message: "Description", body: true },
                { tag: "bare body", message: "", body: true },
                { tag: "actions", message: "Description", body: false },
                { tag: "theme title space", message: "Description", body: true, titleSpace: 32 }
            ];
        }

        function test_dialog_title_block_gap(data) {
            if (data.titleSpace)
                compare(UnitTheme.override({ stack: { titleSpace: data.titleSpace } }), "ok");
            const body = data.body ? 'Item { objectName: "bodyMarker"; width: parent.width; height: 20 }' : "";
            const made = Qt.createQmlObject('import QtQuick\nimport qs.Ui\nDialog { title: "Title"; message: '
                + JSON.stringify(data.message) + '; actions: [{ label: "Close", role: "cancel" }]; ' + body + ' }', root);
            verify(made instanceof Dialog);
            const pane = made.children.find(child => child instanceof Pane);
            verify(pane instanceof Pane);
            waitForRendering(made);
            verify(Theme.stack.titleSpace >= bodyLine.lineBox, "the title space contains a drawn body line");
            const next = data.body ? findChild(made, "bodyMarker") : pane.children[4];
            const block = titleBlock(pane);
            compare(itemTop(next, pane) - (itemTop(block, pane) + block.height), Theme.stack.titleSpace);
            compare(block.children[4].implicitHeight > 0, data.message !== "");
            made.destroy();
        }
    }
}
