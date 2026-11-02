import QtQuick
import QtTest
import qs.Ui
import qs.Unit

// TextShadow draws a line over the shadow it is handed: no offset, the
// handed colour, opacity and blur at the full blur its reach allows. A
// still line draws no frame, and a changed line draws one, the control
// that the frames are counted.
Item {
    id: root
    width: 320
    height: 120

    readonly property var shadow: ({ color: "#123456", opacity: 0.3, blur: 7 })

    Rectangle { anchors.fill: parent; color: "#f4f5f8" }
    Label {
        id: line
        x: 20
        y: 20
        role: "body"
        color: "#ffffff"
        text: "A still line"
        layer.enabled: true
        layer.effect: TextShadow { shadow: root.shadow }
    }

    Component {
        id: frameSpy
        SignalSpy { signalName: "frameSwapped" }
    }

    UnitCase {
        name: "textshadow"
        when: windowShown

        // The effect Qt's layer draws the line through.
        function effect() {
            const found = root.children.filter(node => node.shadowEnabled !== undefined && node.source !== null
                && node.source !== undefined && node.source.sourceItem === line);
            verify(found.length === 1, "one effect draws the line, found " + found.length);
            return found[0];
        }

        function test_the_line_draws_the_handed_shadow() {
            const drawn = effect();
            compare(drawn.shadowEnabled, true);
            compare(String(drawn.shadowColor), String(Qt.color(root.shadow.color)));
            compare(drawn.shadowOpacity, root.shadow.opacity);
            compare(drawn.blurMax, root.shadow.blur);
            compare(drawn.shadowBlur, 1);
            compare(drawn.shadowHorizontalOffset, 0);
            compare(drawn.shadowVerticalOffset, 0);
        }

        function test_a_still_line_draws_no_frame() {
            const frames = createTemporaryObject(frameSpy, root, { target: line.Window.window });
            verify(renderedFrame(root), "the window draws the line");
            frames.clear();
            wait(500);
            compare(frames.count, 0);
            line.text = "A changed line";
            tryVerify(() => frames.count > 0, 1000, "a changed line draws");
            line.text = "A still line";
        }
    }
}
