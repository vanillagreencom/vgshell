import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

// inputs: shell/Ui/* shell/Commons/*
Item {
    id: root
    width: 480
    height: 160
    PathField { id: path; width: 460; placeholderText: "Choose a folder" }
    Label { id: expected; role: "item"; textFormat: Text.PlainText; y: 80 }
    TextMetrics { id: metrics; elide: Text.ElideLeft }

    TestCase {
        name: "pathfield"
        when: windowShown

        function test_unfocused_path_draws_ellipsis_and_keeps_folder_data() {
            return [{tag: "dark", light: false}, {tag: "light", light: true}];
        }

        function test_unfocused_path_draws_ellipsis_and_keeps_folder(data) {
            UnitTheme.reset();
            if (data.light) compare(UnitTheme.override({ scheme: { mode: "light" } }), "ok");
            const value = "/usr/share/a-long-parent-directory-for-the-layout-check/a-long-folder-name-for-the-layout-check";
            const editor = path.children.find(child => child.placeholderText !== undefined);
            const display = path.children.find(child => child.role === "item");
            verify(editor !== undefined && display !== undefined);
            editor.forceActiveFocus();
            editor.text = value;
            editor.textEdited();
            root.forceActiveFocus();
            tryCompare(display, "visible", true);
            compare(path.displayPath, value);
            compare(editor.text, value);
            compare(editor.color.a, 0);
            metrics.font = display.font;
            metrics.text = value;
            metrics.elideWidth = display.width;
            verify(metrics.elidedText.startsWith("…"));
            verify(metrics.elidedText.endsWith("/a-long-folder-name-for-the-layout-check"));
            expected.font = display.font;
            expected.width = display.width;
            expected.text = metrics.elidedText;
            verify(waitForRendering(display));
            verify(waitForRendering(expected));
            verify(grabImage(display).equals(grabImage(expected)), "the drawn path has an ellipsis and its last folder");
            editor.forceActiveFocus();
            tryCompare(display, "visible", false);
            compare(editor.color, Qt.color(Theme.color.text));
            compare(editor.text, value);
            keyClick(Qt.Key_End);
            keyClick("x");
            compare(editor.text, value + "x");
            compare(path.displayPath, value + "x");
        }
    }
}
