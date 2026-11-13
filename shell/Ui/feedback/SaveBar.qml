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
// actions again at once. The confirmation fades on `motion.duration.normal`,
// but keeps its footer space until the page leaves, so expiry cannot move
// a control away from a pointer. `contextKey` identifies a section when the
// same page instance is reused. A page never edited takes no footer room. The
// caller sets the width. The actions take the keyboard by Tab and not by a
// press, so a click on Save leaves the cursor in the field it saves; the
// bar is one focus scope, so a caller reads `activeFocus` to move the
// keyboard on before the bar leaves.
FocusScope {
    id: root

    property bool dirty: false
    property string contextKey: ""
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
        held.room = true;
        held.saved = true;
        dwell.restart();
    }

    function release() {
        dwell.running = false;
        held.room = false;
    }

    onContextKeyChanged: release()
    // Item visibility follows hidden ancestors, so leaving a page releases its room.
    // https://doc.qt.io/qt-6/qml-qtquick-item.html#visible-prop
    onVisibleChanged: {
        if (!visible) release();
        else if (dirty) held.room = true;
    }

    onDirtyChanged: {
        if (!dirty) return;
        held.room = true;
        held.saved = false;
        dwell.stop();
    }

    implicitWidth: line.implicitWidth + Theme.saveBar.gap + actions.implicitWidth
    implicitHeight: dirty || held.room ? Math.max(line.implicitHeight, actions.implicitHeight) : 0
    visible: dirty || held.room
    // Opacity alone does not stop input or release active focus.
    // https://doc.qt.io/qt-6/qml-qtquick-item.html#opacity-prop
    enabled: drawn
    opacity: shown ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: Theme.motion.duration.normal; easing.type: Theme.motion.easing.standard } }

    QtObject {
        id: held
        property bool saved: false
        property bool room: false
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
            y: Math.round(savedText.y) + savedText.topForLeadingIcon(height)
            visible: root.saved
            name: "check"
            size: Theme.icon.size.md
            color: Theme.saveBar.saved
        }
        Label {
            id: savedText
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
