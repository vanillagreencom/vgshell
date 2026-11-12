import QtQuick
import qs.Commons
import qs.Ui

// The section's pairing line, in a slot that stays once a line shows
// until the section is left, at the height of its tallest line, so the
// timed clear empties the text and moves no control below it. A heading
// below spaces itself from Theme.inkBelow of the item above
// (SectionHeader); `inkBelow` answers with the gap under that tallest
// line's last baseline, so neither an empty line nor another line's
// glyphs move the heading.
Item {
    id: root

    property string text: ""
    property bool failed: false
    property real slot: 0
    property real baselineGap: 0

    height: slot
    visible: slot > 0

    readonly property real inkBelow: baselineGap

    // QQuickText emits implicitHeightChanged while it lays out new text,
    // before lineCount, the baseline and contentHeight follow, and emits
    // textChanged once the layout is done; a rewrap from a width change
    // emits contentHeightChanged and no textChanged (qtdeclarative
    // qquicktext.cpp, setText and updateSize; held by
    // scripts/qml-tests/tst_bluetooth_pair_line.qml). A reading at the
    // slot's own height is taken again, so a settled reading replaces one
    // taken earlier.
    function hold() {
        if (line.text === "" || line.implicitHeight < slot) return;
        slot = line.implicitHeight;
        baselineGap = slot - line.lastBaseline();
    }

    Label {
        id: line
        width: parent.width
        role: "body"
        text: root.text
        color: root.failed ? Theme.color.danger : Theme.color.text
        wrapMode: Text.Wrap
        onTextChanged: root.hold()
        onContentHeightChanged: root.hold()
    }
}
