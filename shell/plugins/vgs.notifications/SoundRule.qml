import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Commons
import "NotificationLogic.js" as Logic

// SoundRule owns install orchestration and the rule's version/held observer.
// sound-rule-install.sh owns filesystem validation, migration and writes.
// One marker precedes the daemon-store bootstrap; later Lua updates restart
// WirePlumber alone. Hold intent lives in PipeWire and needs no rule-return
// event or republish. The existing watcher only reports rule availability.
Item {
    id: rule

    visible: false

    readonly property string pluginId: "vgs.notifications"
    readonly property string shippedPath: String(Qt.resolvedUrl("wireplumber/vgs-notification-sounds.lua")).replace(/^file:\/\//, "")
    readonly property string helperPath: String(Qt.resolvedUrl("sound-rule-install.sh")).replace(/^file:\/\//, "")
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    readonly property string dataHome: Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")
    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")
    readonly property string scriptPath: dataHome + "/wireplumber/scripts/vgs-notification-sounds.lua"
    readonly property string markerPath: stateHome + "/vgshell/notifications/sound-rule-store-restarted"
    readonly property var installPaths: [configHome, dataHome, stateHome, Quickshell.env("HOME")]
    property bool bootstrap: false
    property string problem: ""

    // The install's step: installing, reading, installed (the read found
    // the rule running), restarting, absent (the
    // rule is not loaded, after its one restart or a failed one) or failed
    // (a file or a read failed). `phase` reads running whenever the rule
    // runs.
    property string step: "installing"
    readonly property string phase: running ? "running" : step
    property string version: ""
    // The version the rule's metadata reports, "" while none does.
    property string observed: ""
    // Actual rule-held object.serial values, forwarded to AppSounds by Service.
    property var held: []
    readonly property bool running: version !== "" && observed === version
    // Once readiness is observed, a later loss falls back to installed,
    // not the completed restart's activation state.
    onRunningChanged: {
        if (running && step === "restarting") step = "installed";
    }
    // The shipped script's text, null until read.
    property var shipped: null
    // Empty while no new-format activation marker exists; null until read.
    property var marker: null

    function state() {
        return { phase: phase, version: version, problem: problem };
    }

    function stop(line) {
        problem = line;
        step = "failed";
        console.info("notifications: sound rule: " + line);
    }

    function install() {
        if (step !== "installing" || shipped === null || marker === null) return;
        installer.running = true;
    }

    // The first read waits for PipeWire, which a login may start after the
    // shell; a read that fails is made again after the supervision's
    // delays.
    function readRule() {
        if (!Pipewire.ready) return;
        reader.running = true;
    }

    function read(text) {
        const found = Logic.soundRuleRunning(text);
        if (!found.ok) {
            stop("read=failed error=" + found.error);
            return;
        }
        const next = Logic.soundRuleStep(version, found.version, marker);
        if (next === "running") {
            step = "installed";
        } else if (next === "absent") {
            problem = "not-loaded";
            step = "absent";
            console.info("notifications: sound rule: not-loaded version=" + version + " restarted=before running=" + JSON.stringify(found.version));
        } else {
            bootstrap = next === "bootstrap";
            markerWriter.running = true;
        }
    }

    // SplitParser delivers newline chunks (Quickshell 0.3.1,
    // https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/SplitParser).
    // pw-dump 1.6.9 frames each update as an unindented JSON array; entries
    // are deltas, so only a new object or its removal resets prior state.
    function dumpLine(text) {
        if (text === "[") {
            metadataWatch.pending = text;
            return;
        }
        if (metadataWatch.pending === "") return;
        metadataWatch.pending += "\n" + text;
        if (text !== "]") return;
        const batch = metadataWatch.pending;
        metadataWatch.pending = "";
        const read = Logic.soundRuleUpdate({ id: metadataWatch.metadataId, version: observed, held: held }, batch);
        if (!read.ok) {
            observed = "";
            held = [];
            stop("watch=invalid error=" + read.error);
            return;
        }
        metadataWatch.metadataId = read.id;
        observed = read.version;
        held = read.held;
        if (read.invalidHeld) console.warn("notifications: sound rule: held=invalid");
    }

    FileView {
        id: shippedFile
        path: rule.shippedPath
        watchChanges: false
        printErrors: false
        onLoaded: {
            rule.shipped = text();
            rule.version = Logic.soundRuleVersion(rule.shipped);
            rule.install();
        }
        onLoadFailed: error => rule.stop("script=unreadable path=" + rule.shippedPath + " error=" + FileViewError.toString(error))
    }

    FileView {
        id: markerFile
        path: rule.markerPath
        watchChanges: false
        printErrors: false
        onLoaded: {
            rule.marker = text().trim();
            rule.install();
        }
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound) {
                rule.stop("marker=unreadable path=" + rule.markerPath + " error=" + FileViewError.toString(error));
                return;
            }
            rule.marker = "";
            rule.install();
        }
    }

    // The user configuration as the core persists it, read when the
    // service goes.
    FileView {
        id: userConfig
        path: Paths.configDir + "/shell.json"
        blockLoading: true
        watchChanges: false
        printErrors: false
    }

    // Process.clearEnvironment passes only these inherited values when null
    // (Quickshell 0.3.1, https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/Process).
    Process {
        id: installer
        property var completion: null
        command: ["bash", rule.helperPath, "install"].concat(rule.installPaths,
            [rule.shippedPath, rule.version, Logic.soundRuleFragment(rule.scriptPath, rule.version), Logic.soundHoldFragment()])
        clearEnvironment: true
        environment: ({ PATH: null, HOME: null, XDG_RUNTIME_DIR: null, DBUS_SESSION_BUS_ADDRESS: null, LANG: "C.UTF-8" })
        stdout: StdioCollector { id: installedResult }
        stderr: StdioCollector { id: installErr }
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const done = completion;
            completion = null;
            const result = installedResult.text.trim();
            if (done === null || done.code !== 0 || result !== "installed") {
                rule.problem = result.startsWith("unsupported:") ? result.slice("unsupported:".length) : "install";
                rule.step = "unavailable";
                console.info("notifications: sound rule: install=unavailable reason=" + rule.problem + " exit=" + JSON.stringify(done) + " " + installErr.text.trim());
                return;
            }
            rule.step = "reading";
            rule.readRule();
        }
    }

    Process {
        id: markerWriter
        property var completion: null
        command: ["bash", rule.helperPath, "mark"].concat(rule.installPaths, [rule.version])
        clearEnvironment: true
        environment: ({ PATH: null, HOME: null, LANG: "C.UTF-8" })
        stdout: StdioCollector { id: markedResult }
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const done = completion;
            completion = null;
            if (done === null || done.code !== 0 || markedResult.text.trim() !== "marked") {
                rule.stop("marker=failed exit=" + JSON.stringify(done));
                return;
            }
            rule.marker = "hold-store-v1 " + rule.version;
            rule.step = "restarting";
            restart.running = true;
        }
    }

    // pw-dump and systemctl need the program path and the session's
    // PipeWire or bus alone; under clearEnvironment a null value passes the
    // shell's own value through (Quickshell 0.3.1, Process.clearEnvironment).
    Process {
        id: reader
        property var completion: null
        command: ["pw-dump"]
        clearEnvironment: true
        environment: ({ PATH: null, XDG_RUNTIME_DIR: null, PIPEWIRE_RUNTIME_DIR: null, PIPEWIRE_REMOTE: null, LANG: "C.UTF-8" })
        stdout: StdioCollector { id: dumped }
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const done = completion;
            completion = null;
            if (done !== null && done.code === 0) {
                rule.read(dumped.text);
                return;
            }
            const next = Logic.restartStep(readRetry.tries, 0);
            readRetry.tries = next.streak;
            if (next.delay < 0) {
                rule.stop("read=failed exit=" + JSON.stringify(done));
                return;
            }
            readRetry.interval = next.delay;
            readRetry.restart();
        }
    }

    Process {
        id: restart
        property var completion: null
        command: rule.bootstrap ? ["systemctl", "--user", "restart", "pipewire.service"] : ["systemctl", "--user", "restart", "wireplumber.service"]
        clearEnvironment: true
        environment: ({ PATH: null, XDG_RUNTIME_DIR: null, DBUS_SESSION_BUS_ADDRESS: null, LANG: "C.UTF-8" })
        stderr: StdioCollector { id: restartErr }
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const done = completion;
            completion = null;
            if (done === null || done.code !== 0) {
                rule.problem = "restart";
                rule.step = "absent";
                console.info("notifications: sound rule: restart=failed version=" + rule.version + " exit=" + JSON.stringify(done) + " " + restartErr.text.trim().split("\n")[0]);
                return;
            }
            if (rule.bootstrap) resumer.running = true;
            else settle.restart();
        }
    }

    // WirePlumber BindsTo PipeWire, so restarting the daemon may stop it.
    // Start it only after the daemon's restart job completed (WP 0.5.18,
    // src/systemd/user/wireplumber.service.in: BindsTo/After=pipewire.service).
    Process {
        id: resumer
        property var completion: null
        command: ["systemctl", "--user", "start", "wireplumber.service"]
        clearEnvironment: true
        environment: ({ PATH: null, XDG_RUNTIME_DIR: null, DBUS_SESSION_BUS_ADDRESS: null, LANG: "C.UTF-8" })
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const done = completion;
            completion = null;
            if (done === null || done.code !== 0) {
                rule.problem = "restart";
                rule.step = "absent";
                console.info("notifications: sound rule: resume=failed exit=" + JSON.stringify(done));
                return;
            }
            settle.restart();
        }
    }

    Timer {
        id: readRetry
        property int tries: 0
        onTriggered: rule.readRule()
    }

    Connections {
        target: Pipewire
        function onReadyChanged() {
            if (Pipewire.ready && rule.step === "reading" && !reader.running && !readRetry.running) rule.readRule();
        }
    }

    // systemctl returns once the unit has started, and WirePlumber loads
    // its scripts after that: a rule not seen within the grace is not
    // loaded, and the watcher goes on.
    Timer {
        id: settle
        interval: Logic.RULE_GRACE
        onTriggered: {
            if (rule.running) return;
            rule.problem = "not-loaded";
            rule.step = "absent";
            console.info("notifications: sound rule: not-loaded version=" + rule.version + " after=restart");
        }
    }

    Supervised {
        id: metadataWatch
        property string pending: ""
        property int metadataId: 0
        label: "sound rule: metadata watch"
        argv: ["pw-dump", "-m", "-N", Logic.SOUND_RULE_METADATA]
        onLine: text => rule.dumpLine(text)
        onStarted: { pending = ""; metadataId = 0; rule.observed = ""; rule.held = []; }
        onEnded: { pending = ""; metadataId = 0; rule.observed = ""; rule.held = []; }
    }

    Component.onDestruction: {
        // The view holds the text it read when it was built; reload and
        // waitForJob read the file as it is now (measured: without them
        // the disable read the cached text, VGS-1424).
        userConfig.reload();
        userConfig.waitForJob();
        if (!Logic.disabledIn(userConfig.text(), pluginId)) return;
        console.info("notifications: sound rule: remove=disabled");
        Quickshell.execDetached(["bash", helperPath, "remove"].concat(installPaths));
    }
}
