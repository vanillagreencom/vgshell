import QtQuick
import qs.Ui
import "UpdatesLogic.js" as Logic

// A core-hosted choice before an update or over Settings. Dialog owns its
// keys; initial focus stays on its body, away from the system action.
Item {
    id: root
    property var shell: null
    property Item initialFocus: bodyFocus
    property string problem: ""
    property bool answered: false
    implicitWidth: dialog.implicitWidth
    implicitHeight: dialog.implicitHeight

    function open(payloadJson) { problem = ""; answered = false; }
    // The host asks holdsHide before closing (plugin API); a refused
    // dismissal launch keeps its question and feedback visible.
    function holdsHide() {
        if (answered) return false;
        const reply = shell.ipc.call("reboot-notice-answer", "");
        problem = Logic.replyLine(reply);
        answered = reply === "ok";
        return !answered;
    }
    // Native dismissal reaches close without holdsHide (SummonHost.drop).
    // The local latch also covers a hide that already started the run.
    function close() {
        if (answered) return;
        answered = true;
        shell.ipc.call("reboot-notice-dismissed", "");
    }
    function answer(useVgs) {
        const reply = shell.ipc.call("reboot-notice-answer", useVgs ? "vgsOnly" : "both");
        if (reply !== "ok") {
            problem = Logic.replyLine(reply);
            return;
        }
        answered = true;
        shell.surfaces.hide("panel");
    }

    Dialog {
        id: dialog
        width: root.width
        title: "Choose your restart notices"
        message: "VGS asks you to restart only when an update needs it."
        initialFocus: bodyFocus
        actions: [{ label: "Use VGS only (recommended)", role: "accept" }, { label: "Keep CachyOS notices", role: "discard" }]
        onAccepted: root.answer(true)
        onDiscarded: root.answer(false)
        onRejected: root.shell.surfaces.hide("panel")

        // focus-indicator: body focus takes no action; Tab shows the shared buttons' rings
        Item { id: bodyFocus }
        Label { width: parent.width; text: root.problem; visible: text !== ""; role: "hint"; wrapMode: Text.Wrap }
    }
}
