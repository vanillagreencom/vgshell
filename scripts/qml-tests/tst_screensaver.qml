import QtQuick
import QtTest
import qs.Commons
import "../../shell/plugins/vgs.screensaver/ScreensaverLogic.js" as Logic

Item {
    id: scene
    width: 1200
    height: 120
    readonly property color background: Theme.screensaver.background
    readonly property color gradientStart: Theme.screensaver.gradientStart
    readonly property color gradientEnd: Theme.screensaver.gradientEnd
    Text {
        id: rendered
        width: scene.width
        height: 50
        color: "white"
        font.family: Theme.font.family.mono
        font.pixelSize: Theme.text.display.size
        font.weight: Theme.text.body.weight
        textFormat: Text.StyledText
    }
    Text {
        id: reference
        y: 60
        width: scene.width
        height: 50
        color: rendered.color
        font: rendered.font
        textFormat: Text.PlainText
    }
    TestCase {
        name: "screensaver"
        when: windowShown

        function firstInk(item) {
            const image = grabImage(item);
            for (let x = 0; x < image.width; x++)
                for (let y = 0; y < image.height; y++)
                    if (image.red(x, y) > 128) return x;
            fail("the art line contains no drawn character");
            return -1;
        }

        function test_columns_match_the_text_file() {
            const file = new XMLHttpRequest();
            file.open("GET", Qt.resolvedUrl("../../shell/plugins/vgs.screensaver/logo.txt"), false);
            file.send();
            verify(file.responseText.length > 0, "the production art file is readable");
            const sources = [file.responseText, "    A   B\n ╚   █\n  C  D\n"];
            for (const source of sources) {
                const lines = source.split("\n").filter(line => line !== "");
                const parsed = Logic.parseFrame(lines.join("\n")).rows;
                for (let i = 0; i < lines.length; i++) {
                    rendered.text = parsed[i];
                    reference.text = lines[i];
                    rendered.forceLayout();
                    reference.forceLayout();
                    verify(waitForRendering(rendered), "the parsed line renders");
                    compare(firstInk(rendered), firstInk(reference), "first character column of line " + i);
                    fuzzyCompare(rendered.advance.width, reference.advance.width, 0.01, "line " + i + " keeps every text column");
                }
            }
        }

        function test_terminal_background_uses_the_drawn_color() {
            const command = Logic.command("/art", "print", 30, 80, 24, scene.background);
            compare(command[command.indexOf("--terminal-background-color") + 1], "#000000");
        }

        function test_gradient_arguments_use_native_theme_colors() {
            const command = Logic.command("/art", "colorshift", 30, 80, 24, scene.background, scene.gradientStart, scene.gradientEnd);
            const expected = [String(scene.gradientStart).slice(1), String(scene.gradientEnd).slice(1)];
            for (const option of ["--gradient-stops", "--final-gradient-stops"]) {
                const at = command.indexOf(option);
                verify(at > 0);
                compare(command.slice(at + 1, at + 3), expected);
                verify(/^[0-9a-f]{6}$/.test(command[at + 1]));
            }
        }
    }
}
