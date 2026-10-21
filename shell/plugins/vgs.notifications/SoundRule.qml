import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import qs.Commons
import "NotificationLogic.js" as Logic

// The sound rule's install: the WirePlumber script wireplumber/
// vgs-notification-sounds.lua, which holds an app's own notification sound
// silent from its first sample while AppSounds asks for it. The service
// builds this when it starts, never on a mute toggle. It copies the script
// into WirePlumber's user scripts directory and writes the one
// configuration fragment that loads that copy by its absolute path, each
// only when absent or different: the plugin runs from a snapshot under
// the session's runtime directory (Registry.qml, `sourceDir`), which a
// later login's WirePlumber, started before the shell, would not find.
//
// Whether WirePlumber runs the rule is observed, not read once: `running`
// is true while the rule's metadata reports this script's version, and
// follows WirePlumber as it restarts or loads the rule late in a login.
// Two watchers observe it (Supervised.qml): `pw-metadata -m` reports the
// metadata's entries as they change, but stays bound to a metadata a
// WirePlumber restart removed, and `pw-dump -m` reports that removal at
// once but the next object only with a later event, so the removal starts
// pw-metadata again, which waits for the new one (measured on PipeWire
// 1.6.9 and WirePlumber 0.5.18 in the nested sandbox, VGS-1424).
//
// After the install it reads the rule once: not running at this version,
// and no marker beside the service's state file naming the version, it
// restarts WirePlumber once for it, the marker written first. A rule that
// does not come up, or a version already restarted for, leaves the phase
// `absent` while the watchers go on: the rule turns running whenever
// WirePlumber loads it. Each step logs one keyed info line; AppSounds
// warns when a mute waits on a rule that is not loaded.
//
// Disabling the plugin, the only removal a bundled plugin has, removes the
// fragment, the copy and the marker (NotificationLogic.soundRuleRemoval):
// the core writes the user configuration before it destroys a plugin it
// disables, so the destruction reads it. A shell that exits or restarts
// keeps them, so the next login's WirePlumber loads the rule.
Item {
    id: rule

    visible: false

    readonly property string pluginId: "vgs.notifications"
    readonly property string shippedPath: String(Qt.resolvedUrl("wireplumber/vgs-notification-sounds.lua")).replace(/^file:\/\//, "")
    readonly property string scriptDir: (Quickshell.env("XDG_DATA_HOME") || (Quickshell.env("HOME") + "/.local/share")) + "/wireplumber/scripts"
    readonly property string scriptPath: scriptDir + "/vgs-notification-sounds.lua"
    readonly property string confDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/wireplumber/wireplumber.conf.d"
    readonly property string confPath: confDir + "/90-vgs-notification-sounds.conf"
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/vgshell/notifications"
    readonly property string markerPath: stateDir + "/sound-rule-restarted"

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
    // The shipped script's text, null until read.
    property var shipped: null
    // The copy's text, "" while there is none; null until read.
    property var copied: null
    // The marker's version, "" while there is none; null until read.
    property var marker: null
    // The fragment's text, "" while there is none; null until read.
    property var installed: null
    // Whether this install wrote the copy and the fragment, for its line.
    property bool copyWritten: false
    property bool fragmentWritten: false

    function state() {
        return { phase: phase, version: version };
    }

    function stop(line) {
        step = "failed";
        console.info("notifications: sound rule: " + line);
    }

    // Each step waits for what it reads: the script, its copy, the
    // fragment and the marker, then the directories.
    function install() {
        if (step !== "installing" || shipped === null || copied === null || installed === null || marker === null) return;
        dirs.running = true;
    }

    // setText skips text equal to what the view holds, and then saves
    // nothing.
    function writeFragment() {
        const fragment = Logic.soundRuleFragment(scriptPath, version);
        if (installed === fragment) written();
        else confFile.setText(fragment);
    }

    // The first read waits for PipeWire, which a login may start after the
    // shell; a read that fails is made again after the supervision's
    // delays.
    function readRule() {
        if (!Pipewire.ready) return;
        reader.running = true;
    }

    function written() {
        console.info("notifications: sound rule: installed version=" + version + " copy=" + (copyWritten ? "written" : "kept") + " fragment=" + (fragmentWritten ? "written" : "kept"));
        step = "reading";
        readRule();
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
            step = "absent";
            console.info("notifications: sound rule: not-loaded version=" + version + " restarted=before running=" + JSON.stringify(found.version));
        } else {
            markerFile.setText(version + "\n");
        }
    }

    function metadataLine(text) {
        const line = Logic.metadataLine(text);
        if (line === null) return;
        if (line.subject === 0 && line.key === "version") observed = line.kind === "update" ? line.value : "";
        else if (line.subject === 0 && line.key === "held") {
            const read = line.kind === "update" ? Logic.soundRuleHeld(line.value) : [];
            held = read === null ? [] : read;
            if (read === null) console.warn("notifications: sound rule: held=invalid");
        } else if (line.kind === "remove" && line.subject === 0 && line.key === null) {
            observed = "";
            held = [];
        }
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
        id: copyFile
        path: rule.scriptPath
        watchChanges: false
        atomicWrites: true
        printErrors: false
        onLoaded: {
            rule.copied = text();
            rule.install();
        }
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound) {
                rule.stop("copy=unreadable path=" + rule.scriptPath + " error=" + FileViewError.toString(error));
                return;
            }
            rule.copied = "";
            rule.install();
        }
        onSaved: {
            rule.copyWritten = true;
            rule.writeFragment();
        }
        onSaveFailed: error => rule.stop("copy=failed path=" + rule.scriptPath + " error=" + FileViewError.toString(error))
    }

    FileView {
        id: confFile
        path: rule.confPath
        watchChanges: false
        atomicWrites: true
        printErrors: false
        onLoaded: {
            rule.installed = text();
            rule.install();
        }
        onLoadFailed: error => {
            if (error !== FileViewError.FileNotFound) {
                rule.stop("fragment=unreadable path=" + rule.confPath + " error=" + FileViewError.toString(error));
                return;
            }
            rule.installed = "";
            rule.install();
        }
        onSaved: {
            rule.fragmentWritten = true;
            rule.written();
        }
        onSaveFailed: error => rule.stop("fragment=failed path=" + rule.confPath + " error=" + FileViewError.toString(error))
    }

    FileView {
        id: markerFile
        path: rule.markerPath
        watchChanges: false
        atomicWrites: true
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
        // The marker is written before the restart, so a restart that ends
        // the shell or fails is never asked twice for one version.
        onSaved: {
            rule.step = "restarting";
            restart.running = true;
        }
        onSaveFailed: error => rule.stop("marker=failed path=" + rule.markerPath + " error=" + FileViewError.toString(error))
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

    // FileView writes into a directory that exists; the copy's, the
    // fragment's and the marker's are made first.
    Process {
        id: dirs
        property var completion: null
        command: ["mkdir", "-p", "--", rule.scriptDir, rule.confDir, rule.stateDir]
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const done = completion;
            completion = null;
            if (done === null || done.code !== 0) {
                rule.stop("directories=failed exit=" + JSON.stringify(done));
                return;
            }
            if (rule.copied === rule.shipped) rule.writeFragment();
            else copyFile.setText(rule.shipped);
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
        command: ["systemctl", "--user", "restart", "wireplumber.service"]
        clearEnvironment: true
        environment: ({ PATH: null, XDG_RUNTIME_DIR: null, DBUS_SESSION_BUS_ADDRESS: null, LANG: "C.UTF-8" })
        stderr: StdioCollector { id: restartErr }
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const done = completion;
            completion = null;
            if (done === null || done.code !== 0) {
                rule.step = "absent";
                console.info("notifications: sound rule: restart=failed version=" + rule.version + " exit=" + JSON.stringify(done) + " " + restartErr.text.trim().split("\n")[0]);
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
    // loaded, and the watchers go on.
    Timer {
        id: settle
        interval: Logic.RULE_GRACE
        onTriggered: {
            if (rule.running) return;
            rule.step = "absent";
            console.info("notifications: sound rule: not-loaded version=" + rule.version + " after=restart");
        }
    }

    Supervised {
        id: metadataWatch
        label: "sound rule: metadata watch"
        argv: ["pw-metadata", "-m", "-n", Logic.SOUND_RULE_METADATA]
        onLine: text => rule.metadataLine(text)
        onStarted: { rule.observed = ""; rule.held = []; }
        onEnded: { rule.observed = ""; rule.held = []; }
    }

    // pw-dump filters removals by the rule's name. Its removal can arrive
    // before pw-metadata reports the object's id, so it must not wait for
    // that other process's line before starting pw-metadata again.
    Supervised {
        id: removalWatch
        property int last: 0
        label: "sound rule: removal watch"
        argv: ["pw-dump", "-m", "-N", Logic.SOUND_RULE_METADATA]
        onLine: text => {
            const read = Logic.dumpLine(last, text);
            last = read.last;
            if (read.removed === 0) return;
            rule.observed = "";
            rule.held = [];
            metadataWatch.relaunch();
        }
        onStarted: last = 0
    }

    Component.onDestruction: {
        // The view holds the text it read when it was built; reload and
        // waitForJob read the file as it is now (measured: without them
        // the disable read the cached text, VGS-1424).
        userConfig.reload();
        userConfig.waitForJob();
        if (!Logic.disabledIn(userConfig.text(), pluginId)) return;
        console.info("notifications: sound rule: remove=disabled fragment=" + confPath);
        Quickshell.execDetached(Logic.soundRuleRemoval(confPath, scriptPath, markerPath));
    }
}
