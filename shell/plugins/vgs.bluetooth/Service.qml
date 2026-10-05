import QtQuick
import Quickshell
import Quickshell.Bluetooth
import Quickshell.Io
import "BluetoothLogic.js" as Logic

// The Bluetooth service: the one owner of the power operation, the rfkill
// reads and writes, and the discovery debt (BluetoothLogic.js decides; this
// runs the effects). Every other instance asks it through the plugin's own
// IPC, which `vgsh ipc call vgs.bluetooth invoke <name> <arg>` reaches too:
//   power on|off      turn Bluetooth on or off; answers `ok` or a refusal
//   discovery begin   take a discovery lease; answers `lease=<id>`
//   discovery end ID  end lease ID; answers `ok` or a refusal
//   refresh           read rfkill again; answers `ok`
// A panel or pane takes a discovery lease while it is shown and ends it
// from its own teardown (DiscoveryLease.qml).
//
// It publishes the status `power`, the line the Settings page draws, with
// the service-bluetooth step's Turn on action while no adapter exists and
// the step reads needed, and `bluetooth`, `{ power }`, powerView's answer,
// which the widget, the flyout and the pane draw.
//
// rfkill is read when the service starts, after each of its own block and
// unblock runs, after each requirement scan and whenever an adapter's
// Powered or PowerState changes, which BlueZ moves when a radio is
// blocked or unblocked by anything. It is never polled.
Item {
    id: root

    // The core assigns the plugin's scoped shell object after creation.
    property var shell: null
    // Whether the IPC handlers are registered, so a settings change that
    // hands over a new object registers nothing twice.
    property bool registered: false

    readonly property var adapters: Bluetooth.adapters.values
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool powered: adapters.some(a => a.enabled)
    readonly property bool adapterPowered: adapter !== null && adapter.enabled
    readonly property bool confirmed: adapter !== null && adapter.discovering
    // Every adapter's Powered and PowerState, so a change re-reads rfkill.
    readonly property string adapterStates: adapters.map(a => a.adapterId + "=" + a.enabled + "/" + a.state).join(",")
    readonly property bool rfkillMissing: shell !== null && shell.requirements.missing.indexOf("rfkill") !== -1
    readonly property int scans: shell === null ? 0 : shell.requirements.revision
    readonly property string step: {
        if (shell === null) return "";
        const found = shell.system.state["service-bluetooth"];
        return found === undefined ? "" : found.state;
    }

    // rfkill's last reading: { state: "unread" }, or rfkillReading's answer.
    property var rfkill: ({ state: "unread" })
    property var op: Logic.powerIdle()
    property var discovery: Logic.discoveryIdle()
    // The adapter the discovery debt belongs to.
    property var discoveryAdapter: null

    readonly property var view: Logic.powerView({
        rfkillMissing: rfkillMissing,
        rfkill: rfkill,
        adapters: adapters.length,
        powered: powered,
        op: op,
        step: step
    })

    onShellChanged: {
        if (shell === null || registered) return;
        registered = true;
        shell.ipc.handle("power", arg => root.request(arg));
        shell.ipc.handle("discovery", arg => root.discoveryCall(arg));
        shell.ipc.handle("refresh", () => {
            root.readRfkill();
            return "ok";
        });
        readRfkill();
        publish();
    }
    onViewChanged: publish()
    onAdapterStatesChanged: readRfkill()
    onScansChanged: readRfkill()
    onPoweredChanged: runPower(Logic.powerEvent(op, { type: "observed" }, seen()))
    onRfkillChanged: runPower(Logic.powerEvent(op, { type: "observed" }, seen()))
    onConfirmedChanged: applyDiscovery(Logic.discoveryConfirmed(discovery, discoveryContext()))
    onAdapterChanged: {
        if (discoveryAdapter !== null && adapter !== discoveryAdapter) applyDiscovery(Logic.discoveryReplaced(discovery));
        discoveryAdapter = adapter;
    }
    Component.onCompleted: discoveryAdapter = adapter
    Component.onDestruction: applyDiscovery(Logic.discoveryTeardown(discovery, discoveryContext()))

    function publish() {
        if (shell === null) return;
        const reply = shell.status.set("power", { tone: view.tone, text: view.text, action: view.action });
        if (reply !== "ok") console.error("bluetooth: status power " + reply);
        const data = shell.status.set("bluetooth", { power: view });
        if (data !== "ok") console.error("bluetooth: status bluetooth " + data);
    }

    // What is observed now, for the power operation. Read from the source
    // properties, since a change handler can run before the bindings that
    // read them (runtime-qml.md).
    function seen() { return { powered: adapters.some(a => a.enabled), rfkill: rfkill }; }

    // A press of a power switch; answers `ok` or the refusal, which the log
    // keeps.
    function request(want) {
        const result = Logic.powerRequest(op, want, view);
        runPower(result);
        if (result.reply !== "ok") console.warn("bluetooth: " + result.reply);
        return result.reply;
    }

    // Run one power step: its new state, then each effect in order.
    function runPower(result) {
        op = result.op;
        for (const effect of result.effects) {
            switch (effect.type) {
            case "run":
                startRfkill(effect.verb);
                break;
            case "arm":
                deadline.interval = effect.ms;
                deadline.restart();
                break;
            case "disarm":
                deadline.stop();
                break;
            case "enable":
                // Quickshell refuses Powered on a blocked adapter
                // (BluetoothAdapter::setEnabled), so those are left.
                for (const a of adapters)
                    if (!a.enabled && a.state !== BluetoothAdapterState.Blocked) a.enabled = true;
                break;
            case "read":
                readRfkill();
                break;
            default:
                throw new Error("bluetooth: power effect " + JSON.stringify(effect) + " is not one of run, arm, disarm, enable, read");
            }
        }
        if (op.phase === "failed" && result.effects.length > 0) console.warn("bluetooth: power failed reason=" + op.reason);
    }

    function startRfkill(verb) {
        if (writer.running) throw new Error("bluetooth: rfkill " + verb + " while rfkill " + writer.verb + " runs");
        writer.verb = verb;
        writer.completion = null;
        writer.command = ["rfkill", verb, "bluetooth"];
        writer.running = true;
    }

    function readRfkill() {
        if (shell === null || rfkillMissing) return;
        if (reader.running) {
            reader.again = true;
            return;
        }
        reader.completion = null;
        reader.running = true;
    }

    function discoveryContext() { return { powered: adapterPowered, confirmed: confirmed }; }

    function applyDiscovery(result) {
        discovery = result.state;
        for (const effect of result.effects) {
            if (adapter === null) return;
            if (effect === "start") adapter.discovering = true;
            else if (effect === "stop") adapter.discovering = false;
            else throw new Error("bluetooth: discovery effect " + JSON.stringify(effect) + " is not one of start, stop");
        }
    }

    // `begin`, or `end <id>`.
    function discoveryCall(arg) {
        if (arg === "begin") {
            const begun = Logic.discoveryBegin(discovery, discoveryContext());
            applyDiscovery(begun);
            return "lease=" + begun.id;
        }
        const match = /^end ([1-9][0-9]*)$/.exec(arg);
        if (match === null) return "refused: discovery=" + JSON.stringify(arg) + " want=begin|end <id>";
        const ended = Logic.discoveryEnd(discovery, Number(match[1]), discoveryContext());
        if (!ended.known) return "refused: lease=" + match[1] + " reason=unknown";
        applyDiscovery(ended);
        return "ok";
    }

    Timer {
        id: deadline
        repeat: false
        onTriggered: root.runPower(Logic.powerEvent(root.op, { type: "deadline" }, root.seen()))
    }

    Timer {
        interval: Logic.DISCOVERY_TICK_MS
        repeat: true
        running: Logic.discoveryTickWanted(root.discovery, root.discoveryContext())
        onTriggered: root.applyDiscovery(Logic.discoveryTick(root.discovery, root.discoveryContext()))
    }

    // A command that fails to start emits only runningChanged, so each end
    // is read there: no exit recorded is a failed start (runtime-qml.md).
    Process {
        id: reader
        property var completion: null
        property bool again: false
        command: ["rfkill", "-J"]
        stdout: StdioCollector { id: readOutput }
        onExited: (code, status) => { reader.completion = { code: code }; }
        onRunningChanged: {
            if (running) return;
            const code = reader.completion === null ? -1 : reader.completion.code;
            const reading = Logic.rfkillReading(code, readOutput.text);
            if (reading.state === "failed") console.warn("bluetooth: rfkill read " + reading.reason);
            root.rfkill = reading;
            if (reader.again) {
                reader.again = false;
                root.readRfkill();
            }
        }
    }

    Process {
        id: writer
        property string verb: ""
        property var completion: null
        stderr: StdioCollector { id: writeErrors }
        onExited: (code, status) => { writer.completion = { code: code }; }
        onRunningChanged: {
            if (running) return;
            const code = writer.completion === null ? -1 : writer.completion.code;
            if (code !== 0) console.warn("bluetooth: rfkill " + writer.verb + " exit=" + code + " " + writeErrors.text.trim());
            root.runPower(Logic.powerEvent(root.op, { type: "rfkill-exit", code: code }, root.seen()));
        }
    }
}
