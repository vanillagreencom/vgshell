import QtQuick
import Quickshell
import Quickshell.Networking
import qs.Commons
import qs.Ui
import "NetworkLogic.js" as Logic

// Shared body for the dropdown and System pane. Masked fields deliver their
// secrets to NetworkManager; IPC receives public identity alone.
// A device's Details draws its rows once they are read: while the service
// reads, the row shows a Spinner and its content takes no height, so the
// rows under it move once.
// The Wi-Fi password prompt is a Dialog over a Scrim in the body's own
// window, drawn over `promptPane` when the host names one: the dropdown
// names its own Pane, so the Scrim also covers the title row's switch and
// gear and the footer, which lie outside the body, and none of them
// answers while the dialog waits. The System pane names none, and the
// prompt draws over the body there. The shared ModalDialog is a layer
// surface that takes the keyboard, and Hyprland ends the flyout's popup
// grab when one maps, which closes the flyout and the prompt with it
// (network smoke row with a ModalDialog on the prompt, 2026-10-13: the
// flyout read hidden at the first reading; Hyprland 0.56.2
// LayerSurface.cpp onMap, XDGShell.cpp addOrStartGrab).
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
    property var joinTarget: undefined
    property string joinInterface: ""
    property string openDetails: ""
    property var readyDetails: ({})
    readonly property var values: shell === null ? ({}) : shell.status.values
    // Whether the details tool is installed; its install is the plugin's
    // own offer, as a join's and a share's are.
    readonly property bool detailsReady: shell !== null && !shell.requirements.missing.includes("nmcli")
    readonly property var network: values.network || ({ wifi: [], ethernet: [], state: "unavailable", action: { kind: "idle" }, prompt: null, detail: { state: "idle", rows: [] } })
    readonly property var rows: network.wifi || []
    readonly property var selected: rows.find(row => row.key === currentKey) || null
    readonly property string permissionNotice: network.access === "unavailable" ? "Network permissions could not be checked. NetworkManager still handles each change." : ""
    readonly property bool busy: network.action.kind !== "idle"
    readonly property bool prompting: promptKey !== "" && content.visible
    // The prompted network while its dialog shows, else "". Its change is
    // the one place the dialog takes the focus: when it shows, a prompt
    // that waited behind Share or the join form included, and when its
    // network changes. Qt.callLater runs after the dialog's own `visible`
    // binding has followed `prompting`.
    readonly property string shownPrompt: prompting ? promptKey : ""
    onShownPromptChanged: if (shownPrompt !== "") Qt.callLater(() => { if (root.prompting) prompt.takeFocus(); })
    readonly property Item initialFocus: prompting ? password : list
    readonly property string promptName: network.prompt === null || !network.prompt ? "" : network.prompt.name
    property Pane promptPane: null
    readonly property Item promptHost: promptPane === null ? root : promptPane
    // The corner the scrim rounds to: the hosting Pane's container corner,
    // or none over the body, a square part of its page.
    readonly property real promptCorner: promptPane === null ? 0 : promptPane.cornerRadius
    // The view that scrolls the body, read when a prompt opens, and the
    // body's top in that view's content. The prompt centres on the part of
    // its host the view shows, so a long list scrolled down still shows it;
    // a Pane that hosts it does not scroll, and shows all of it.
    // Flickable.contentY is the content coordinate at the view's top edge
    // (Qt 6 Flickable reference).
    property Flickable promptView: null
    property real promptOrigin: 0
    readonly property real shownTop: promptPane !== null || promptView === null ? 0 : Math.max(0, Math.min(height, promptView.contentY - promptOrigin))
    readonly property real shownBottom: promptPane !== null ? promptPane.height : promptView === null ? height : Math.max(shownTop, Math.min(height, promptView.contentY - promptOrigin + promptView.height))
    // The body keeps the prompt's height, so the Pane that hosts it is
    // never shorter than the dialog either.
    implicitHeight: joinTarget !== undefined ? (joinLoader.item === null ? 0 : joinLoader.item.implicitHeight) : shareTarget === null ? Math.max(content.implicitHeight, prompting ? prompt.implicitHeight + 2 * Theme.dialog.margin : 0) : shareLoader.item === null ? 0 : shareLoader.item.implicitHeight

    function open() {
        if (leaseId === "") leaseId = String(root);
        if (shell !== null && !leased) {
            leased = answered(shell.ipc.call("lease", JSON.stringify({ id: leaseId, open: true }))) === "ok";
        }
        if (currentKey === "" && rows.length) currentKey = rows[0].key;
    }
    function close() {
        closeJoin();
        closeShare();
        if (promptKey !== "") cancelPassword(false);
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
        if (!network.wifiEnabled || !network.hasWifi || (joinTarget !== undefined && joinInterface !== network.wifiInterface)) closeJoin();
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
        const held = prompt.activeFocus;
        password.text = "";
        promptKey = next;
        if (next === "") {
            if (held) list.forceActiveFocus(Qt.OtherFocusReason);
            return;
        }
        promptView = null;
        for (let at = root.parent; at !== null && promptView === null; at = at.parent) {
            if (at instanceof Flickable) {
                promptOrigin = root.mapToItem(at.contentItem, 0, 0).y;
                promptView = at;
            }
        }
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
        if (!row.connected && !row.known && Logic.supportsEnterprise(row.security)) { join(row); return; }
        action(row.connected ? "disconnect" : "connect", row);
    }
    function join(row) {
        if (!network.writable || busy || shell === null) return;
        if (shell.requirements.missing.includes("nmcli")) { shell.requirements.offer(["nmcli"]); return; }
        closeShare();
        // A later status update must not move an open form to another adapter.
        joinInterface = row === null ? network.wifiInterface || "" : row.interface;
        joinTarget = row;
    }
    function closeJoin() {
        if (joinLoader.item !== null) joinLoader.item.clear();
        joinTarget = undefined;
        joinInterface = "";
    }
    function cancelPassword(takeFocus = true) {
        password.text = "";
        promptKey = "";
        action("cancel", null);
        if (takeFocus) list.forceActiveFocus(Qt.ShortcutFocusReason);
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
        expandable: root.detailsReady
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
        id: joinLoader
        width: root.width
        active: root.joinTarget !== undefined
        sourceComponent: NetworkJoin {
            width: root.width
            shell: root.shell
            target: root.joinTarget === undefined ? null : root.joinTarget
            interfaceName: root.joinInterface
            onDismissed: { root.closeJoin(); if (!root.prompting) list.forceActiveFocus(Qt.ShortcutFocusReason); }
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
            onDismissed: { root.closeShare(); if (!root.prompting) list.forceActiveFocus(Qt.ShortcutFocusReason); }
        }
    }

    // The page is disabled while the prompt shows over it. A disabled item
    // loses the active focus and takes no keyboard events (Qt 6 Item.enabled
    // reference), and Tab passes over it (network smoke row, Tab from the
    // System search, 2026-10-13), so a focus from outside the body reaches
    // the dialog and never the list behind the scrim.
    Column {
        id: content
        width: root.width
        visible: root.shareTarget === null && root.joinTarget === undefined
        enabled: !root.prompting
        spacing: Theme.stack.group
        Label {
            width: parent.width
            role: "body"
            text: root.network.text || Logic.stateText("unavailable")
            wrapMode: Text.Wrap
        }
        RowActions {
            visible: !!root.network.portalAvailable
            RowAction {
                objectName: "network-sign-in"
                text: "Sign in"
                onClicked: root.action("sign-in", null)
            }
            RowAction {
                objectName: "network-check-connectivity"
                text: "Check connection"
                onClicked: root.action("check-connectivity", null)
            }
        }
        LinkText {
            objectName: "network-problem"
            width: parent.width
            visible: text !== "" && !root.prompting
            role: "hint"
            color: Theme.color.danger
            text: root.localProblem || root.network.problem || ""
            wrapMode: Text.Wrap
            onPageActivated: (page, tab) => root.shell.surfaces.openPage(page, tab)
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
            inline: true
            hint: root.network.wifiHardwareEnabled === false ? "The hardware switch blocks Wi-Fi." : ""
            control: Switch {
                objectName: "network-radio"
                size: "sm"
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
                    onMenuRequested: index => wifiRepeater.itemAt(index).openMenu("key")
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
                            iconName: Logic.wifiIcon(modelData.strength)
                            secondary: modelData.changing ? "Connecting…" : (modelData.connected ? "Connected · " : modelData.known ? "Saved · " : "") + Logic.securityLabel(modelData.security)
                            badge: modelData.strength + "%"
                            cursor: networkCursor
                            highlighted: root.currentKey === modelData.key
                            focusPolicy: Qt.NoFocus
                            enabled: !!root.network.writable && !root.busy
                            onClicked: { root.currentKey = modelData.key; root.activate(modelData); }
                            menuEntries: [
                                MenuItem { text: "Forget"; iconName: "trash"; enabled: wifiRow.modelData.known; onTriggered: root.action("forget", wifiRow.modelData) },
                                MenuItem { text: "Details"; iconName: "info"; enabled: root.detailsReady; onTriggered: { root.openDeviceDetails(wifiRow.modelData.interface); } },
                                MenuItem { text: "Share QR code"; iconName: "qr-code"; enabled: Logic.shareable(wifiRow.modelData); onTriggered: root.share(wifiRow.modelData) }
                            ]
                        }
                    }
                }
            }
        }
        Button {
            objectName: "network-other"
            text: "Other Network…"
            variant: "secondary"
            visible: !!root.network.hasWifi && !!root.network.wifiEnabled
            enabled: !!root.network.writable && !root.busy
            onClicked: root.join(null)
        }
        Section {
            width: parent.width
            visible: !!root.network.hasWifi && (root.expanded || root.openDetails === root.network.wifiInterface)
            title: "Wi-Fi options"
            // The row and its cursor, beside the section's column: a
            // positioner would lay the plate out as a row.
            Item {
                width: parent.width
                height: wifiDetails.height
                visible: root.network.wifiInterface !== ""
                ListCursor { id: wifiDetailsCursor }
                DeviceDetails {
                    id: wifiDetails
                    cursor: wifiDetailsCursor
                    device: root.network.wifiInterface
                    label: "Wi-Fi device"
                    stateLine: root.network.wifiInterface
                    glyph: "wifi"
                }
            }
            Field {
                width: parent.width
                visible: root.expanded
                label: "Auto-join"
                inline: true
                hint: "Allow this Wi-Fi device to join saved networks automatically."
                control: Switch {
                    objectName: "network-autojoin"
                    size: "sm"
                    checked: !!root.network.wifiAutoconnect
                    enabled: !!root.network.writable
                    onClicked: { root.action("autoconnect", { interface: root.network.wifiInterface }); }
                }
            }
            RowActions {
                visible: root.expanded
                RowAction { text: "Forget"; enabled: root.selected !== null && root.selected.known && !root.busy; onClicked: root.action("forget", root.selected) }
                RowAction { text: "Share QR code"; enabled: Logic.shareable(root.selected); onClicked: root.share(root.selected) }
            }
        }
        Section {
            width: parent.width
            title: "Ethernet"
            description: (root.network.ethernet || []).length ? "" : "No Ethernet device detected."
            // The rows and their cursor, beside the rows' column.
            Item {
                width: parent.width
                height: ethernetRows.height
                visible: (root.network.ethernet || []).length > 0
                ListCursor { id: ethernetCursor }
                Column {
                    id: ethernetRows
                    width: parent.width
                    spacing: Theme.stack.row
                    Repeater {
                        model: ScriptModel { values: root.network.ethernet || []; objectProp: "name" }
                        DeviceDetails {
                            required property var modelData
                            cursor: ethernetCursor
                            device: modelData.name
                            label: modelData.name
                            stateLine: Logic.ethernetText(modelData.state)
                            glyph: "ethernet-port"
                        }
                    }
                }
            }
            RowAction {
                visible: root.expanded && root.shell !== null && !root.detailsReady
                text: "Install details tool"
                onClicked: {
                    const reply = root.shell.requirements.offer(["nmcli"]);
                    root.answered(reply === "satisfied" ? "ok" : reply);
                }
            }
        }
        Section {
            width: parent.width
            visible: root.expanded
            title: "Bar"
            Field {
                width: parent.width
                label: "Show disconnected icon"
                inline: true
                control: Switch {
                    size: "sm"
                    checked: root.shell === null || root.shell.settings.showDisconnected
                    onClicked: root.answered(root.shell.configure.set("showDisconnected", checked))
                }
            }
        }
    }

    // The scrim takes each press, hover and wheel over its host. A press on
    // it keeps the typed text. Over a Pane it rounds to the Pane's container
    // corner, the dropdown Surface's, so it darkens nothing outside the card
    // in the transparent popup. Both items join the host when it is named,
    // in no set order, so the dialog's `z` keeps it above the scrim.
    Scrim {
        visible: root.prompting
        parent: root.promptHost
        radius: root.promptCorner
        onClicked: prompt.takeFocus()
    }
    Dialog {
        id: prompt
        objectName: "network-prompt"
        parent: root.promptHost
        z: 1
        visible: root.prompting
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.shownTop + Math.max(0, (root.shownBottom - root.shownTop - height) / 2)
        width: Math.min(implicitWidth, root.width)
        title: "Wi-Fi password"
        Accessible.description: [root.promptName, root.network.problem || ""].filter(Boolean).join(". ")
        initialFocus: password
        actions: [{ label: "Cancel", role: "cancel" }, { label: "Join", role: "accept", enabled: password.text !== "" }]
        onAccepted: root.submitPassword()
        onRejected: root.cancelPassword()

        Label {
            objectName: "network-prompt-reason"
            width: parent.width
            visible: text !== ""
            role: "bodyStrong"
            color: Theme.color.danger
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: root.network.problem || ""
        }
        // The name comes from the access point. Plain text draws it as
        // sent: Qt's default AutoText would style a name that holds tags,
        // and the Dialog's message would draw a page reference in it as a link.
        Label {
            objectName: "network-prompt-name"
            width: parent.width
            textFormat: Text.PlainText
            wrapMode: Text.Wrap
            text: root.promptName === "" ? "Enter the password for this network." : "Enter the password for " + root.promptName + "."
        }
        TextField {
            id: password
            objectName: "network-password"
            width: parent.width
            password: true
            placeholderText: "Wi-Fi password"
        }
    }
}
