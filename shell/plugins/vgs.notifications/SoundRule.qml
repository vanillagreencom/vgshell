import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Commons
import "NotificationLogic.js" as Logic

// SoundRule owns install orchestration and the rule's version/held observer.
// sound-rule-install.sh owns filesystem validation, migration and writes.
// PipeWire and WirePlumber read the installed drop-ins only when they start
// (WirePlumber 0.5 daemon/configuration/modifying_configuration: the
// configuration file is only read at startup; pipewire.conf(5): the daemon
// creates context.objects at startup), so a new or updated rule loads at the
// next normal start of the user's audio services. Nothing here restarts
// them: a restart drops every live call's devices (VGS-2231).
// Hold intent lives in PipeWire and needs no rule-return event or
// republish. The existing watcher only reports rule availability.
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
    readonly property var installPaths: [configHome, dataHome, stateHome, Quickshell.env("HOME")]
    property string problem: ""

    // The install's step: installing, reading, installed (the rule ran at
    // this version), pending (the audio services last started before these
    // files and load the rule at their next start), absent (they started
    // with these files and did not load it, problem not-loaded),
    // unavailable (the install was refused) or failed (a read failed).
    // `phase` reads running whenever the rule runs.
    property string step: "installing"
    readonly property string phase: running ? "running" : step
    property string version: ""
    // The version the rule's metadata reports, "" while none does.
    property string observed: ""
    // Actual rule-held object.serial values, forwarded to AppSounds by Service.
    property var held: []
    readonly property bool running: version !== "" && observed === version
    // Once readiness is observed, a later loss falls back to installed,
    // not the wait for the next start or a load that did not happen.
    onRunningChanged: {
        if (!running || (step !== "pending" && step !== "absent")) return;
        step = "installed";
        problem = "";
    }
    // The shipped script's text, null until read.
    property var shipped: null

    function state() {
        return { phase: phase, version: version, problem: problem };
    }

    function stop(line) {
        problem = line;
        step = "failed";
        console.info("notifications: sound rule: " + line);
    }

    function install() {
        if (step !== "installing" || shipped === null) return;
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
        // The watcher may see the rule before this snapshot does.
        if (found.version === version || running) {
            step = "installed";
            return;
        }
        settle.restart();
    }

    // Judge a rule that is not running: pending while the audio services
    // last started before these files, not loaded once they started with
    // them.
    function judge(result) {
        if (running) {
            step = "installed";
        } else if (result === "waiting") {
            step = "pending";
            console.info("notifications: sound rule: pending version=" + version);
        } else {
            problem = "not-loaded";
            step = "absent";
            console.info("notifications: sound rule: not-loaded version=" + version + " started=after-files");
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

    // pw-dump needs the program path and the session's PipeWire alone;
    // under clearEnvironment a null value passes the shell's own value
    // through (Quickshell 0.3.1, Process.clearEnvironment).
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

    // WirePlumber loads its scripts after its unit starts, so a read at
    // sign-in can come before the rule publishes its version.
    Timer {
        id: settle
        interval: Logic.RULE_GRACE
        onTriggered: {
            if (rule.running) rule.step = "installed";
            else startCheck.running = true;
        }
    }

    // Reads the files' times and the services' start times and starts no
    // job; systemctl needs the program path and the session bus (Quickshell
    // 0.3.1, Process.clearEnvironment).
    Process {
        id: startCheck
        property var completion: null
        command: ["bash", rule.helperPath, "started"].concat(rule.installPaths)
        clearEnvironment: true
        environment: ({ PATH: null, XDG_RUNTIME_DIR: null, DBUS_SESSION_BUS_ADDRESS: null, LANG: "C.UTF-8" })
        stdout: StdioCollector { id: startedResult }
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const done = completion;
            completion = null;
            const result = startedResult.text.trim();
            if (done === null || done.code !== 0 || (result !== "started" && result !== "waiting")) {
                rule.stop("start-check=failed result=" + JSON.stringify(result) + " exit=" + JSON.stringify(done));
                return;
            }
            rule.judge(result);
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
