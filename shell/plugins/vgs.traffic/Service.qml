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
    // The last request to kill an app while the panel is open: null, or
    // `{ name, state }`, `state` `running`, `sent` or `failed`.
    property var ending: null
    // A kill has started and its exit is not handled yet.
    property bool killing: false
    // Set first as the service is destroyed: a child stopped then reports
    // its end, and nothing may publish from it.
    property bool disposing: false
    readonly property var snapshot: ({ state: app.state, down: total.down, up: total.up, interfaces: total.interfaces,
        apps: app.apps, other: app.other, bandwhich: bandwhichPresent, ending: ending })

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
        ending = null;
        app = { state: "measuring", apps: [], other: { down: null, up: null } };
        if (socketLeaseCount === 0) sockets.running = false;
        else Qt.callLater(root.read);
    }

    // An app's pids and connections in the newest sample, for the panel's
    // Inspect and Kill. Reads only while the panel holds the sample.
    function inspect(arg) {
        const app = socketLeaseCount === 0 ? null : Logic.inspect(previousSockets, JSON.parse(arg).name);
        return app === null ? "refused: inspect=app" : JSON.stringify(app);
    }
    // SIGTERM to the pids of one app, each named for it by ss in the newest
    // sample, refused when that sample started more than two refresh
    // intervals ago: a read that a tick skipped, that hangs or that failed
    // leaves an older sample, or none. Linux hands out pids in turn up to
    // pid_max, so a pid the sample names is not given to a new process
    // within that time unless the pid space wraps around in it.
    function kill(arg) {
        if (socketLeaseCount === 0) return "refused: kill=closed";
        if (killing) return "refused: kill=busy";
        const request = JSON.parse(arg);
        const judged = Logic.killRequest(previousSockets, socketsAt, Date.now(), 2 * tick.interval, request);
        if (judged.error !== undefined) return "refused: kill=" + judged.error;
        ending = { name: request.name, state: "running" };
        killer.command = ["kill", "-TERM"].concat(judged.pids.map(String));
        killing = true;
        killer.running = true;
        return "ok";
    }
    function killed(code) {
        if (!killing || disposing) return;
        killing = false;
        if (code !== 0) console.warn("traffic: kill exit=" + code + " " + killErrors.text.trim());
        if (ending !== null) ending = { name: ending.name, state: code === 0 ? "sent" : "failed" };
        Qt.callLater(root.read);
    }

    function read() {
        if (leaseCount === 0 || shell === null) return;
        if (fileReading || socketReading || interfaces.running) { skippedTicks++; return; }
        fileReading = true;
        net.reload();
        net.text();
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
        if (!socketReading || disposing) return;
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
    // With preload off, reload unloads and text starts the asynchronous
    // read. loaded consumes completed data with no blocking. 0.3.1:
    // https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/FileView
    FileView {
        id: net
        path: "/proc/net/dev"
        preload: false
        blockLoading: false
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
            if (root.leaseCount === 0 || root.disposing) return;
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
    // kill(1) signals every pid it is given and exits non-zero when any
    // signal fails, naming the cause on stderr; it writes nothing to stdout.
    Process {
        id: killer
        clearEnvironment: true
        environment: ({ PATH: null, LC_ALL: "C" })
        stderr: StdioCollector { id: killErrors; waitForEnd: true }
        onExited: code => root.killed(code)
        // FailedToStart emits runningChanged without exited, as for ss.
        onRunningChanged: if (!running) root.killed(-1)
    }
    onShellChanged: {
        if (shell === null) return;
        if (!registered) {
            shell.ipc.handle("lease", root.lease);
            shell.ipc.handle("inspect", root.inspect);
            shell.ipc.handle("kill", root.kill);
            shell.ipc.handle("open", arg => shell.surfaces.summon("panel", arg || "{}"));
            shell.shortcut.register("open", "Network Traffic", () => shell.surfaces.toggle("panel", "{}"));
            registered = true;
        }
        publish();
    }
    Component.onDestruction: { disposing = true; tick.stop(); sockets.running = false; interfaces.running = false; killer.running = false; }
}
