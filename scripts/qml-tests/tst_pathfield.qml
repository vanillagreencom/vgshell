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
    Rectangle {
        x: expected.x; y: expected.y
        width: expected.width; height: expected.height
        color: Theme.textField.background
    }
    Label { id: expected; role: "item"; textFormat: Text.PlainText; y: 80 }
    TextMetrics { id: metrics; elide: Text.ElideLeft }

    TestCase {
        name: "pathfield"
        when: windowShown

        function descendants(item) {
            const out = [];
            const stack = [item];
            while (stack.length > 0) {
                const at = stack.pop();
                out.push(at);
                for (const child of at.children) stack.push(child);
            }
            return out;
        }
        function titleOf(row) { return descendants(row.contentItem).find(child => child.role === "item" && child.text === row.text); }

        function test_the_keyboards_folder_row_holds_the_plate_and_opens_on_enter() {
            UnitTheme.reset();
            compare(UnitTheme.override({ motion: { scale: 0 } }), "ok");
            path.openFolder("/usr");
            const picker = path.children.find(child => child.toggle !== undefined && child.opened !== undefined);
            picker.open();
            const window = picker.resources.find(child => child.anchor !== undefined);
            const list = descendants(window.contentItem).find(child => child.itemAtIndex !== undefined);
            const home = descendants(window.contentItem).find(child => child.text === "Home");
            // The stand-in model lists no rows to a view, so the view takes
            // its row count; each row reads its folder from the model, as
            // on the shell.
            const folders = list.model;
            folders.setFiles(["/usr/bin", "/usr/lib", "/usr/share"], "drop");
            list.model = folders.count;
            tryVerify(() => list.itemAtIndex(2) !== null, 1000, "the list builds its rows");
            const plate = descendants(list.contentItem).find(child => child.follow !== undefined && child.placed !== undefined);
            window.requestActivate();
            list.forceActiveFocus();
            tryCompare(list, "activeFocus", true);
            wait(0);
            keyClick(Qt.Key_Down);
            keyClick(Qt.Key_Down);
            const row = list.itemAtIndex(2);
            compare(list.currentIndex, 2);
            verify(plate.placed === row, "the plate sits on the keyboard's row");
            compare(plate.opacity, 1);
            compare(String(titleOf(row).color), String(Qt.color(Theme.listItem.selectedForeground)), "the keyboard's row takes the accent");
            compare(String(titleOf(list.itemAtIndex(0)).color), String(Qt.color(Theme.color.text)), "another row keeps its resting text");
            mouseMove(list.itemAtIndex(0), 20, 5);
            mouseMove(list.itemAtIndex(0), 21, 5);
            verify(plate.placed === list.itemAtIndex(0), "a moved pointer takes the plate");
            compare(list.currentIndex, 2, "the pointer moves no keyboard row");
            mouseMove(home, 5, 5);
            verify(plate.placed === row, "the plate goes back to the keyboard's row when the pointer leaves");
            keyClick(Qt.Key_Return);
            compare(path.currentFolder, "/usr/share");
            picker.close();
            root.Window.window.requestActivate();
            tryCompare(root.Window, "active", true);
            UnitTheme.reset();
        }

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
            const position = display.mapToItem(root, 0, 0);
            expected.x = position.x - Math.floor(position.x);
            expected.y = 80 + position.y - Math.floor(position.y);
            tryVerify(() => grabImage(display).equals(grabImage(expected)), 5000,
                      "the drawn path has an ellipsis and its last folder");
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
