import QtQuick
import QtTest
import qs.Commons
import qs.Ui
import qs.Unit
import "../../shell/plugins/vgs.bluetooth"

// The Bluetooth section's pairing line keeps its room once a line shows:
// a later line that wraps to more lines, or a narrower section that wraps
// the same line, grows the slot, and its inkBelow() is the settled height
// less the tallest line's last baseline, the gap a heading below spaces
// from. An emptied line keeps both, so the timed clear moves nothing below
// it.
Item {
    id: root
    width: 300
    height: 200

    PairLine { id: slot; width: 300 }
    PairLine { id: narrowed; width: 300; y: 100 }

    TestCase {
        name: "bluetoothPairLine"
        when: windowShown

        function init() { UnitTheme.reset(); }

        function test_slot() {
            const line = slot.children[0];
            slot.text = "Pairing with Sony WH-1000XM5";
            tryVerify(() => slot.visible && slot.height > 0);
            const oneLine = slot.height;
            compare(line.lineCount, 1, "the first line is one line");
            compare(slot.inkBelow, slot.height - line.lastBaseline(), "a one-line slot answers from its baseline");

            slot.text = "Sony WH-1000XM5 did not pair. Make sure it is in pairing mode and try again.";
            tryVerify(() => line.lineCount > 1);
            verify(slot.height > oneLine, "a line that wraps to more lines grows the slot");
            compare(slot.height, line.implicitHeight, "the slot takes the wrapped line's height");
            compare(slot.inkBelow, slot.height - line.lastBaseline(), "a grown slot answers from the wrapped line's last baseline");

            const grown = [slot.height, slot.inkBelow];
            slot.text = "";
            compare([slot.visible, slot.height, slot.inkBelow], [true, grown[0], grown[1]], "an emptied line keeps its room and its ink");
        }

        function test_rewrap() {
            const line = narrowed.children[0];
            narrowed.text = "Paired with Sony WH-1000XM5";
            tryVerify(() => narrowed.visible && line.lineCount === 1);
            narrowed.width = 90;
            tryVerify(() => line.lineCount > 1);
            compare(narrowed.height, line.implicitHeight, "a rewrap grows the slot");
            compare(narrowed.inkBelow, narrowed.height - line.lastBaseline(), "a rewrapped slot answers from its last baseline");
        }
    }
}
