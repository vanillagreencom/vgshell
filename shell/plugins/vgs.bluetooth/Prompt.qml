import QtQuick
import qs.Commons
import qs.Ui
import "BluetoothLogic.js" as Logic

// The Bluetooth section's one dialog, over a scrim that covers the
// section: the pairing agent's open prompt (docs/architecture/
// bluetooth-agent.md § Requests), else a rename. BluetoothLogic.PROMPTS
// holds each kind's title, message, field and actions, and promptAccept
// turns the field into the answer, which goes out as `answered`; Cancel,
// Decline, OK, Escape and a click on the scrim emit `dismissed`. The Dialog
// owns Enter, and refuses an accept action its field leaves disabled.
//
// The agent lists a new copy of its prompts after every line bluetoothctl
// prints, so the dialog starts afresh only when the prompt's id or kind
// changes: a held prompt that turns into a cancel keeps its id. Each start
// clears the field and the error and gives the dialog the keyboard.
Item {
    id: root

    // The agent's entry, `{ id, kind, code, service, entered }`, or null.
    property var request: null
    // The device the prompt names, "" for "a device".
    property string deviceName: ""
    // The name a rename starts from, "" while no rename is open.
    property string renaming: ""
    // A refused answer's line under the field, cleared by the next prompt.
    property string error: ""
    readonly property int requestId: request === null ? 0 : request.id
    readonly property string kind: request !== null ? request.kind : renaming !== "" ? "rename" : ""
    readonly property bool shown: kind !== ""
    readonly property string who: kind === "rename" ? renaming : deviceName !== "" ? deviceName : "a device"
    readonly property var view: kind === "" ? null : Logic.promptView(kind, who, request, input.text)
    readonly property alias field: input

    signal answered(var value)
    signal dismissed()

    visible: shown
    implicitHeight: shown ? dialog.implicitHeight + 2 * Theme.dialog.margin : 0

    onKindChanged: reset()
    onRequestIdChanged: reset()

    // A change handler can run before the bindings that read the changed
    // property, so this reads the request and the rename
    // itself, and the focus moves a turn later, once the dialog shows.
    function reset() {
        error = "";
        input.text = request === null && renaming !== "" ? renaming : "";
        Qt.callLater(() => { if (root.shown) dialog.forceActiveFocus(Qt.OtherFocusReason); });
    }

    function accept() {
        const result = Logic.promptAccept(kind, input.text, SettingValues.utf8Bytes);
        if (result.error !== undefined) {
            error = result.error;
            return;
        }
        answered(result.answer);
    }

    Scrim {
        anchors.fill: parent
        onClicked: root.dismissed()
    }

    Dialog {
        id: dialog
        anchors.centerIn: parent
        availableHeight: root.height
        title: root.view === null ? "" : root.view.title
        message: root.view === null ? "" : root.view.message
        actions: root.view === null ? [] : root.view.actions
        initialFocus: root.view !== null && root.view.field !== "" ? input : null
        onAccepted: root.accept()
        onRejected: root.dismissed()

        TextField {
            id: input
            width: parent.width
            visible: root.view !== null && root.view.field !== ""
            error: root.error !== ""
            placeholderText: root.view === null ? "" : root.view.field
        }
        Label {
            width: parent.width
            visible: root.error !== ""
            role: "hint"
            color: Theme.color.danger
            text: root.error
            wrapMode: Text.Wrap
        }
    }
}
