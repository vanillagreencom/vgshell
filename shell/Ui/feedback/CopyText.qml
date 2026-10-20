import QtQuick
import qs.Commons

// The one clipboard writer of qs.Ui: `copy(text)` puts TEXT on the
// clipboard, and `confirming` holds true for `codeLine.confirm`
// milliseconds after it, so the control that asked can read Copied or
// draw a check mark for that long. It draws nothing and takes no input;
// the caller places the control that calls it. The clipboard is the
// application's, reached through a hidden text edit's copy, so the
// component imports no Quickshell module. It logs nothing it copies.
Item {
    id: root

    readonly property bool confirming: confirm.running

    function copy(text) {
        clipboard.text = text;
        clipboard.selectAll();
        clipboard.copy();
        clipboard.deselect();
        clipboard.text = "";
        confirm.restart();
    }

    TextEdit {
        id: clipboard
        visible: false
        readOnly: true
    }

    Timer {
        id: confirm
        interval: Theme.codeLine.confirm
    }
}
