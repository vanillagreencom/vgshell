import QtQuick
import Quickshell
import Quickshell.Networking
import qs.Commons
import qs.Ui
import "NetworkLogic.js" as Logic

// Shared body for the dropdown and System pane. Only this field holds a PSK.
// The service receives the network key; NetworkManager receives the secret.
// A device's Details draws its rows once they are read: while the service
// reads, the row shows a Spinner and its content takes no height, so the
// rows under it move once.
FocusScope {
    id: root
    focus: true
    property var shell: null
    property bool expanded: false
    property string leaseId: ""
    property bool leased: false
    property string currentKey: ""
    property string promptKey: ""
    property string localProblem: ""
    property var shareTarget: null
    property string openDetails: ""
    property var readyDetails: ({})
    readonly property var values: shell === null ? ({}) : shell.status.values
    readonly property var network: values.network || ({ wifi: [], ethernet: [], state: "unavailable", action: { kind: "idle" }, prompt: null, detail: { state: "idle", rows: [] } })
    readonly property var rows: network.wifi || []
    readonly property var selected: rows.find(row => row.key === currentKey) || null
    readonly property string permissionNotice: network.access === "unavailable" ? "Network permissions could not be checked. NetworkManager still handles each change." : ""
    readonly property bool busy: network.action.kind !== "idle"
    readonly property Item initialFocus: list
    readonly property string promptName: network.prompt === null || !network.prompt ? "" : network.prompt.name
    implicitHeight: shareTarget === null ? content.implicitHeight : shareLoader.item === null ? 0 : shareLoader.item.implicitHeight

    function open() {
        if (leaseId === "") leaseId = String(root);
        if (shell !== null && !leased) {
            leased = answered(shell.ipc.call("lease", JSON.stringify({ id: leaseId, open: true }))) === "ok";
        }
        if (currentKey === "" && rows.length) currentKey = rows[0].key;
    }
    function close() {
        closeShare();
        password.text = "";
        promptKey = "";
        if (leased && shell !== null) {
            shell.ipc.call("lease", JSON.stringify({ id: leaseId, open: false }));
            leased = false;
        }
    }
    Component.onDestruction: close()
    onRowsChanged: {
        if (currentKey === "" || !rows.some(row => row.key === currentKey)) currentKey = rows.length ? rows[0].key : "";
        if (promptKey !== "" && !rows.some(row => row.key === promptKey)) cancelPassword();
        if (shareTarget !== null && !rows.some(row => row.key === shareTarget.key && row.known)) closeShare();
    }
    onNetworkChanged: {
        if (!network.wifiEnabled) closeShare();
        const detail = network.detail || {};
        if (detail.interface !== undefined && detail.interface !== "" && detail.state === "ready") {
            const rows = detail.rows || [];
            if (JSON.stringify(readyDetails[detail.interface] || []) !== JSON.stringify(rows)) {
                const kept = Object.assign({}, readyDetails);
                kept[detail.interface] = rows;
                readyDetails = kept;
            }
        }
        const next = network.prompt ? network.prompt.key : "";
        if (next === promptKey) return;
        password.text = "";
        promptKey = next;
        if (next !== "") Qt.callLater(() => password.forceActiveFocus(Qt.ShortcutFocusReason));
    }
    function answered(reply) {
        localProblem = reply === "ok" ? "" : reply === "busy" ? "A network change is still in progress." : "The network action is unavailable.";
        return reply;
    }
    function action(kind, row) {
        if (shell === null) return "unavailable";
        return answered(shell.ipc.call("action", JSON.stringify({ kind: kind, key: row ? row.key : "", interface: row ? row.interface || row.name : "" })));
    }
    function activate(row) {
        if (row === null || !network.writable || busy) return;
        action(row.connected ? "disconnect" : "connect", row);
    }
    function cancelPassword() {
        password.text = "";
        promptKey = "";
        action("cancel", null);
        list.forceActiveFocus(Qt.ShortcutFocusReason);
    }
    function submitPassword() {
        if (shell === null || password.text === "" || promptKey === "") return;
        const row = rows.find(item => item.key === promptKey);
        if (!row || !Logic.supportsPsk(row.security)) { cancelPassword(); return; }
        const device = Networking.devices.values.find(d => d.name === row.interface);
        const n = device ? device.networks.values.find(item => item.name === row.name) : null;
        if (n === null) { cancelPassword(); localProblem = "This network is no longer available."; return; }
        const secret = password.text;
        password.text = "";
        if (action("psk", row) !== "ok") return;
        promptKey = "";
        n.connectWithPsk(secret);
        list.forceActiveFocus(Qt.ShortcutFocusReason);
    }
    function showDetails(interfaceName) {
        if (shell === null) return "unavailable";
        return answered(shell.ipc.call("details", interfaceName));
    }
    function openDeviceDetails(interfaceName) {
        if (interfaceName === "") return;
        const previous = openDetails;
        openDetails = interfaceName;
        if (showDetails(interfaceName) !== "ok") openDetails = previous;
    }
    function detailRowsFor(interfaceName) {
        const detail = network.detail || {};
        if (detail.interface === interfaceName && detail.rows !== undefined && detail.rows.length > 0) return detail.rows;
        const kept = readyDetails[interfaceName];
        return kept === undefined ? [] : kept;
    }
    function detailStateFor(interfaceName) {
        const detail = network.detail || {};
        if (detail.interface === interfaceName) return detail.state;
        return detailRowsFor(interfaceName).length > 0 ? "ready" : "idle";
    }
    function share(row) {
        if (!Logic.shareable(row)) return;
        const missing = shell === null ? ["nmcli", "qrencode"] : shell.requirements.missing;
        if (missing.includes("nmcli") || missing.includes("qrencode")) {
            if (shell !== null) shell.requirements.offer(["nmcli", "qrencode"]);
            localProblem = "Wi-Fi sharing needs its installed tools. Use the installation notice to add them.";
            return;
        }
        closeShare();
        shareTarget = row;
    }
    function closeShare() {
        if (shareLoader.item !== null) shareLoader.item.clear();
        shareTarget = null;
    }

    component DeviceDetails: Disclosure {
        id: details

        required property string device
        property string label: ""
        property string stateLine: ""
        property string glyph: "network"
        readonly property bool shouldOpen: device !== "" && root.openDetails === device

        width: parent.width
        text: label
        secondary: stateLine
        iconName: glyph
        expandable: !!root.values.detailsTool && root.values.detailsTool.action === false
        Component.onCompleted: expanded = shouldOpen
        onShouldOpenChanged: expanded = shouldOpen
        trailing: [
            Spinner {
                anchors.verticalCenter: parent.verticalCenter
                visible: details.expanded && root.detailStateFor(details.device) === "loading" && root.detailRowsFor(details.device).length === 0
            }
        ]
        onExpandedChanged: {
            if (expanded) {
                if (!shouldOpen) root.openDeviceDetails(device);
            } else if (shouldOpen) {
                root.openDetails = "";
            }
        }

        Column {
            objectName: details.expanded ? "network-details" : ""
            width: parent.width
            spacing: Theme.stack.row
            readonly property var rows: root.detailRowsFor(details.device)
            readonly property string detailState: root.detailStateFor(details.device)
            Label {
                width: parent.width
                visible: parent.detailState === "failed"
                role: "hint"
                color: Theme.color.danger
                text: "Connection details could not be read."
                wrapMode: Text.Wrap
            }
            Repeater {
                model: parent.detailState === "failed" ? [] : parent.rows
                Field {
                    id: deviceDetailRow
                    required property var modelData
                    width: parent.width
                    inline: true
                    label: modelData.key
                    Label {
                        text: deviceDetailRow.modelData.value
                        role: "value"
                        width: parent.width
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    Loader {
        id: shareLoader
        objectName: "network-share-owner"
        width: root.width
        active: root.shareTarget !== null
        sourceComponent: NetworkShare {
            width: root.width
            target: root.shareTarget
            onDismissed: { root.closeShare(); list.forceActiveFocus(Qt.ShortcutFocusReason); }
        }
    }

    Column {
        id: content
        width: root.width
        visible: root.shareTarget === null
        spacing: Theme.stack.group
        Label {
            width: parent.width
            role: "body"
            text: root.network.text || Logic.stateText("unavailable")
            wrapMode: Text.Wrap
        }
        Label {
            width: parent.width
            visible: text !== ""
            role: "hint"
            color: Theme.color.danger
            text: root.localProblem || root.network.problem || ""
            wrapMode: Text.Wrap
        }
        Label {
            objectName: "network-permission-notice"
            width: parent.width
            role: "hint"
            visible: text !== ""
            text: root.permissionNotice
            wrapMode: Text.Wrap
        }
        Field {
            width: parent.width
            visible: root.expanded && !!root.network.hasWifi
            label: "Wi-Fi"
            hint: root.network.wifiHardwareEnabled === false ? "The hardware switch blocks Wi-Fi." : ""
            control: Switch {
                objectName: "network-radio"
                checked: !!root.network.wifiEnabled
                enabled: !!root.network.writable && root.network.wifiHardwareEnabled !== false
                onClicked: root.action("radio", null)
            }
        }
        Label {
            width: parent.width
            visible: !root.expanded && !!root.network.hasWifi && root.network.wifiHardwareEnabled === false
            role: "hint"
            text: "The hardware switch blocks Wi-Fi."
            wrapMode: Text.Wrap
        }
        Section {
            title: "Wi-Fi networks"
            visible: !!root.network.hasWifi && !!root.network.wifiEnabled
            width: parent.width
            description: root.rows.length ? "" : "No networks found."
            // focus-indicator: the one ListCursor marks the selected network
            FocusScope {
                id: list
                width: parent.width
                implicitHeight: wifiList.implicitHeight
                activeFocusOnTab: visible && root.rows.length > 0
                focus: true
                Keys.onPressed: event => { event.accepted = navigation.handle(event); }
                ListCursor { id: networkCursor; shown: root.rows.length > 0 }
                KeyNav {
                    id: navigation
                    count: root.rows.length
                    currentIndex: root.rows.findIndex(row => row.key === root.currentKey)
                    cursor: networkCursor
                    labelAt: index => root.rows[index].name
                    onMoved: index => root.currentKey = root.rows[index].key
                    onActivated: index => root.activate(root.rows[index])
                    onRemoved: index => { if (root.rows[index].known) root.action("forget", root.rows[index]); }
                    onMenuRequested: index => wifiRepeater.itemAt(index).openMenu()
                }
                Column {
                    id: wifiList
                    width: list.width
                    Repeater {
                        id: wifiRepeater
                        model: ScriptModel { values: root.rows; objectProp: "key" }
                        DeviceRow {
                            id: wifiRow
                            required property var modelData
                            width: wifiList.width
                            text: modelData.name === "" ? "Hidden network" : modelData.name
                            iconName: modelData.connected ? "wifi" : "wifi-low"
                            secondary: modelData.changing ? "Connecting…" : (modelData.connected ? "Connected · " : modelData.known ? "Saved · " : "") + Logic.securityLabel(modelData.security)
                            badge: modelData.strength + "%"
                            cursor: networkCursor
                            highlighted: root.currentKey === modelData.key
                            focusPolicy: Qt.NoFocus
                            enabled: !!root.network.writable && !root.busy
                            onPointed: root.currentKey = modelData.key
                            onClicked: { root.currentKey = modelData.key; root.activate(modelData); }
                            menuEntries: [
                                MenuItem { text: "Forget"; iconName: "trash"; enabled: wifiRow.modelData.known; onTriggered: root.action("forget", wifiRow.modelData) },
                                MenuItem { text: "Details"; iconName: "info"; enabled: !!root.values.detailsTool && root.values.detailsTool.action === false; onTriggered: { root.openDeviceDetails(wifiRow.modelData.interface); } },
                                MenuItem { text: "Share QR code"; iconName: "qr-code"; enabled: Logic.shareable(wifiRow.modelData); onTriggered: root.share(wifiRow.modelData) }
                            ]
                        }
                    }
                }
            }
        }
        Column {
            width: parent.width
            spacing: Theme.stack.row
            visible: root.promptKey !== ""
            Label { role: "hint"; text: "Password for " + root.promptName }
            TextField {
                id: password
                objectName: "network-password"
                width: parent.width
                password: true
                placeholderText: "Wi-Fi password"
                onAccepted: root.submitPassword()
                Keys.onEscapePressed: event => { root.cancelPassword(); event.accepted = true; }
            }
            Row {
                spacing: Theme.control.gap
                Button { text: "Join"; enabled: password.text !== ""; onClicked: root.submitPassword() }
                Button { text: "Cancel"; variant: "secondary"; onClicked: root.cancelPassword() }
            }
        }
        Section {
            width: parent.width
            visible: !!root.network.hasWifi && (root.expanded || root.openDetails === root.network.wifiInterface)
            title: "Wi-Fi options"
            DeviceDetails {
                device: root.network.wifiInterface
                label: "Wi-Fi device"
                stateLine: root.network.wifiInterface
                glyph: "wifi"
                visible: root.network.wifiInterface !== ""
            }
            Field {
                width: parent.width
                visible: root.expanded
                label: "Auto-join"
                hint: "Allow this Wi-Fi device to join saved networks automatically."
                control: Switch {
                    objectName: "network-autojoin"
                    checked: !!root.network.wifiAutoconnect
                    enabled: !!root.network.writable
                    onClicked: { root.action("autoconnect", { interface: root.network.wifiInterface }); }
                }
            }
            Row {
                visible: root.expanded
                spacing: Theme.control.gap
                Button { text: "Forget"; variant: "secondary"; enabled: root.selected !== null && root.selected.known && !root.busy; onClicked: root.action("forget", root.selected) }
                Button { text: "Share QR code"; variant: "secondary"; enabled: Logic.shareable(root.selected); onClicked: root.share(root.selected) }
            }
        }
        Section {
            width: parent.width
            title: "Ethernet"
            description: (root.network.ethernet || []).length ? "" : "No Ethernet device detected."
            Repeater {
                model: ScriptModel { values: root.network.ethernet || []; objectProp: "name" }
                DeviceDetails {
                    required property var modelData
                    device: modelData.name
                    label: modelData.name
                    stateLine: Logic.ethernetText(modelData.state)
                    glyph: "ethernet-port"
                }
            }
            Button {
                visible: root.expanded && !!root.values.detailsTool && root.values.detailsTool.action === true
                text: "Install details tool"
                variant: "secondary"
                onClicked: root.answered(root.shell.status.act("detailsTool"))
            }
        }
        Section {
            width: parent.width
            visible: root.expanded
            title: "Bar"
            Field {
                width: parent.width
                label: "Show disconnected icon"
                control: Switch {
                    checked: root.shell === null || root.shell.settings.showDisconnected
                    onClicked: root.answered(root.shell.configure.set("showDisconnected", checked))
                }
            }
        }
    }
}
