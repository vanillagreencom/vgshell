import QtQuick
import qs.Commons
import qs.Ui
import "VpnLogic.js" as Logic

// The password prompt of one profile that reads Needs password: its name in
// the title, the retry line after a connect with a password failed, a
// masked field, and Cancel and Connect. It owns the field and hands the
// password to the service through VpnLogic.submitConnect, a direct local
// call, never IPC. The field clears on submit, on cancel and when the host
// closes it. VpnBody places it over a Scrim and owns when it shows.
// Enter in the field reaches the Dialog, which presses Connect: TextInput
// leaves Return and Enter unaccepted after its own `accepted` (Qt 6
// QQuickTextInput key handling), as vgs.network's Wi-Fi prompt relies on.
Dialog {
    id: root

    // The profile asked about, { uuid, name }, or null.
    property var target: null
    // A connect with a password failed on this profile.
    property bool retry: false
    readonly property bool ready: password.text !== ""

    // Emitted before and after the hand-off, so the host can follow the
    // connect from its first published state.
    signal submitting(string uuid)
    signal submitted(string uuid, string reply)
    signal canceled(string uuid)

    objectName: "vpn-connect-prompt"
    title: target === null ? "" : "Connect " + target.name
    initialFocus: password
    actions: [{ label: "Cancel", role: "cancel" }, { label: "Connect", role: "accept", enabled: root.ready }]
    onAccepted: submit()
    onRejected: {
        const uuid = target === null ? "" : target.uuid;
        clear();
        canceled(uuid);
    }

    function clear() { password.text = ""; }
    function submit() {
        if (target === null || !ready) return;
        const uuid = target.uuid;
        const secret = password.text;
        clear();
        submitting(uuid);
        submitted(uuid, Logic.submitConnect(uuid, secret));
    }

    Label {
        objectName: "vpn-password-retry"
        width: parent.width
        visible: root.retry
        role: "bodyStrong"
        color: Theme.color.danger
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        text: "NetworkManager could not connect with this password. Check it and try again."
    }
    Label {
        width: parent.width
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        text: "Enter the password for this VPN profile."
    }
    TextField {
        id: password
        objectName: "vpn-password"
        width: parent.width
        password: true
        placeholderText: "VPN password"
    }
}
