import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "NetworkLogic.js" as Logic

// The service owns the helper through cancellation and profile cleanup.
// This form hands it a one-use stdin closure through a direct local call.
FocusScope {
    id: root
    objectName: "network-join-form"
    property var shell: null
    property string interfaceName: ""
    property var target: null
    property string owner: String(root)
    property bool pending: false
    property var result: ({ kind: "idle" })
    readonly property bool enterprise: security.currentIndex === 1
    readonly property bool canSubmit: !pending && ssid.text !== "" && password.text !== "" && (!enterprise || (identity.text !== "" && domain.text !== ""))
    readonly property Item initialFocus: target === null ? ssid : identity
    signal dismissed()
    implicitHeight: content.implicitHeight
    Keys.onEscapePressed: event => { root.dismissed(); event.accepted = true; }

    function finish(value) {
        if (!pending) return;
        pending = false;
        result = value;
        if (value.kind === "ok") dismissed();
    }
    function clear() {
        password.text = "";
        Logic.closeJoin(owner);
        pending = false;
    }
    Component.onDestruction: clear()
    Component.onCompleted: Qt.callLater(() => initialFocus.forceActiveFocus(Qt.ShortcutFocusReason))

    function submit() {
        if (!canSubmit || shell === null) return;
        const secret = password.text;
        password.text = "";
        pending = true;
        result = { kind: "joining" };
        const reply = Logic.submitJoin({ owner: owner, interface: interfaceName, name: ssid.text,
            hidden: target === null ? "yes" : "no", method: enterprise ? (method.currentIndex === 0 ? "peap" : "ttls") : "psk",
            identity: identity.text, domain: domain.text },
            helper => { helper.write(secret); helper.stdinEnabled = false; }, root.finish);
        if (reply !== "ok") { pending = false; result = { kind: reply === "busy" ? "busy" : "refused" }; }
    }
    Column {
        id: content
        width: root.width
        spacing: Theme.stack.group
        Label { width: parent.width; role: "bodyStrong"; text: root.target === null ? "Other Network" : "Join " + root.target.name; wrapMode: Text.Wrap }
        Label {
            width: parent.width
            role: "hint"
            visible: text !== ""
            text: root.result.cleanup === "failed" ? "The connection failed. Its new network profile could not be removed."
                : root.result.kind === "refused" ? "NetworkManager denied access to this network change."
                : root.result.kind === "busy" ? "A network change is still in progress."
                : ["failed", "timeout", "start-failed", "invalid"].includes(root.result.kind) ? "The network could not connect. Check the network settings and try again."
                : root.result.kind === "joining" ? "Connecting…" : ""
            wrapMode: Text.Wrap
        }
        Field {
            width: parent.width
            label: "Network name"
            TextField { id: ssid; objectName: "network-join-ssid"; width: parent.width; text: root.target === null ? "" : root.target.name; enabled: !root.pending && root.target === null; placeholderText: "Network name" }
        }
        Field {
            width: parent.width
            label: "Security"
            Select { id: security; objectName: "network-join-security"; width: parent.width; model: ["WPA/WPA2 Personal", "WPA Enterprise"]; currentIndex: root.target === null ? 0 : 1; enabled: !root.pending && root.target === null; onActivated: password.text = "" }
        }
        Field {
            width: parent.width
            visible: root.enterprise
            label: "Method"
            Select { id: method; objectName: "network-join-method"; width: parent.width; model: ["PEAP / MSCHAPv2", "TTLS / PAP"]; enabled: !root.pending }
        }
        Field {
            width: parent.width
            visible: root.enterprise
            label: "User name"
            TextField { id: identity; objectName: "network-join-identity"; width: parent.width; enabled: !root.pending; placeholderText: "Network user name" }
        }
        Field {
            width: parent.width
            visible: root.enterprise
            label: "Server domain"
            hint: "Use the authentication server domain supplied by your network administrator."
            TextField { id: domain; objectName: "network-join-domain"; width: parent.width; enabled: !root.pending; placeholderText: "auth.example.com" }
        }
        Field {
            width: parent.width
            label: "Password"
            TextField { id: password; objectName: "network-join-password"; width: parent.width; password: true; enabled: !root.pending; placeholderText: "Network password"; onAccepted: root.submit() }
        }
        Row {
            spacing: Theme.control.gap
            Button { text: "Join"; enabled: root.canSubmit; onClicked: root.submit() }
            Button { text: "Cancel"; variant: "secondary"; onClicked: root.dismissed() }
        }
    }
}
