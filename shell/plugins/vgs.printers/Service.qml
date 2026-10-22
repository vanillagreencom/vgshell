import QtQuick
import Quickshell
import Quickshell.Io
import "PrintersLogic.js" as Logic

// The Printers service: the one owner of the `lpstat` reads, the change
// watcher bin/printers-watch and the calls to the CUPS D-Bus helper
// (PrintersLogic.js decides; this runs the processes). The pane asks it
// through the plugin's own IPC, which `vgshell ipc call vgs.printers
// invoke <name> <arg>` reaches too:
//   default NAME    make printer NAME the default
//   remove NAME     remove printer NAME
//   add URI         add the found device URI, driverless only
//   address TEXT    add the printer at the address TEXT
//   find            ask CUPS for the devices it can reach
//   retry           read the printers again, and start the watcher again
//                   after it ended
//   view begin      the pane opened; answers `lease=<id>`
//   view end ID     the pane with lease ID closed; answers `ok`
// Each other answers `ok`, `busy` while a change runs, or a refusal; a
// change's end is published, never answered.
//
// It publishes the status `printing`, the Settings page's line, with the
// service-cups step's Turn on printing action while CUPS is not running
// and the step applies, and `printers`, the data the pane draws: the
// scheduler's state, the printers, the watcher, the change and the found
// devices.
//
// Only the pane shows live printer state, so the watcher, and with it the
// CUPS subscription and dbus-monitor, runs only while a pane holds a view
// lease (Pane.qml takes one when it opens and ends it when it closes or is
// destroyed). With no lease open the service holds no process and no
// subscription; the last lease's end stops the watcher, whose own trap
// cancels the subscription.
//
// A read is lpstat for the printers, their jobs and devices, then ipptool
// over ipp/default.test for the scheduler's default, the one Set as
// default changes. The list is never polled. The service reads once when a view
// opens, when the Settings page shows the plugin (`status.viewed`), which
// draws the `printing` line, after the watcher's `ready` and each CUPS
// notification it prints, after each of its own changes ends, and on
// `retry`; a read that comes while one runs reads once more after it.
// While a view or the Settings page is shown and the printers are unread,
// a requirement scan or a system step run that leaves the step ready reads
// them again too.
Item {
    id: root

    // The core assigns the plugin's scoped shell object after creation.
    property var shell: null
    // Whether the IPC handlers are registered, so a settings change that
    // hands over a new object registers nothing twice.
    property bool registered: false
    // Set while the service is destroyed, so the watcher's end it causes
    // is not taken for a failure.
    property bool closing: false
    // The pane's open views, PrintersLogic.viewIdle() and on.
    property var views: Logic.viewIdle()
    readonly property bool shown: views.leases.length > 0
    readonly property bool viewed: shell !== null && shell.status.viewed

    readonly property var missing: shell === null ? [] : shell.requirements.missing
    readonly property bool cupsMissing: Logic.CUPS_COMMANDS.some(command => missing.indexOf(command) !== -1)
    readonly property bool watchMissing: missing.indexOf("dbus-monitor") !== -1
    readonly property bool helperMissing: missing.indexOf("gdbus") !== -1 || missing.indexOf(Logic.HELPER) !== -1
    readonly property int scans: shell === null ? 0 : shell.requirements.revision
    readonly property string step: {
        if (shell === null) return "";
        const found = shell.system.state["service-cups"];
        return found === undefined ? "" : found.state;
    }

    // lpstat's last reading: { state: "unread" }, or lpstatReading's answer.
    property var reading: ({ state: "unread" })
    // The watcher: off, starting, ready, stopping once the last view
    // closed, or ended once it exited on its own.
    property string watch: "off"
    property var op: Logic.opIdle()
    // The last find: { state: idle|finding|found|failed, devices }.
    property var found: ({ state: "idle", devices: [] })

    readonly property var printers: reading.state === "read" ? reading.printers : []
    readonly property var printing: Logic.printingView(reading, cupsMissing, step)
    readonly property var view: ({
        cups: cupsMissing ? "missing" : reading.state,
        printers: printers,
        watch: watch,
        op: Logic.opView(op),
        found: { state: found.state, devices: Logic.foundShown(found.devices, printers) },
        helper: helperMissing ? "missing" : "present"
    })

    onShellChanged: {
        if (shell === null || registered) return;
        registered = true;
        shell.ipc.handle("default", arg => root.change("default", arg));
        shell.ipc.handle("remove", arg => root.change("remove", arg));
        shell.ipc.handle("add", arg => root.addFound(arg));
        shell.ipc.handle("address", arg => root.addAddress(arg));
        shell.ipc.handle("find", () => root.begin("find", "", Logic.findSteps()));
        shell.ipc.handle("retry", () => root.retry());
        shell.ipc.handle("view", arg => root.viewCall(arg));
        publish();
    }
    onViewChanged: publish()
    onPrintingChanged: publish()
    onShownChanged: {
        if (shown) {
            if (watch === "ended") watch = "off";
            read();
        } else {
            stopWatch();
        }
    }
    onViewedChanged: if (viewed) read()
    onScansChanged: if ((shown || viewed) && reading.state !== "read") read()
    onStepChanged: if ((shown || viewed) && step === "ready" && reading.state === "down") read()
    Component.onDestruction: closing = true

    function publish() {
        if (shell === null) return;
        const line = shell.status.set("printing", printing);
        if (line !== "ok") console.error("printers: status printing " + line);
        const data = shell.status.set("printers", view);
        if (data !== "ok") console.error("printers: status printers " + data);
    }

    function read() {
        if (shell === null || cupsMissing) return;
        if (reader.running || defaults.running) {
            reader.again = true;
            return;
        }
        reader.completion = null;
        reader.running = true;
    }

    function retry() {
        if (!watcher.running) watch = "off";
        read();
        return "ok";
    }

    function startWatch() {
        watch = "starting";
        watcher.completion = null;
        watcher.running = true;
    }

    // Setting `running` to false sends SIGTERM (Quickshell 0.3.1,
    // Process.running), which the watcher forwards to its second process,
    // whose trap cancels the subscription.
    function stopWatch() {
        if (watcher.running) {
            watch = "stopping";
            watcher.running = false;
        } else {
            watch = "off";
        }
    }

    // `begin`, or `end <id>`.
    function viewCall(arg) {
        if (arg === "begin") {
            const begun = Logic.viewBegin(views);
            views = begun.state;
            return "lease=" + begun.id;
        }
        const match = /^end ([1-9][0-9]*)$/.exec(arg);
        if (match === null) return "refused: view=" + JSON.stringify(arg) + " want=begin|end <id>";
        const ended = Logic.viewEnd(views, Number(match[1]));
        if (!ended.known) return "refused: lease=" + match[1] + " reason=unknown";
        views = ended.state;
        return "ok";
    }

    // ipp/ test file NAME's path.
    function ippTest(name) { return String(Qt.resolvedUrl("ipp/" + name)).replace(/^file:\/\//, ""); }

    // The end of one read, READING with the default applied.
    function readEnded(reading) {
        root.reading = reading;
        if (shown && reading.state === "read" && watch === "off" && !watchMissing) startWatch();
        if (reader.again) {
            reader.again = false;
            read();
        }
    }

    // NAME's printer of the last reading, or undefined.
    function printerNamed(name) { return printers.find(p => p.name === name); }

    function change(kind, name) {
        if (printerNamed(name) === undefined) return "refused: printer=" + JSON.stringify(name) + " reason=unknown";
        return begin(kind, name, kind === "default" ? Logic.defaultSteps(name) : Logic.removeSteps(name));
    }

    // A press of Add again, after a change that left the queue, must not add
    // a second queue for one device.
    function addFound(uri) {
        const device = found.devices.find(d => d.uri === uri);
        if (device === undefined) return "refused: device=" + JSON.stringify(uri) + " reason=unknown";
        if (!device.driverless) return "refused: device=" + JSON.stringify(uri) + " reason=driver";
        if (printers.some(p => p.uri === uri)) return "refused: device=" + JSON.stringify(uri) + " reason=installed";
        const name = Logic.queueName(device.info, printers.map(p => p.name));
        return begin("add", name, Logic.addSteps(name, device.uri, device.info));
    }

    function addAddress(text) {
        const device = Logic.addressDevice(text);
        if (!device.ok) return "refused: address=" + device.problem;
        if (printers.some(p => p.uri === device.uri)) return "refused: address=installed";
        const name = Logic.queueName(device.host, printers.map(p => p.name));
        return begin("add", name, Logic.addSteps(name, device.uri, device.host));
    }

    // Start a change of KIND on TARGET that makes the helper calls STEPS.
    function begin(kind, target, steps) {
        if (op.phase === "running") return "busy";
        if (helperMissing) return "refused: helper=missing";
        op = Logic.opBegin(kind, target, steps);
        if (kind === "find") found = { state: "finding", devices: found.devices };
        runStep();
        return "ok";
    }

    function runStep() {
        helper.completion = null;
        helper.command = op.steps[op.index];
        helper.running = true;
    }

    function stepEnded(code) {
        const reply = Logic.helperReply(code, helperOutput.text, helperErrors.text);
        if (!reply.ok) console.warn("printers: " + op.kind + " " + JSON.stringify(op.target) + " problem=" + reply.problem + " " + reply.detail);
        op = Logic.opAdvance(op, reply);
        if (op.phase === "running") {
            runStep();
            return;
        }
        if (op.kind === "find")
            found = op.phase === "done" ? { state: "found", devices: Logic.foundDevices(reply.value[1], printers) } : { state: "failed", devices: [] };
        else
            read();
    }

    // Each child gets PATH, HOME, which holds the user's lpoptions, CUPS's
    // own server variable and the system bus address, with the C locale, so
    // lpstat prints the lines lpstatReading reads. Under clearEnvironment a
    // null value passes the shell's own value through (Quickshell 0.3.1,
    // Process.clearEnvironment).
    readonly property var childEnvironment: ({ PATH: null, HOME: null, CUPS_SERVER: null, DBUS_SYSTEM_BUS_ADDRESS: null, LC_ALL: "C" })

    // A command that fails to start emits only runningChanged, so each end
    // is read there: no exit recorded is a failed start.
    Process {
        id: reader
        property var completion: null
        property bool again: false
        command: Logic.LPSTAT_ARGV
        clearEnvironment: true
        environment: root.childEnvironment
        stdout: StdioCollector { id: readOutput }
        stderr: StdioCollector { id: readErrors }
        onExited: (code, status) => { reader.completion = { code: code }; }
        onRunningChanged: {
            if (running) return;
            const code = reader.completion === null ? -1 : reader.completion.code;
            const reading = Logic.lpstatReading(code, readOutput.text);
            if (reading.state === "failed") console.warn("printers: lpstat reason=" + reading.reason + " " + readErrors.text.trim());
            if (reading.state !== "read") {
                root.readEnded(reading);
                return;
            }
            defaults.listed = reading;
            defaults.completion = null;
            defaults.running = true;
        }
    }

    // The scheduler's own default, which Set as default changes, read after
    // the list it marks.
    Process {
        id: defaults
        property var completion: null
        property var listed: null
        command: Logic.ippArgv(root.ippTest("default.test"), {})
        clearEnvironment: true
        environment: root.childEnvironment
        stdout: StdioCollector { id: defaultOutput }
        stderr: StdioCollector { id: defaultErrors }
        onExited: (code, status) => { defaults.completion = { code: code }; }
        onRunningChanged: {
            if (running) return;
            const found = Logic.defaultReading(defaults.completion === null ? -1 : defaults.completion.code, defaultOutput.text);
            if (!found.ok) console.warn("printers: default reason=" + found.reason + " " + defaultErrors.text.trim().split("\n")[0]);
            root.readEnded(Logic.withDefault(defaults.listed, found.ok ? found.name : ""));
        }
    }

    // The watcher's second process cancels the subscription when Process
    // destruction kills its parent. Its stdin lease also ends it when
    // its connection to the shell closes.
    Process {
        id: watcher
        property var completion: null
        stdinEnabled: true
        command: ["setpriv", "--pdeathsig", "TERM", "--", String(Qt.resolvedUrl("bin/printers-watch")).replace(/^file:\/\//, ""), Logic.CUPS_URI]
        clearEnvironment: true
        environment: root.childEnvironment
        stdout: SplitParser {
            onRead: line => {
                const event = Logic.watchLine(line);
                if (event.kind === "ready") {
                    root.watch = "ready";
                    root.read();
                } else if (event.kind === "event") {
                    root.read();
                } else {
                    console.warn("printers: watcher line unknown: " + line);
                }
            }
        }
        stderr: StdioCollector { id: watchErrors }
        onExited: (code, status) => { watcher.completion = { code: code }; }
        onRunningChanged: {
            if (running || root.closing) return;
            if (root.watch === "stopping") {
                root.watch = "off";
                // A cancel CUPS refused, the one line the watcher prints on
                // a stop.
                if (watchErrors.text.trim() !== "") console.warn("printers: watcher stopped " + watchErrors.text.trim().split("\n").join(" "));
                // A view that opened while the watcher stopped starts it again.
                if (root.shown) root.read();
                return;
            }
            const code = watcher.completion === null ? "not-started" : watcher.completion.code;
            console.warn("printers: watcher ended exit=" + code + " " + watchErrors.text.trim().split("\n")[0]);
            root.watch = "ended";
            root.read();
        }
    }

    Process {
        id: helper
        property var completion: null
        clearEnvironment: true
        environment: root.childEnvironment
        stdout: StdioCollector { id: helperOutput }
        stderr: StdioCollector { id: helperErrors }
        onExited: (code, status) => { helper.completion = { code: code }; }
        onRunningChanged: {
            if (running || root.closing) return;
            root.stepEnded(helper.completion === null ? -1 : helper.completion.code);
        }
    }
}
