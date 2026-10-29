import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "NotificationLogic.js" as Logic

// The rule routes a notification stream to its private silent output. This
// instance publishes the complete held/released serial sets; it never changes
// the stream's volume, mute or saved target. A pw-cli client leases
// the hold, so destroying this instance or losing its writer frees the routes.
// appSoundStep keeps a chime held across pauses and frees a possible call
// once its notification wait expires. The rule's actual held serials, observed
// by SoundRule, distinguish a new rule-held stream from an existing call.
Item {
    id: root

    visible: false

    // Whether WirePlumber runs the sound rule at the shipped version
    // (SoundRule.running) and the install's phase, and the notifications
    // the service keeps, live and history, whose apps the hold names.
    property bool ruleRunning: false
    property string rulePhase: ""
    property var kept: []

    // App name -> { at, until }: the apps a notification armed lately.
    property var arms: ({})
    // Snapshot entries retain their first paused/playing admission observation.
    // Preexisting streams were observed before this lease; playing ones stay
    // free, while matching paused ones can be adopted before their next play.
    property var streams: []
    property bool initialized: false
    // object.serial -> { node, hold }, retaining appSoundStep's phase.
    property var holds: ({})
    property var ruleHeldSerials: []
    // Current broad admission policy, null without a running rule and writer.
    property var ruleHold: null
    property string holdState: "none"
    property int holdTries: 0
    property string lastHold: ""
    onRuleHeldSerialsChanged: {
        for (const entry of streams) judge(entry.node);
    }
    // The apps the hold names: every name a kept or armed notification goes
    // by, as bounded as what the service keeps.
    readonly property var holdNames: Logic.holdApps(kept, Object.keys(arms))
    onHoldNamesChanged: {
        writeHold(false);
    }
    // The rule holds nothing of an earlier instance's or an earlier
    // WirePlumber's: a rule that comes back gets the hold again, and one
    // that goes takes the hold with it.
    onRuleRunningChanged: {
        if (ruleRunning) {
            writeHold(true);
            return;
        }
        ruleHold = null;
        lastHold = "";
        holdState = "none";
        holdRetry.stop();
        ruleGrace.restart();
    }

    // The app of a notification that arrived: its streams that start to
    // play in the next APP_SOUND_ARM ms are muted.
    function arm(desktopEntry, appName) {
        const now = Date.now();
        const next = Object.assign({}, arms);
        for (const app of Logic.soundApps(desktopEntry, appName)) next[app] = { at: now, until: now + Logic.APP_SOUND_ARM };
        arms = next;
        for (const entry of streams) judge(entry.node);
    }

    // What the service's status reports: the node names of the streams
    // under a mute.
    function state() {
        return { held: Object.keys(holds).map(id => String(holds[id].node.name)).sort(), hold: holdState, writer: writer.processId };
    }

    function props(node) {
        const p = node.properties;
        return p !== null && p !== undefined ? p : {};
    }

    // Quickshell hands node properties over as PipeWire's strings.
    function corked(node) {
        const value = props(node)["pulse.corked"];
        return value === "true" ? true : value === "false" ? false : null;
    }

    // The latest arm of the app NODE belongs to, or null.
    function armOf(node) {
        let latest = null;
        for (const app of Object.keys(arms))
            if (Logic.streamOfApps(props(node), [app]) && (latest === null || arms[app].at > latest.at)) latest = arms[app];
        return latest;
    }

    // Admission stays pending through node-list, identity and cork-state
    // delivery. Its first matching paused/playing observation settles it,
    // so a known call is not adopted when it later pauses or another app joins.
    // An unjudged new stream is not released before the rule reports it held:
    // its node-added hook may still be queued on WirePlumber's event loop.
    function judge(node) {
        const entry = streams.find(e => e.node === node);
        if (entry === undefined || !node.ready) return;
        const p = props(node);
        const serial = p["object.serial"];
        if (typeof serial !== "string" || serial === "" || Object.keys(p).length === 0) return;
        if (entry.serial === "") entry.serial = serial;
        if (entry.serial !== serial) return;
        const own = Logic.shellPlayer(p, shellSounds);
        const paused = corked(node);
        let ruled = own ? "own" : "";
        if (!entry.judged && !own) {
            ruled = Logic.ruleHeld(ruleHeldSerials, p, own);
            if (ruled !== "" || (entry.preexisting && paused !== null) || (ruleHold !== null && !Logic.holdMatches(ruleHold, p))) entry.judged = true;
        }
        if (ruleHold !== null && entry.admission === "waiting" && paused !== null && Logic.holdMatches(ruleHold, p)) {
            entry.admission = paused ? "paused" : "playing";
            if (!own && paused) {
                ruled = Logic.ruleHeld([serial], p, false);
                entry.judged = true;
            }
        }
        const held = Logic.hasOwn(holds, serial) && holds[serial].node === node ? holds[serial] : null;
        const step = Logic.appSoundStep(held === null ? null : held.hold, armOf(node),
            { corked: paused, since: entry.since }, Date.now(), ruled);
        const wasFree = entry.free;
        if (step.change !== "") {
            const next = Object.assign({}, holds);
            if (step.hold === null) delete next[serial];
            else next[serial] = { node: node, hold: step.hold };
            holds = next;
            entry.judged = true;
            entry.free = step.hold === null;
            schedule();
        } else if (held === null && entry.judged) {
            entry.free = true;
        }
        if (step.change !== "" || wasFree !== entry.free) Qt.callLater(root.publishHold);
    }

    function refresh() {
        const now = Date.now();
        const nodes = Pipewire.nodes.values.filter(n => n !== null && n.isStream && n.isSink && n.audio !== null);
        streams = nodes.map(n => {
            const known = root.streams.find(e => e.node === n);
            return known === undefined ? { node: n, serial: "", since: now, preexisting: !initialized, admission: "waiting", judged: false, free: false } : known;
        });
        const next = {};
        for (const id of Object.keys(holds))
            if (nodes.indexOf(holds[id].node) !== -1) next[id] = holds[id];
        holds = next;
        for (const entry of streams) judge(entry.node);
        Qt.callLater(root.publishHold);
    }

    // The clock runs to the nearest end of an arm or a hold.
    function schedule() {
        const now = Date.now();
        const ends = Object.keys(arms).map(a => arms[a].until).concat(Object.keys(holds).map(id => holds[id].hold.until)).filter(t => t > now);
        if (ends.length === 0) {
            clock.stop();
            return;
        }
        clock.interval = Math.max(1, Math.min(...ends) - now);
        clock.restart();
    }

    function expire() {
        const now = Date.now();
        const next = {};
        for (const app of Object.keys(arms)) if (arms[app].until > now) next[app] = arms[app];
        arms = next;
        for (const entry of streams) judge(entry.node);
        schedule();
    }

    // The core's sound player's directory (Sounds.qml): a stream playing a
    // file of it is the shell's own sound (NotificationLogic.shellPlayer).
    readonly property string shellSounds: Quickshell.shellDir + "/assets/sounds"

    function writeHold(fresh) {
        const adopt = fresh || ruleHold === null || holdNames.some(app => !ruleHold.apps.includes(app));
        if (fresh) {
            ruleHold = null;
            lastHold = "";
            holdTries = 0;
        }
        if (!ruleRunning || !writer.running) return;
        ruleHold = { apps: holdNames, roles: Logic.HOLD_ROLES };
        if (adopt) {
            for (const entry of streams) judge(entry.node);
        }
        publishHold();
    }

    // Only observed live identities enter either exact set. PipeWire's
    // object.serial increases per object, unlike reusable node ids
    // (https://docs.pipewire.org/group__pw__keys.html). Release wins while
    // the same app remains broadly admitted, including the shell's sounds.
    function holdEntry(pid) {
        const live = streams.filter(e => e.serial !== "" && Pipewire.nodes.values.includes(e.node));
        const held = live.filter(e => Logic.hasOwn(holds, e.serial) && holds[e.serial].node === e.node).map(e => e.serial);
        const released = live.filter(e => e.free).map(e => e.serial);
        return Logic.holdEntry(pid, ruleHold.apps, held, released);
    }

    // A snapshot replaces both exact sets, including removals. Coalesced
    // calls and readbacks with no changed intent start no new process.
    function publishHold() {
        if (ruleHold === null || !ruleRunning || !writer.running) return;
        const next = holdEntry(writer.processId);
        if (next === lastHold) return;
        lastHold = next;
        holdState = "sending";
        holdRetry.stop();
        if (holdWriter.running) holdWriter.again = true;
        else holdWriter.send();
    }

    // A write that failed is sent again after the supervision's delays;
    // once they run out the hold stays unconfirmed and routing is unproved.
    function holdFailed(line) {
        const step = Logic.restartStep(holdTries, 0);
        holdTries = step.streak;
        console.warn("notifications: app sounds: hold=failed " + line + " retry=" + (step.delay < 0 ? "gave-up" : step.delay + "ms"));
        if (step.delay < 0) {
            holdState = "failed";
            return;
        }
        holdRetry.interval = step.delay;
        holdRetry.restart();
    }

    // Binding exposes full properties once PwNode.ready is true (Quickshell
    // 0.3.1, https://quickshell.org/docs/v0.3.1/types/Quickshell.Services.Pipewire/PwNode).
    PwObjectTracker {
        objects: root.streams.map(e => e.node)
    }

    // Read on the next turn, not inside the change: rebuilding from the
    // removal signal while Quickshell dispatches it has crashed its PipeWire
    // service (vgs.sound's Audio.qml). Not after Audio.qml's 75 ms either: a
    // Slack chime's stream starts to play 75 ms after it opens.
    Connections {
        target: Pipewire.nodes
        function onValuesChanged() { Qt.callLater(root.refresh); }
    }

    Repeater {
        model: root.streams
        Item {
            required property var modelData
            Connections {
                target: modelData.node
                function onPropertiesChanged() { root.judge(modelData.node); }
                function onReadyChanged() { root.judge(modelData.node); }
            }
        }
    }

    Timer {
        id: clock
        onTriggered: root.expire()
    }

    // A PipeWire client whose lifetime leases the hold. Supervised
    // restarts it after a server loss. No stream parameter writes are
    // sent to this client's stdin.
    Supervised {
        id: writer
        label: "app sounds: writer"
        argv: ["pw-cli"]
        stdinEnabled: true
        exitLevel: "warn"
        onStarted: root.writeHold(true)
        onEnded: {
            root.ruleHold = null;
            root.lastHold = "";
            root.holdState = "none";
            holdRetry.stop();
        }
    }

    // One hold write; a write asked while one runs is sent once it ends,
    // with the hold as it then stands. The engine ends a write still under
    // way when the shell dies.
    Process {
        id: holdWriter
        property bool again: false
        property var completion: null
        property var sentPid: null
        function send() {
            if (root.ruleHold === null || !root.ruleRunning || !writer.running) return;
            sentPid = writer.processId;
            command = ["pw-metadata", "-n", Logic.SOUND_RULE_METADATA, "0", "hold", root.holdEntry(sentPid), "Spa:String:JSON"];
            running = true;
        }
        clearEnvironment: true
        environment: ({ PATH: null, XDG_RUNTIME_DIR: null, PIPEWIRE_RUNTIME_DIR: null, PIPEWIRE_REMOTE: null, LANG: "C.UTF-8" })
        stderr: StdioCollector { id: holdErr }
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: {
            if (running) return;
            const done = completion;
            completion = null;
            if (again) {
                again = false;
                send();
                return;
            }
            if (root.ruleHold === null || sentPid !== writer.processId) return;
            if (done !== null && done.code === 0) {
                root.holdState = "confirmed";
                root.holdTries = 0;
            } else {
                root.holdFailed("exit=" + JSON.stringify(done) + " " + holdErr.text.trim().split("\n")[0]);
            }
        }
    }

    Timer {
        id: holdRetry
        onTriggered: {
            root.lastHold = "";
            root.publishHold();
        }
    }

    // Without the rule there is no routing hold. Report the unavailable
    // policy once after its startup grace, including the install phase.
    Timer {
        id: ruleGrace
        interval: Logic.RULE_GRACE
        onTriggered: {
            if (!root.ruleRunning) console.warn("notifications: app sounds: rule=not-loaded phase=" + root.rulePhase + " mutes=unavailable");
        }
    }

    Component.onCompleted: {
        refresh();
        initialized = true;
        writeHold(true);
        if (!ruleRunning) ruleGrace.start();
    }
}
