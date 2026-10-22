import QtQuick
import qs.Ui
import "UpdatesLogic.js" as Logic

// A core-hosted panel over the Updates page. The shared Dialog owns its
// keys; initial focus stays on its body, away from the system action.
Item {
    id: root
    property var shell: null
    property Item initialFocus: bodyFocus
    property string problem: ""
    implicitWidth: dialog.implicitWidth
    implicitHeight: dialog.implicitHeight

    function open(payloadJson) { problem = ""; }
    function close() {}
    function answer(useVgs) {
        if (useVgs && !Logic.rebootNoticeRequested("vgsOnly", shell.status.values.rebootNotice)) {
            shell.surfaces.hide("panel");
            return;
        }
        const stored = shell.configure.set("rebootNoticeAnswered", true);
        if (stored !== "ok") {
            problem = "Your choice could not be saved. Try again.";
            return;
        }
        if (useVgs) {
            const reply = shell.status.act("rebootNotice");
            if (reply !== "ok") {
                problem = "The setup terminal could not open. Try again.";
                return;
            }
        }
        shell.surfaces.hide("panel");
    }

    Dialog {
        id: dialog
        width: root.width
        title: "Choose your restart notices"
        message: "VGS asks once after all update steps when a restart is needed. Use VGS only to avoid a second CachyOS prompt. The setup terminal shows the change and asks you to confirm."
        initialFocus: bodyFocus
        actions: [{ label: "Use VGS only (recommended)", role: "accept" }, { label: "Keep CachyOS notices", role: "discard" }]
        onAccepted: root.answer(true)
        onDiscarded: root.answer(false)
        onRejected: root.shell.surfaces.hide("panel")

        // focus-indicator: body focus takes no action; Tab shows the shared buttons' rings
        Item { id: bodyFocus }
        Label { text: root.problem; visible: text !== ""; role: "hint" }
    }
}
