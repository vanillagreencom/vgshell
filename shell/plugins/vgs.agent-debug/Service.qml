import QtQuick
import Quickshell.Io
import "Debug.js" as Debug
import "Diagnose.js" as Diagnose

// The Agent Debug service. While an agent is chosen it follows the journal
// for the core dumps of the user's own programs, and it reads the core's
// failed VGS setup tasks through capability `doctor`. Each new crash or
// failed task, at most one a minute per program or task (Debug.admit),
// gets one notification through the core notify capability, whose Diagnose
// opens the chosen text receiver or the plugin's `diagnose` TUI, and whose
// Mute, on a crash, mutes the program. It publishes the agents the Settings
// select offers, the muted programs and the Crash watch reading.
//   vgshell ipc call vgs.agent-debug invoke mute PROGRAM
//   vgshell ipc call vgs.agent-debug invoke unmute PROGRAM
//     `ok` or the keyed refusal; the vgs-diagnose skill and tui/unmute.sh
//     call them on the user's yes
//   vgshell ipc call vgs.agent-debug invoke draft ""
//     the waiting Diagnose draft, JSON { facts, agent }, facts null for none
//   vgshell ipc call vgs.agent-debug invoke draft-run ""
//   vgshell ipc call vgs.agent-debug invoke draft-cancel ""
//     the window's Run and Cancel: `ok`, or `refused: draft=none`,
//     `refused: agent=none`
//
// Another plugin hands a failure to the `diagnose` receiver as text: a
// failed sync job's facts (Debug.syncFacts). The receiver opens a draft in
// the Agent Debug window and starts nothing: only the user's Run opens the
// agent, as a notification's Diagnose does. A second failure while a draft
// waits is refused, so the waiting draft stays.
//
// With no agent chosen it starts no process: the uid read and the follower
// start only once one is. Every process here is a managed Quickshell
// Process, which the engine ends with the service (docs/architecture/
// runtime.md § Process).
Item {
    id: root

    // The core assigns the plugin's scoped shell object after creation.
    property var shell: null
    // The shell this service registered with, so a new object handed over
    // registers nothing twice.
    property var registeredWith: null

    readonly property var missing: shell === null ? null : shell.requirements.missing
    // Keep an unavailable saved text target selected so Diagnose can explain
    // its cause and offer an explicit one-off terminal choice.
    readonly property string agent: missing === null ? "" : Debug.chosen(shell.settings.agent, missing)
    readonly property bool journal: missing !== null && missing.indexOf("journalctl") === -1
    // Plugin id -> its failed requirement install, the core's reading.
    readonly property var failures: shell === null ? null : shell.doctor.installFailures
    // The user's uid, read once by `id -u` when the follower is first
    // wanted; uidFailed when that read failed.
    property string uid: ""
    property bool uidFailed: false
    // Whether the follower ended while it was wanted. It stays stopped
    // until the plugin is turned off and on, or the agent changes.
    property bool stopped: false
    readonly property bool wanted: agent !== "" && journal && !stopped && !uidFailed
    property var exitCompletion: null
    // The limiter's window (Debug.admit), the failure keys last read, null
    // before the first read, and the service's own recent pids.
    property var seen: ({})
    property var failuresSeen: null
    property var ownPids: []
    readonly property var targets: shell === null ? [] : shell.handoff.targets
    onTargetsChanged: publish()
    // Only the scalar failure arguments survive while the recovery window
    // offers a one-off terminal choice. It never changes the saved agent.
    property var recoveryArgs: null
    // The failure another plugin handed over, waiting for Run or Cancel in
    // the window; null for none.
    property var draft: null
    property string recoveryReason: ""

    onShellChanged: {
        if (shell === null) return;
        if (registeredWith === null) {
            registeredWith = shell;
            shell.ipc.handle("mute", name => root.mute(name));
            shell.ipc.handle("unmute", name => root.unmute(name));
            shell.ipc.handle("recover", name => root.recover(name));
            shell.ipc.handle("recovery", () => JSON.stringify({ waiting: root.recoveryArgs !== null, reason: root.recoveryReason }));
            // Another plugin's failure reaches Diagnose as text through the
            // core's handoff, never a named call: Local Sync's Send to agent.
            shell.handoff.offer("diagnose", text => root.handed(text), "");
            shell.ipc.handle("draft", () => JSON.stringify({ facts: root.draft, agent: root.agent === "" ? "" : Debug.label(root.agent, root.targets) }));
            shell.ipc.handle("draft-run", () => root.runDraft());
            shell.ipc.handle("draft-cancel", () => {
                if (root.draft === null) return "refused: draft=none";
                root.draft = null;
                return "ok";
            });
        }
        publish();
    }
    onMissingChanged: publish()
    // A change of agent starts a stopped follower again.
    onAgentChanged: {
        stopped = false;
        publish();
    }
    onWantedChanged: reconcile()
    onFailuresChanged: readFailures()

    // Start or stop the follower to match `wanted`: the uid read first.
    function reconcile() {
        if (!wanted) {
            if (follower.running) follower.running = false;
        } else if (uid === "") {
            if (!uidRead.running) uidRead.running = true;
        } else if (!follower.running) {
            follower.command = Debug.followerArgv(uid);
            exitCompletion = null;
            follower.running = true;
        }
        publish();
    }

    // COMPLETION, a Process's exit, and the last line of its STDERR, as
    // the log names why it ended.
    function ending(completion, stderr) {
        const lines = stderr.trim().split("\n");
        return (completion === null ? "exit=none" : "exit=" + completion.code + " status=" + completion.status) + " stderr=" + JSON.stringify(lines[lines.length - 1]);
    }

    function own(pid) {
        ownPids = Debug.ownAdded(ownPids, pid);
    }

    function uidEnded(completion, text) {
        uid = completion !== null && completion.code === 0 && completion.status === 0 ? Debug.uidOf(text) : "";
        if (uid === "") {
            uidFailed = true;
            console.error("agent-debug: uid=unread " + ending(completion, uidErr.text));
        }
        reconcile();
    }

    // The follower ended while it was wanted: the Crash watch reads
    // Stopped, and the log names why.
    function followerEnded() {
        if (wanted) {
            console.warn("agent-debug: watch=stopped " + ending(exitCompletion, followerErr.text));
            stopped = true;
        }
        publish();
    }

    function journalLine(line) {
        const entry = Debug.crash(line, ownPids);
        if (entry.kind !== "crash") {
            if (entry.reason === "json") console.warn("agent-debug: line=skipped reason=json");
            return;
        }
        const program = Debug.fact(entry.program);
        if (agent === "" || Debug.mutedList(shell.settings.muted).indexOf(program) !== -1) return;
        if (!admitted("crash:" + program)) return;
        send(Debug.crashNotice(program, Debug.label(agent, targets)), { kind: "crash", entry: entry, read: Date.now() });
    }

    // The failures the core holds now, each new one told once while an
    // agent is chosen; the first read tells none.
    function readFailures() {
        if (failures === null) return;
        const step = Debug.failuresStep(failuresSeen, failures, shell.manifest.id);
        failuresSeen = step.seen;
        if (agent === "") return;
        for (const fresh of step.fresh) {
            if (!admitted("task:" + fresh.id)) continue;
            send(Debug.taskNotice(fresh.failure, Debug.label(agent, targets)), { kind: "task", plugin: fresh.id, key: Debug.failureKey(fresh.id, fresh.failure), failure: fresh.failure, read: Date.now() });
        }
    }

    function admitted(key) {
        const result = Debug.admit(seen, key, Date.now());
        seen = result.seen;
        if (result.reason === "full") console.warn("agent-debug: notice=dropped reason=full limit=" + Debug.MAX_KEYS);
        return result.admit;
    }

    // The core owns the notification and reports its chosen action.
    function send(notice, facts) {
        const reply = shell.notify.send(Debug.options(notice), action => {
            if (action === "diagnose") diagnose(facts);
            else if (action === "mute" && facts.kind === "crash") {
                const reply = mute(Debug.fact(facts.entry.program));
                if (reply !== "ok") console.error("agent-debug: mute " + reply);
            }
        });
        if (reply !== "ok") console.warn("agent-debug: notice " + reply);
    }

    // FACTS handed as TEXT by another plugin: a failed sync job's
    // (Debug.syncFacts), held as the window's draft until the user runs or
    // cancels it. The answer tells the sender why it could not.
    function handed(text) {
        const facts = Debug.syncFacts(text);
        if (facts === null) return { ok: false, reason: "Agent Debug could not read this failure." };
        if (draft !== null) return { ok: false, reason: "Agent Debug already holds a diagnosis. Run or cancel it first." };
        draft = facts;
        const reply = shell.surfaces.summon("window", JSON.stringify({ draft: true }));
        if (reply === "ok") return { ok: true, reason: "" };
        draft = null;
        console.error("agent-debug: draft window " + reply);
        return { ok: false, reason: "Agent Debug could not open its window. Try again." };
    }

    // The window's Run: Diagnose for the waiting draft, through the agent
    // the user chose.
    function runDraft() {
        if (draft === null) return "refused: draft=none";
        if (agent === "") return "refused: agent=none";
        const facts = draft;
        draft = null;
        diagnose({ kind: "sync", entry: facts, read: Date.now() });
        return "ok";
    }

    // Choose at the press, never when the notification was built. Terminal
    // arguments and the text prompt share the same admitted scalar facts.
    function diagnose(facts) {
        if (agent === "") {
            console.warn("agent-debug: diagnose refused=no-agent");
            return;
        }
        let args;
        if (facts.kind === "crash") {
            const at = facts.entry.time === null ? facts.read : facts.entry.time;
            args = Debug.crashArgs(agent, facts.entry, at, -new Date(at).getTimezoneOffset());
        } else if (facts.kind === "sync") {
            const at = facts.entry.at === 0 ? facts.read : facts.entry.at;
            args = Debug.syncArgs(agent, facts.entry, at, -new Date(at).getTimezoneOffset());
        } else {
            const failure = Debug.pressedFailure(failures, facts.plugin, facts.key, facts.failure);
            args = Debug.taskArgs(agent, facts.plugin, failure, facts.read, -new Date(facts.read).getTimezoneOffset());
        }
        if (Debug.isHandoff(agent)) {
            const target = targets.find(row => row.key === agent);
            const result = target === undefined ? { ok: false, reason: "Your saved message target is no longer installed." }
                : !target.available ? { ok: false, reason: target.reason } : target.open(Diagnose.prompt(args.slice(1), ""));
            if (!result.ok) {
                recoveryArgs = args.slice(1);
                recoveryReason = result.reason;
                const reply = shell.surfaces.summon("window", "{}");
                if (reply !== "ok") console.error("agent-debug: recovery " + reply);
            }
            return;
        }
        terminal(args);
    }

    function terminal(args) {
        const reply = shell.tui.run("diagnose", args, result => {
            if (result.reason !== null || (result.code !== 0 && result.code !== 130))
                console.warn("agent-debug: diagnose code=" + result.code + " reason=" + result.reason);
        });
        if (reply !== "ok") console.warn("agent-debug: diagnose " + reply);
        return reply;
    }

    function recover(name) {
        if (name === "cancel") { recoveryArgs = null; return "ok"; }
        if (recoveryArgs === null || ["claude", "codex"].indexOf(name) === -1) return "refused: recovery=choice";
        if (missing.indexOf(name) !== -1) return "refused: recovery=agent-missing";
        const reply = terminal([name].concat(recoveryArgs));
        if (reply === "ok") recoveryArgs = null;
        return reply;
    }

    function mute(name) {
        const result = Debug.mute(Debug.mutedList(shell.settings.muted), name);
        return result.answer === "ok" ? keepMuted(result.list) : result.answer;
    }

    function unmute(name) {
        const result = Debug.unmute(Debug.mutedList(shell.settings.muted), name);
        return result.answer === "ok" ? keepMuted(result.list) : result.answer;
    }

    // LIST written to the plugin's `muted` setting when it changes it; the
    // write hands the service a new shell, which publishes the rows.
    function keepMuted(list) {
        if (JSON.stringify(list) === JSON.stringify(Debug.mutedList(shell.settings.muted))) return "ok";
        return shell.configure.set("muted", list);
    }

    function watchState() {
        if (agent === "") return "no-agent";
        if (!journal) return "no-journal";
        if (stopped || uidFailed) return "stopped";
        return follower.running ? "watching" : "starting";
    }

    // Publish each value; the core keeps an unchanged one as it is.
    function publish() {
        if (shell === null || missing === null) return;
        const values = {
            agents: Debug.choices(missing, targets, shell.settings.agent),
            muted: Debug.mutedRows(Debug.mutedList(shell.settings.muted)),
            watch: Debug.WATCH[watchState()]
        };
        for (const key of Object.keys(values)) {
            const reply = shell.status.set(key, values[key]);
            if (!shell.status.isOk(reply)) console.error("agent-debug: publish=" + key + " " + reply);
        }
    }

    Process {
        id: uidRead
        property var completion: null
        command: ["id", "-u"]
        stdout: StdioCollector { id: uidText }
        stderr: StdioCollector { id: uidErr }
        onStarted: root.own(processId)
        onExited: (code, status) => { completion = { code: code, status: status }; }
        onRunningChanged: if (!running) root.uidEnded(completion, uidText.text)
    }

    // processId is null while a Process is not running, so each pid is read
    // at `started`; SplitParser splits at "\n" by default, one journal entry
    // a line; a null stderr parser closes that channel, so each process here
    // collects its stderr for the log
    // (https://quickshell.org/docs/v0.3.1/types/Quickshell.Io/Process,
    // .../SplitParser).
    Process {
        id: follower
        stdout: SplitParser { onRead: line => root.journalLine(line) }
        stderr: StdioCollector { id: followerErr }
        onStarted: {
            root.own(processId);
            root.publish();
        }
        onExited: (code, status) => { root.exitCompletion = { code: code, status: status }; }
        onRunningChanged: if (!running) root.followerEnded()
    }

}
