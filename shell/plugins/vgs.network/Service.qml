import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import "NetworkLogic.js" as Logic

// One scanner owner for every open network surface. Leases are keyed by
// the QML instance; closing one view cannot turn another view's scan off.
Item {
    id: root
    property var shell: null
    property bool registered: false
    property var leases: ({})
    property var scannerDevice: null
    property string serviceState: "unavailable"
    property string access: "unavailable"
    property var operation: null
    readonly property var action: operation === null ? ({ kind: "idle" }) : ({
        kind: operation.kind === "psk" ? "connect" : operation.kind, key: operation.key, known: operation.known
    })
    // Native methods return no result for a D-Bus refusal. One watchdog
    // bounds an unacknowledged request and an observed transition.
    readonly property int requestTimeout: 10000
    readonly property int transitionTimeout: 120000
    readonly property int terminalGrace: 1000
    property var prompt: null
    property string problem: ""
    property var detail: ({ interface: "", state: "idle", rows: [] })
    readonly property var securityVariants: ({
        Wpa3SuiteB192: WifiSecurityType.Wpa3SuiteB192, Sae: WifiSecurityType.Sae,
        Wpa2Eap: WifiSecurityType.Wpa2Eap, Wpa2Psk: WifiSecurityType.Wpa2Psk,
        WpaEap: WifiSecurityType.WpaEap, WpaPsk: WifiSecurityType.WpaPsk,
        StaticWep: WifiSecurityType.StaticWep, DynamicWep: WifiSecurityType.DynamicWep,
        Leap: WifiSecurityType.Leap, Owe: WifiSecurityType.Owe, Open: WifiSecurityType.Open,
        Unknown: WifiSecurityType.Unknown
    })
    readonly property var failureVariants: ({
        NoSecrets: ConnectionFailReason.NoSecrets, WifiAuthTimeout: ConnectionFailReason.WifiAuthTimeout,
        WifiClientFailed: ConnectionFailReason.WifiClientFailed
    })
    readonly property var connectivityVariants: ({
        Portal: NetworkConnectivity.Portal, Limited: NetworkConnectivity.Limited,
        Full: NetworkConnectivity.Full, None: NetworkConnectivity.None, Unknown: NetworkConnectivity.Unknown
    })
    readonly property var devices: Networking.devices.values
    readonly property var wifiDevice: devices.find(d => d.type === DeviceType.Wifi) || null
    readonly property var wifiObjects: wifiDevice ? wifiDevice.networks.values : []
    readonly property var wifiRows: Logic.ordered(wifiObjects.map(n => ({
        key: JSON.stringify([n.device.name, n.name]), name: n.name, interface: n.device.name,
        strength: Logic.strength(n.signalStrength), security: Logic.enumName(n.security, securityVariants),
        known: n.known, connected: n.connected, changing: n.stateChanging
    })))
    readonly property var wiredRows: Logic.ethernetOrdered(devices.filter(d => d.type === DeviceType.Wired).map(d => ({
        name: d.name, connected: d.connected, managed: d.nmManaged, autoconnect: d.autoconnect,
        speed: d.linkSpeed, link: d.hasLink, state: Logic.ethernetState(d.nmManaged, d.connected, d.hasLink)
    })))
    readonly property bool backendAvailable: Networking.backend === NetworkBackendType.NetworkManager
    readonly property bool managed: devices.length === 0 || devices.some(d => d.nmManaged)
    readonly property bool connected: devices.some(d => d.connected && (d.type !== DeviceType.Wifi || Networking.wifiEnabled))
    readonly property string state: Logic.state(serviceState, backendAvailable, managed, access,
        connected, Logic.enumName(Networking.connectivity, connectivityVariants), Networking.connectivityCheckEnabled,
        Networking.wifiEnabled, wifiDevice !== null)
    readonly property int leaseCount: Object.keys(leases).length
    readonly property bool nmcliPresent: shell !== null && shell.requirements.missing.indexOf("nmcli") === -1
    readonly property var snapshot: ({ state: state, access: access, text: Logic.summary({ state: state, wifi: wifiRows, ethernet: wiredRows }),
        wifi: wifiRows, ethernet: wiredRows, wifiEnabled: Networking.wifiEnabled,
        wifiHardwareEnabled: Networking.wifiHardwareEnabled, hasWifi: wifiDevice !== null,
        wifiAutoconnect: wifiDevice ? wifiDevice.autoconnect : false, wifiInterface: wifiDevice ? wifiDevice.name : "",
        writable: Logic.writable(state), action: action, prompt: prompt, problem: problem, detail: detail })

    function publish() {
        if (shell === null) return;
        const writes = [
            ["network", snapshot],
            ["connection", { tone: state === "connected" ? "ok" : Logic.writable(state) ? "info" : "warning", text: Logic.stateText(state) }],
            ["detailsTool", { tone: nmcliPresent ? "ok" : "info", text: nmcliPresent ? "Available" : "Connection details need the details tool.", action: !nmcliPresent }]
        ];
        for (let i = 0; i < writes.length; i++) {
            const reply = shell.status.set(writes[i][0], writes[i][1]);
            if (reply !== "ok") console.warn("network status: " + reply);
        }
    }
    onSnapshotChanged: publish()
    onNmcliPresentChanged: {
        if (!nmcliPresent) access = "unavailable";
        publish();
    }
    onWifiDeviceChanged: {
        prompt = null;
        finishOperation(operation === null ? "" : "The network device is no longer available.");
        Qt.callLater(root.moveScanner);
    }
    onLeaseCountChanged: moveScanner()
    onWifiObjectsChanged: {
        if (operation !== null && wifiObjects.indexOf(operation.network) === -1)
            finishOperation("The network is no longer available.");
        if (prompt !== null && network(prompt.key) === null) prompt = null;
    }

    // Quickshell 0.3.1 lists a network only while its device scans, is
    // connected to it or holds its settings, and setting scannerEnabled
    // asks for a scan, again at most every scan interval
    // (network/nm/wireless.cpp).
    function moveScanner() {
        const next = leaseCount > 0 ? wifiDevice : null;
        if (scannerDevice !== null && scannerDevice !== next) scannerDevice.scannerEnabled = false;
        scannerDevice = next;
        if (scannerDevice !== null) scannerDevice.scannerEnabled = true;
        else if (wifiDevice !== null) wifiDevice.scannerEnabled = false;
    }
    Component.onDestruction: if (scannerDevice !== null) scannerDevice.scannerEnabled = false

    function lease(arg) {
        const request = JSON.parse(arg);
        if (typeof request.id !== "string" || request.id === "" || typeof request.open !== "boolean") return "refused: lease=value";
        const next = Object.assign({}, leases);
        if (request.open) next[request.id] = true;
        else delete next[request.id];
        leases = next;
        if (request.open) refresh();
        return "ok";
    }

    function network(key) {
        return wifiObjects.find(n => JSON.stringify([n.device.name, n.name]) === key) || null;
    }

    function finishOperation(message) {
        watchdog.stop();
        operation = null;
        if (message !== "") problem = message;
    }

    function beginOperation(kind, n, key) {
        prompt = null;
        problem = "";
        operation = { kind: kind, key: key, network: n, known: n.known, changing: false };
        watchdog.interval = requestTimeout;
        watchdog.restart();
    }

    function reconcile(n) {
        const pending = operation;
        if (pending === null || pending.network !== n) return;
        const result = Logic.operationResult(pending.kind, n.connected, n.known, n.stateChanging, pending.changing);
        if (result === "complete") {
            finishOperation(""); prompt = null; problem = "";
        } else if (n.stateChanging && !pending.changing) {
            operation = Object.assign({}, pending, { changing: true });
            watchdog.interval = transitionTimeout;
            watchdog.restart();
        } else if (result === "terminal") {
            // The state property can precede the credentials failure signal.
            // Keep its matching owner during that signal's delivery window.
            watchdog.interval = terminalGrace;
            watchdog.restart();
        }
    }

    function expired() {
        if (operation === null) return;
        const n = operation.network;
        if (n !== null && Logic.operationResult(operation.kind, n.connected, n.known, n.stateChanging, operation.changing) === "complete") {
            finishOperation(""); prompt = null; problem = "";
        } else {
            finishOperation("The network change did not complete. Try again.");
        }
    }

    Timer {
        id: watchdog
        objectName: "network-operation-watchdog"
        repeat: false
        onTriggered: root.expired()
    }

    function act(arg) {
        const request = JSON.parse(arg);
        if (request.kind === "cancel") { prompt = null; problem = ""; return "ok"; }
        if (!Logic.writable(state)) return "refused: network=" + state;
        if (request.kind === "radio") {
            if (Networking.wifiEnabled) {
                prompt = null;
                finishOperation(operation === null ? "" : "The network change was canceled because Wi-Fi was turned off.");
            }
            Networking.wifiEnabled = !Networking.wifiEnabled;
            return "ok";
        }
        if (request.kind === "autoconnect") {
            const device = devices.find(d => d.name === request.interface);
            if (!device) return "refused: device=absent";
            device.autoconnect = !device.autoconnect;
            return "ok";
        }
        const n = network(request.key);
        if (n === null) return "refused: network=absent";
        if (!n.device.nmManaged) return "refused: network=unmanaged";
        if (operation !== null || n.stateChanging) return "busy";
        if (["connect", "disconnect", "forget", "psk"].indexOf(request.kind) === -1) return "refused: action=unknown";
        beginOperation(request.kind, n, request.key);
        if (request.kind === "connect") n.connect();
        else if (request.kind === "disconnect") n.disconnect();
        else if (request.kind === "forget") n.forget();
        // psk only owns safe preparatory state. The masked field calls
        // NetworkManager directly; the secret never crosses this handler.
        return "ok";
    }

    function failed(n, reason) {
        const pending = operation;
        if (pending === null || pending.network !== n || ["connect", "psk"].indexOf(pending.kind) === -1) return;
        const security = Logic.enumName(n.security, securityVariants);
        finishOperation("");
        if (Logic.shouldReprompt(Logic.enumName(reason, failureVariants), security, pending.known)) {
            prompt = { key: pending.key, name: n.name };
            problem = pending.known ? "The saved password did not work. Enter the Wi-Fi password again." : "Enter the Wi-Fi password.";
        } else {
            prompt = null;
            problem = security.indexOf("Eap") >= 0 ? "This network needs enterprise Wi-Fi settings." : "The network could not connect. Check that it is in range and try again.";
        }
    }

    Instantiator {
        model: root.wifiDevice ? root.wifiDevice.networks : null
        delegate: Connections {
            required property var modelData
            target: modelData
            function onConnectionFailed(reason) { root.failed(modelData, reason); }
            function onConnectedChanged() { root.reconcile(modelData); }
            function onStateChanged() { root.reconcile(modelData); }
            function onStateChangingChanged() { root.reconcile(modelData); }
            function onKnownChanged() { root.reconcile(modelData); }
        }
    }

    function refresh() {
        if (shell === null) return "unavailable";
        if (!serviceProbe.running && shell.requirements.missing.indexOf("systemctl") === -1) serviceProbe.running = true;
        if (!nmcliPresent) access = "unavailable";
        else if (!permissions.running) permissions.running = true;
        return "ok";
    }
    Process {
        id: serviceProbe
        command: ["systemctl", "show", "--property=LoadState", "--property=ActiveState", "NetworkManager.service"]
        stdout: StdioCollector { id: unitText; waitForEnd: true }
        onExited: code => { root.serviceState = Logic.serviceProbe(unitText.text, code); }
    }
    Process {
        id: permissions
        command: ["nmcli", "-t", "-f", "PERMISSION,VALUE", "general", "permissions"]
        stdout: StdioCollector { id: permissionText; waitForEnd: true }
        onExited: code => { root.access = Logic.permission(permissionText.text, code); }
    }
    Process {
        id: detailsProcess
        stdout: StdioCollector { id: detailText; waitForEnd: true }
        onExited: code => { root.detail = { interface: root.detail.interface, state: code === 0 ? "ready" : "failed", rows: code === 0 ? Logic.details(detailText.text) : [] }; }
    }
    function details(interfaceName) {
        if (!nmcliPresent) return "refused: details=missing-tool";
        if (detailsProcess.running) return "busy";
        if (!devices.some(d => d.name === interfaceName)) return "refused: device=absent";
        detail = { interface: interfaceName, state: "loading", rows: [] };
        detailsProcess.command = ["nmcli", "-t", "device", "show", interfaceName];
        detailsProcess.running = true;
        return "ok";
    }
    onShellChanged: {
        if (shell === null) return;
        if (!registered) {
            registered = true;
            shell.ipc.handle("lease", root.lease);
            shell.ipc.handle("action", root.act);
            shell.ipc.handle("details", root.details);
            shell.ipc.handle("refresh", arg => root.refresh());
            shell.ipc.handle("open", arg => shell.surfaces.summon("panel", arg || "{}"));
            refresh();
        }
        publish();
    }
}
