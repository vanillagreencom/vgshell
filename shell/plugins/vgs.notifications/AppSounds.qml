import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import "NotificationLogic.js" as Logic

// An app's own notification sound, muted while the shell plays none of its
// own: the service creates this while Do Not Disturb is on or Sound is off
// and destroys it when both turn back or the service goes.
//
// Two layers. The sound rule (wireplumber/vgs-notification-sounds.lua),
// while WirePlumber runs it (`ruleRunning`), holds every new output stream
// the hold names silent before it links it, so the chime's first sample is
// silent however late the shell reacts; this writes that hold, naming the
// apps of every notification the service keeps or arms, and the rule
// keeps it only while this instance's writer lives. The shell keeps a
// stream the rule held muted while it waits for its app's notification,
// which can reach the shell after the chime starts, and frees it once the
// arm's time passes with none, as a call. Every other stream keeps the
// reaction: `arm` names the app of a notification that arrived, and a
// stream of that app that then starts to play is muted until it pauses.
// A muted stream that pauses stays muted until it plays again, so a chime
// the app plays on a stream it keeps open is silent from its first sample
// too (NotificationLogic.appSoundStep).
//
// The mute is the stream's softMute: WirePlumber 0.5 keeps a stream's
// `mute` and volumes for every later stream of the same app
// (state-stream.lua, keyed by media.role, else application.name), so a
// plain mute of Slack's chime would mute its next call, and it keeps no
// softMute. Any write of the stream's `mute` mixes the stream at its own
// volume and mute again, though its softMute still reads true; a write
// of `softMute: false` alone, or with the mute in the same write, leaves
// it mixed at full volume whatever its own volume. So the lift is two
// writes: softMute false, then the mute the stream already has, which
// leaves both reading false at its own level (measured on a private
// PipeWire 1.6.9 and WirePlumber 0.5.18 with stand-in streams, VGS-1311,
// and with a stream at channel volume 0.5, VGS-1424). A volume written to
// a held stream lifts its softMute the same way, so it is muted again.
// The destruction lifts every stream this instance wrote to. A shell
// stopped by a signal runs no destruction, but its writer dies with it,
// so the rule lifts what it held; the next instance's first scan lifts
// what the reaction left, and a shell that does not start again leaves
// that stream muted until its app closes it.
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
    // The output streams of the last snapshot, each { node, since, judged,
    // freeing, wrote }, bound so their properties stay current: judged once
    // the rule's verdict on it was read, freeing while the shell's own
    // stream the rule held waits for its link to be freed, wrote once this
    // instance wrote to it. A snapshot, never a binding on the live model,
    // as vgs.sound's Audio.qml explains.
    property var streams: []
    // Node id -> { node, hold, level }: the streams under a mute; hold is
    // appSoundStep's answer, kept whole for its next step; level is the
    // volume the stream last reported, so only a change mutes it again.
    property var holds: ({})
    // The writes made while the writer is not ready, each { node, on }, the
    // last for each stream that is still there.
    property var pending: []
    // Whether the running writer has its session's objects
    // (NotificationLogic.cliReady): a write it reads before is refused.
    property bool writerReady: false
    // The hold as last sent to the rule, { at, apps, roles }, at when the
    // first write for this rule and this writer started; null while none
    // is sent. A stream that appears once a write started counts as held
    // before the write lands: the shell writes the mute of a stream it
    // counts as held itself, so one the rule did not hold is muted the same.
    property var ruleHold: null
    // none, sending, confirmed (pw-metadata exited 0 for the current
    // writer's pid) or failed (the retries ran out).
    property string holdState: "none"
    property int holdTries: 0
    // The start-up scan has lifted what an earlier shell left, so a stream
    // the rule holds under this instance's hold is never taken for one.
    property bool scanned: false
    // The apps the hold names: every name a kept or armed notification goes
    // by, as bounded as what the service keeps.
    readonly property var holdNames: Logic.holdApps(kept, Object.keys(arms))
    onHoldNamesChanged: {
        if (ruleHold !== null && Logic.holdGrows(ruleHold.apps, holdNames)) writeHold(false);
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
        holdState = "none";
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

    function level(node) {
        const audio = node.audio;
        return audio === null ? "" : JSON.stringify([audio.volumes, audio.muted]);
    }

    // The latest arm of the app NODE belongs to, or null.
    function armOf(node) {
        let latest = null;
        for (const app of Object.keys(arms))
            if (Logic.streamOfApps(props(node), [app]) && (latest === null || arms[app].at > latest.at)) latest = arms[app];
        return latest;
    }

    // OPEN includes a paused stream present when the hold is written:
    // the rule adopts it then, although it predates the hold.
    function judge(node, open) {
        const entry = streams.find(e => e.node === node);
        if (entry === undefined) return;
        let ruled = "";
        if ((!entry.judged || open === true) && Object.keys(props(node)).length > 0) {
            entry.judged = true;
            ruled = Logic.ruleHeld(ruleHold, props(node), open === true ? ruleHold.at : entry.since, Logic.shellPlayer(props(node), shellSounds));
        }
        const id = String(node.id);
        const held = Logic.hasOwn(holds, id) && holds[id].node === node ? holds[id] : null;
        const step = Logic.appSoundStep(held === null ? null : held.hold, armOf(node),
            { corked: corked(node), since: entry.since }, Date.now(), ruled);
        if (step.change === "") return;
        const next = Object.assign({}, holds);
        if (step.hold === null) delete next[id];
        else next[id] = { node: node, hold: step.hold, level: level(node) };
        holds = next;
        entry.freeing = step.change === "release" && ruled !== "";
        if (entry.freeing) freeLinked();
        else soften(node, step.change !== "release");
        schedule();
    }

    // A stream the rule held as the shell's own is freed once it is
    // linked: WirePlumber sends the rule's softMute before it links the
    // stream, on its one connection, so a lift written once the link shows
    // reaches the stream after that mute. One written as soon as the
    // stream shows can reach it first and leave it muted: the shell judged
    // a stream within the same millisecond as the rule held it (nested
    // sandbox, WirePlumber 0.5.18, VGS-1424).
    function freeLinked() {
        const linked = Pipewire.linkGroups.values.filter(g => g !== null).map(g => g.source);
        for (const entry of streams) {
            if (!entry.freeing || linked.indexOf(entry.node) === -1) continue;
            entry.freeing = false;
            soften(entry.node, false);
        }
    }

    // A held stream whose volume changed has lost its mute.
    function levelChanged(node) {
        const id = String(node.id);
        if (!Logic.hasOwn(holds, id) || holds[id].node !== node || holds[id].level === level(node)) return;
        holds[id].level = level(node);
        soften(node, true);
    }

    function refresh() {
        const now = Date.now();
        const nodes = Pipewire.nodes.values.filter(n => n !== null && n.isStream && n.isSink && n.audio !== null);
        streams = nodes.map(n => {
            const known = root.streams.find(e => e.node === n);
            return known === undefined ? { node: n, since: now, judged: false, freeing: false, wrote: false } : known;
        });
        const next = {};
        for (const id of Object.keys(holds))
            if (nodes.indexOf(holds[id].node) !== -1) next[id] = holds[id];
        holds = next;
        pending = pending.filter(i => nodes.indexOf(i.node) !== -1);
        for (const entry of streams) judge(entry.node);
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

    // The writer's lines for node ID: ON mutes it; otherwise the lift,
    // softMute false and then MUTED, the stream's own mute.
    function softLines(id, on, muted) {
        const set = "set-param " + id + " Props ";
        return on ? [set + "{ softMute: true }"] : [set + "{ softMute: false }", set + ownProps(muted)];
    }

    function ownProps(muted) {
        return muted ? "{ mute: true }" : "{ mute: false }";
    }

    function ownMute(node) {
        return node.audio !== null && node.audio.muted;
    }

    // The core's sound player's directory (Sounds.qml): a stream playing a
    // file of it is the shell's own sound (NotificationLogic.shellPlayer).
    readonly property string shellSounds: Quickshell.shellDir + "/assets/sounds"

    // A node PipeWire removed meanwhile is skipped: its id may already name
    // another stream.
    function soften(node, on) {
        if (!writer.running || !writerReady) {
            pending = pending.filter(i => i.node !== node).concat([{ node: node, on: on }]);
            return;
        }
        if (!Pipewire.nodes.values.includes(node)) return;
        const entry = streams.find(e => e.node === node);
        if (entry !== undefined) entry.wrote = true;
        writer.write(softLines(node.id, on, ownMute(node)).join("\n") + "\n");
    }

    // The hold names this instance's writer, once it runs, WirePlumber runs
    // the rule and the scan is done. FRESH starts a new hold, as for a new
    // writer or a rule that came back; otherwise a hold written again keeps
    // the time of its first write.
    function writeHold(fresh) {
        if (fresh) ruleHold = null;
        if (!ruleRunning || !writer.running || !scanned) return;
        if (ruleHold === null) holdTries = 0;
        ruleHold = { at: ruleHold === null ? Date.now() : ruleHold.at, apps: holdNames, roles: Logic.HOLD_ROLES };
        // A playing call keeps playing; an already-open paused chime
        // enters the same rest phase as one the rule held when it opened.
        for (const entry of streams)
            if (corked(entry.node) === true) judge(entry.node, true);
        holdState = "sending";
        holdRetry.stop();
        if (holdWriter.running) holdWriter.again = true;
        else holdWriter.send();
    }

    // Existing streams have one adoption decision, above. The rule only
    // registers these for writer-death cleanup; another mute on metadata
    // arrival could land after this instance already released the stream.
    function holdEntry(pid) {
        const entry = JSON.parse(Logic.holdEntry(pid, ruleHold.apps));
        // PipeWire's object.serial increments per object, unlike reusable
        // node ids (https://docs.pipewire.org/group__pw__keys.html).
        entry.streams = Object.keys(holds).map(id => props(holds[id].node)["object.serial"]);
        return JSON.stringify(entry);
    }

    // A write that failed is sent again after the supervision's delays;
    // once they run out the hold stays unconfirmed and the shell mutes by
    // reaction alone.
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

    // TEXT is pw-dump's answer. A soft mute on an output stream that this
    // instance does not hold is one a shell that stopped left: nothing else
    // sets a stream's softMute, since pipewire-pulse and WirePlumber write
    // `mute`, and the rule lifts what it held when that shell's writer
    // died. A stream a destruction lifted with its mute alone still reads
    // softMute true, so it is lifted again, which changes nothing.
    function lift(text) {
        let objects;
        try {
            objects = JSON.parse(text);
        } catch (e) {
            console.warn("notifications: app sounds: scan json=" + e.message);
            return;
        }
        for (const o of objects) {
            const info = o.info || {};
            const params = (info.params || {}).Props || [];
            if ((info.props || {})["media.class"] !== "Stream/Output/Audio" || !params.some(p => p.softMute === true)) continue;
            if (Logic.hasOwn(holds, String(o.id))) continue;
            const node = Pipewire.nodes.values.find(n => n !== null && n.id === o.id);
            if (node !== undefined) soften(node, false);
        }
    }

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

    Connections {
        target: Pipewire.linkGroups
        function onValuesChanged() { Qt.callLater(root.freeLinked); }
    }

    Repeater {
        model: root.streams
        Item {
            required property var modelData
            Connections {
                target: modelData.node
                function onPropertiesChanged() { root.judge(modelData.node); }
            }
            Connections {
                target: modelData.node.audio
                function onVolumesChanged() { root.levelChanged(modelData.node); }
                function onMutedChanged() { root.levelChanged(modelData.node); }
            }
        }
    }

    Timer {
        id: clock
        onTriggered: root.expire()
    }

    // The one pw-cli that takes every softMute write on its stdin, a line
    // each, and whose life is the hold's: the rule counts the hold only
    // while a PipeWire client with this process's pid exists. It cannot
    // outlive the shell and is started again after an exit nobody asked
    // for, such as a PipeWire restart (Supervised.qml). Its output is read
    // until it has its session's objects; then it gets the writes owed
    // meanwhile, every stream this instance still holds is muted again,
    // since the rule lifted what it held when the last writer went, and
    // the hold is written under its pid.
    Supervised {
        id: writer
        label: "app sounds: writer"
        argv: ["pw-cli"]
        stdinEnabled: true
        exitLevel: "warn"
        onLine: text => {
            if (root.writerReady || !Logic.cliReady(text)) return;
            root.writerReady = true;
            const owed = root.pending;
            root.pending = [];
            for (const item of owed) root.soften(item.node, item.on);
            for (const id of Object.keys(root.holds))
                if (!owed.some(i => i.node === root.holds[id].node)) root.soften(root.holds[id].node, true);
        }
        onStarted: root.writeHold(true)
        onEnded: {
            root.writerReady = false;
            root.ruleHold = null;
            root.holdState = "none";
        }
    }

    // One hold write; a write asked while one runs is sent once it ends,
    // with the hold as it then stands. It is guarded like the writer, so a
    // write still under way when the shell dies is not left to land.
    Process {
        id: holdWriter
        property bool again: false
        property var completion: null
        property var sentPid: null
        function send() {
            if (root.ruleHold === null || !writer.running) return;
            sentPid = writer.processId;
            command = Logic.guardedArgv(Quickshell.processId, ["pw-metadata", "-n", Logic.SOUND_RULE_METADATA, "0", "hold", root.holdEntry(sentPid), "Spa:String:JSON"]);
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
        onTriggered: root.writeHold(false)
    }

    // A mute that waits on the rule longer than the grace mutes by reaction
    // alone, which can let a chime's first samples through: said once each
    // time it happens, at warn, naming the rule as not loaded.
    Timer {
        id: ruleGrace
        interval: Logic.RULE_GRACE
        onTriggered: {
            if (!root.ruleRunning) console.warn("notifications: app sounds: rule=not-loaded phase=" + root.rulePhase + " mutes=reaction");
        }
    }

    Process {
        id: scan
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
            if (done === null || done.code !== 0) console.warn("notifications: app sounds: pw-dump exit=" + JSON.stringify(done));
            else root.lift(dumped.text);
            root.scanned = true;
            root.writeHold(true);
        }
    }

    Component.onCompleted: {
        refresh();
        scan.running = true;
        if (!ruleRunning) ruleGrace.start();
    }

    // The writer goes with this instance, SIGKILLed, and may not have
    // reached PipeWire with what it was last given, so every stream this
    // instance wrote to or holds, and every lift still owed, gets a lift of
    // its own. It writes the stream's own mute alone, which mixes it at its
    // own level: two detached processes could land softMute false last and
    // leave it at full volume.
    Component.onDestruction: {
        const owed = streams.filter(e => e.wrote).map(e => e.node).concat(Object.keys(holds).map(id => holds[id].node))
            .concat(pending.filter(i => !i.on).map(i => i.node));
        for (const node of owed.filter((n, i) => owed.indexOf(n) === i))
            if (Pipewire.nodes.values.includes(node)) Quickshell.execDetached(["pw-cli", "set-param", String(node.id), "Props", ownProps(ownMute(node))]);
    }
}
