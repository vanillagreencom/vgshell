import QtQuick
import qs.Commons
import qs.Ui

// The bar a page shows while it holds an unsaved edit: the line "Unsaved
// changes" with Discard and Save at its end, `saveBar.gap` apart. `dirty`
// says the page holds an edit. Save emits `save()` and Discard `discard()`;
// the bar writes and restores nothing itself. Once the caller's write is
// accepted it calls `confirm()`, and the line then reads "Saved" in
// `saveBar.saved` for `saveBar.duration` milliseconds, with no action
// beside it; an edit that begins in that time shows the line and the
// actions again at once. The bar shows while `dirty` or the Saved line
// holds, fades on `motion.duration.normal`, and is no taller than zero
// while hidden, so a `Pane` footer that holds it takes no room then. The
// caller sets the width. The actions take the keyboard by Tab and not by a
// press, so a click on Save leaves the cursor in the field it saves; the
// bar is one focus scope, so a caller reads `activeFocus` to move the
// keyboard on before the bar leaves.
FocusScope {
    id: root

    property bool dirty: false
    // Whether the line reads Saved: from `confirm()` until an edit begins,
    // so it still reads Saved while the bar fades.
    readonly property alias saved: held.saved
    readonly property bool shown: dirty || dwell.running
    // Whether the bar still draws: it fades after `shown` turns false.
    readonly property bool drawn: opacity > 0
    signal save()
    signal discard()

    function confirm() {
        if (dirty) return;
        held.saved = true;
        dwell.restart();
    }

    onDirtyChanged: {
        if (!dirty) return;
        held.saved = false;
        dwell.stop();
    }

    implicitWidth: line.implicitWidth + Theme.saveBar.gap + actions.implicitWidth
    implicitHeight: drawn ? Math.max(line.implicitHeight, actions.implicitHeight) : 0
    visible: drawn
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.motion.duration.normal; easing.type: Theme.motion.easing.standard } }

    QtObject {
        id: held
        property bool saved: false
        // How each action takes the keyboard.
        readonly property int actionFocus: Qt.TabFocus
    }

    Timer {
        id: dwell
        interval: Theme.saveBar.duration
    }

    Row {
        id: line
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.control.gap

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.saved
            name: "check"
            size: Theme.icon.size.md
            color: Theme.saveBar.saved
        }
        Label {
            anchors.verticalCenter: parent.verticalCenter
            role: "item"
            text: root.saved ? "Saved" : "Unsaved changes"
            color: root.saved ? Theme.saveBar.saved : Theme.color.textMuted
        }
    }

    Row {
        id: actions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.saveBar.gap
        visible: !root.saved

        Button {
            text: "Discard"
            variant: "tertiary"
            enabled: root.dirty
            focusPolicy: held.actionFocus
            onClicked: root.discard()
        }
        Button {
            text: "Save"
            variant: "primary"
            enabled: root.dirty
            focusPolicy: held.actionFocus
            onClicked: root.save()
        }
    }
}
