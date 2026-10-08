import QtQuick
import Quickshell.Io
import "TrafficLogic.js" as Logic

Item {
    id: root
    property var shell: null
    property bool registered: false
    property var leases: ({})
    readonly property int leaseCount: Object.keys(leases).length
    readonly property int socketLeaseCount: Object.keys(leases).filter(id => leases[id] === "panel").length
    readonly property bool timerRunning: tick.running
    readonly property bool ssRunning: sockets.running
    readonly property bool bandwhichPresent: shell !== null && shell.requirements.missing.indexOf("bandwhich") === -1
    readonly property var captureStep: shell === null ? null : shell.system.state["bandwhich-capture"]
    property var previousTotals: null
    property double totalsAt: 0
    property var total: ({ down: null, up: null, interfaces: [] })
    property var previousSockets: null
    property double socketsAt: 0
    property var app: ({ state: "measuring", apps: [], other: { down: null, up: null } })
    property var interfaceNames: []
    property var countedNames: null
    property var resolvingNames: []
    property bool fileReading: false
    property bool socketReading: false
    property double socketStartedAt: 0
    property int socketGeneration: 0
    property int startedGeneration: 0
    property int ssStarts: 0
    property int skippedTicks: 0
    readonly property var snapshot: ({ state: app.state, down: total.down, up: total.up, interfaces: total.interfaces,
        apps: app.apps, other: app.other, bandwhich: bandwhichPresent })

    function publish() {
        if (shell === null || !registered) return;
        for (const row of [["traffic", snapshot], ["capture", Logic.capture(captureStep)]]) {
            const reply = shell.status.set(row[0], row[1]);
            if (reply !== "ok") console.warn("traffic: status " + reply);
        }
    }
    onSnapshotChanged: publish()
    onCaptureStepChanged: publish()

    function lease(arg) {
        const request = JSON.parse(arg);
        if (typeof request.id !== "string" || request.id === "" || typeof request.open !== "boolean"
            || (request.open && ["widget", "panel"].indexOf(request.kind) === -1)) return "refused: lease=value";
        const next = Object.assign({}, leases);
        if (request.open) {
            if (!Object.prototype.hasOwnProperty.call(next, request.id) && leaseCount >= 128) return "refused: lease=full";
            next[request.id] = request.kind;
        } else delete next[request.id];
        leases = next;
        return "ok";
    }
    onLeaseCountChanged: {
        if (leaseCount > 0) Qt.callLater(root.read);
        else {
            previousTotals = null;
            totalsAt = 0;
            total = { down: null, up: null, interfaces: [] };
        }
    }
    onSocketLeaseCountChanged: {
        socketGeneration++;
        previousSockets = null;
        socketsAt = 0;
        app = { state: "measuring", apps: [], other: { down: null, up: null } };
        if (socketLeaseCount === 0) sockets.running = false;
        else Qt.callLater(root.read);
    }

    function read() {
        if (leaseCount === 0 || shell === null) return;
        if (fileReading || socketReading || interfaces.running) { skippedTicks++; return; }
        fileReading = true;
        net.reload();
    }
    function netLoaded(text) {
        fileReading = false;
        if (leaseCount === 0) return;
        const sample = Logic.parseNetDev(text);
        if (sample === null) { failedTotals(); return; }
        const names = Object.keys(sample).sort();
        if (JSON.stringify(names) !== JSON.stringify(interfaceNames) || countedNames === null) {
            interfaceNames = names;
            countedNames = null;
            previousTotals = null;
            if (names.length === 0) { countedNames = []; acceptTotals(sample); return; }
            resolvingNames = names;
            interfaces.command = ["readlink", "-m", "--"].concat(names.map(name => "/sys/class/net/" + name));
            interfaces.running = true;
            total = { down: null, up: null, interfaces: [] };
            return;
        }
        acceptTotals(sample);
    }
    function acceptTotals(sample) {
        const at = Date.now();
        total = Logic.totals(sample, previousTotals, countedNames, at, totalsAt);
        previousTotals = sample;
        totalsAt = at;
        if (socketLeaseCount > 0 && shell.requirements.missing.indexOf("ss") === -1) {
            socketReading = true;
            socketStartedAt = at;
            startedGeneration = socketGeneration;
            ssStarts++;
            sockets.running = true;
        }
    }
    function failedTotals() {
        fileReading = false;
        previousTotals = null;
        total = { down: null, up: null, interfaces: [] };
        app = { state: "unknown", apps: [], other: { down: null, up: null } };
    }
    function finishSockets(code, text) {
        if (!socketReading) return;
        socketReading = false;
        if (socketLeaseCount === 0 || startedGeneration !== socketGeneration) return;
        if (code !== 0) {
            previousSockets = null;
            app = { state: "unknown", apps: [], other: { down: null, up: null } };
            return;
        }
        const sample = Logic.parseSockets(text);
        app = Logic.apps(sample, previousSockets, socketStartedAt, socketsAt, total);
        previousSockets = sample;
        socketsAt = socketStartedAt;
    }

    Timer {
        id: tick
        interval: (root.shell === null ? 2 : root.shell.settings.refreshSeconds) * 1000
        repeat: true
        running: root.leaseCount > 0
        onTriggered: root.read()
    }
    // FileView.reload starts an asynchronous read. text() in loaded reads
    // completed data without blocking: Quickshell 0.3.1 FileView reference.
    // https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/FileView
    FileView {
        id: net
        path: "/proc/net/dev"
        preload: false
        onLoaded: root.netLoaded(text())
        onLoadFailed: error => { root.failedTotals(); console.warn("traffic: net-dev read=" + error); }
    }
    // Null values pass only the named inherited variables with a cleared
    // environment: https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/Process
    Process {
        id: interfaces
        clearEnvironment: true
        environment: ({ PATH: null, LC_ALL: "C" })
        stdout: StdioCollector { id: interfaceOutput; waitForEnd: true }
        onExited: code => {
            if (root.leaseCount === 0) return;
            root.countedNames = code === 0 ? Logic.physicalInterfaces(root.resolvingNames, interfaceOutput.text.trim().split("\n")) : null;
            if (root.countedNames === null) root.failedTotals();
            else Qt.callLater(root.read);
        }
    }
    Process {
        id: sockets
        command: ["ss", "-tinpeH", "state", "connected"]
        clearEnvironment: true
        environment: ({ PATH: null, LC_ALL: "C" })
        stdout: StdioCollector { id: socketOutput; waitForEnd: true }
        onExited: code => root.finishSockets(code, socketOutput.text)
        // FailedToStart emits runningChanged without exited (0.3.1
        // process.cpp). Normal exited runs first and clears socketReading.
        onRunningChanged: if (!running && root.socketReading) root.finishSockets(-1, "")
    }
    onShellChanged: {
        if (shell === null) return;
        if (!registered) {
            shell.ipc.handle("lease", root.lease);
            shell.ipc.handle("open", arg => shell.surfaces.summon("panel", arg || "{}"));
            shell.shortcut.register("open", "Network Traffic", () => shell.surfaces.toggle("panel", "{}"));
            registered = true;
        }
        publish();
    }
    Component.onDestruction: { tick.stop(); sockets.running = false; interfaces.running = false; }
}
