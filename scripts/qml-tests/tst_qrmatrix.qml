import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit

Item {
    width: 400
    height: 300
    QrMatrix { id: matrix; matrixData: "100\n011\n101\n"; width: 101; height: 80 }
    TestCase {
        name: "qrmatrix"
        when: windowShown
        function init() { UnitTheme.reset(); matrix.matrixData = "100\n011\n101\n"; matrix.width = 101; matrix.height = 80; }
        function modules() { return matrix.children[0].children[0].children.filter(c => c.index !== undefined); }
        function test_binary_square_and_bound() {
            for (const data of ["", "100\n10\n101\n", "100\n0x1\n101\n", Array(186).fill("0".repeat(186)).join("\n")]) {
                matrix.matrixData = data;
                compare(matrix.side, 0);
                compare(modules().length, 0);
            }
        }
        function test_integer_modules_fit_and_centre() {
            compare(matrix.side, 3);
            compare(matrix.moduleSize, 26);
            compare(matrix.drawnSize, 78);
            const canvas = matrix.children[0];
            compare(canvas.width, 78);
            compare(canvas.height, 78);
            compare(canvas.x, 12);
            compare(canvas.y, 1);
            for (const module of modules()) compare([module.width, module.height], [26, 26]);
            matrix.width = 2;
            compare(matrix.moduleSize, 0);
            verify(!canvas.visible);
        }
        function test_row_major_modules_take_their_colours() {
            verify(Qt.colorEqual(Theme.qrMatrix.foreground, "#000000"));
            verify(Qt.colorEqual(Theme.qrMatrix.background, "#ffffff"));
            const colors = [true, false, false, false, true, true, true, false, true];
            compare(modules().length, 9);
            for (let i = 0; i < colors.length; i++) verify(Qt.colorEqual(modules()[i].color, colors[i] ? Theme.qrMatrix.foreground : Theme.qrMatrix.background));
            verify(Qt.colorEqual(matrix.children[0].color, Theme.qrMatrix.background));
        }
        function test_theme_changes_without_rebuild() {
            compare(UnitTheme.override({ qrMatrix: { size: 200, foreground: "#111111", background: "#eeeeee" } }), "ok");
            compare(matrix.implicitWidth, 200);
            verify(Qt.colorEqual(modules()[0].color, "#111111"));
            verify(Qt.colorEqual(modules()[1].color, "#eeeeee"));
            verify(Qt.colorEqual(matrix.children[0].color, "#eeeeee"));
        }
    }
}
