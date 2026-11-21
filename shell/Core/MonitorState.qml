import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import "MonitorLogic.js" as Monitors
import "PluginLogic.js" as Logic

// Owns the outputs reading behind the `monitors` capability: the outputs
// `hyprctl -j monitors all` lists, read while `active`. MonitorLogic.js
// judges the reply. It writes nothing: the user's own Hyprland config sets
// every output. Hyprland posts `monitoradded`, `monitorremoved`,
// `monitoraddedv2` and `monitorremovedv2` when an output comes or goes and
// `configreloaded` after each reload, and the outputs are read again on
// each. A failed read is logged
// and returns `outputs` to null. `support`, what each panel takes, comes
// from `hyprctl systeminfo`: Hyprland v0.56.2 prints it nowhere else, in
// no JSON form, and only for the outputs that are on and mirror nothing.
// That call runs lspci on Hyprland's main loop and holds the compositor
// while it does (22-36 ms per call in the nested sandbox, host cachy,
// 2026-10-06), so it is read only while a hold from
// `wantSupport` stands, and then only when the outputs list a panel it
// lacks or `monitoraddedv2` puts a panel on a connector; a trial that names
// a colour mode with no panel read asks for one read. Each v2 event drops
// the panel of its connector, and no reload reads it again. The plugin
// that owns `hyprland.monitors`
// may run a guarded trial: the guard is detached from Quickshell, and the
// token file is the only state it shares with the shell.
Scope {
    id: root

    // Whether anything needs the outputs: a plugin holds `monitors`.
    property bool active: false
    // parseOutputs's outputs, null until read while active and after a
    // failed read.
    property var outputs: null
    // parseSupport's support, null until read while active and after a
    // failed read.
    property var support: null
    // The `wantSupport` holds that stand.
    property int supportHolds: 0
    readonly property bool supportWanted: active && supportHolds > 0
    property string ownerId: ""
    property var trialState: ({ phase: "idle", token: "", deadline: 0, failure: "" })
    property string restoreLua: ""
    property var restoreRules: ({})
    // Whether a trial's detached guard may still be restoring, read from
    // the trial directory, since a guard outlives the shell that started it
    // (MonitorLogic.guardRecheck): `unread` until a listing answers,
    // `pending` from a trial's arming and while a guard's token or claim
    // stands, `rereading` while the outputs read that follows the guard
    // runs, `settled` once it answered. layoutRules is null and trial()
    // refuses until `settled`.
    property string guard: "unread"
    // The name of the token this shell's last trial armed its guard with,
    // "" once that guard is done or Keep claimed it; whether this shell's
    // deadline timer has fired for it; and the listings since that, or since
    // activation.
    property string ownToken: ""
    property bool ownDue: false
    property int guardChecks: 0
    // The rule set the trial's Keep saves.
    property var keptRules: ({})
    property string trialLua: ""
    property string tokenPath: ""
    readonly property string trialDir: Paths.stateDir + "/display-trials"
    readonly property string guardPath: Quickshell.shellDir + "/../bin/vgshell-display-guard"
    readonly property string hyprlandSignature: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")

    onActiveChanged: {
        if (active) {
            guardChecks = 0;
            readOutputs();
            listGuards();
            return;
        }
        outputs = null;
        support = null;
        guard = "unread";
        guardCheck.stop();
    }

    onSupportWantedChanged: readMissingSupport()
    onOutputsChanged: readMissingSupport()

    // The capability. A `wantSupport` hold is released by the function it
    // returns or with the instance.
    function provider(ctx) {
        return Object.freeze({
            get outputs() { return root.outputs === null ? null : Logic.frozenJson(root.outputs); },
            get support() { return root.support === null ? null : Logic.frozenJson(root.support); },
            get trialState() { return Logic.frozenJson(root.trialState); },
            primaryOutputs: rules => Logic.frozenJson(Monitors.primaryOutputs(root.outputs || [], rules)),
            layoutRules: saved => root.layoutRules(saved),
            overridden: rules => root.overridden(rules),
            trial: (rules, saved) => root.trial(ctx.id, rules, saved),
            keep: (token, done) => root.keep(ctx.id, token, done),
            revert: token => root.revert(ctx.id, token),
            wantSupport: () => root.holdSupport(ctx)
        });
    }

    function holdSupport(ctx) {
        let held = true;
        const release = () => {
            if (!held) return;
            held = false;
            root.supportHolds -= 1;
        };
        supportHolds += 1;
        ctx.onDispose(release);
        return release;
    }

    function record() {
        return { active: root.active };
    }

    function readOutputs() {
        reader.read(Monitors.OUTPUTS_REQUEST, null);
    }

    function readSupport() {
        supportReader.read(Monitors.SUPPORT_REQUEST, null);
    }

    function readMissingSupport() {
        if (supportWanted && outputs !== null && Monitors.supportMissing(outputs, support).length > 0) readSupport();
    }

    function mustOwn(id) {
        return id === ownerId ? "" : "refused: monitors-owner=" + ownerId + " caller=" + id;
    }

    // The layout the login screen copies, SAVED over what Hyprland applied,
    // or null while the outputs are unread or a trial holds or its guard may
    // still hold them, so no trial reaches the copy.
    function layoutRules(saved) {
        if (outputs === null || trialState.phase !== "idle" || guard !== "settled") return null;
        return Logic.frozenJson(Monitors.layoutRules(outputs, saved));
    }

    // List the trial directory, once more after a listing in flight, since
    // that one may predate the change asked about.
    function listGuards() {
        guardCheck.stop();
        if (guardLister.running) {
            guardLister.again = true;
            return;
        }
        guardLister.completion = null;
        guardLister.running = true;
    }

    function guardsListed() {
        if (!active) return;
        if (guardLister.again) {
            guardLister.again = false;
            listGuards();
            return;
        }
        if (guardLister.completion !== 0) {
            // Unlisted is not settled: the next activation or trial lists again.
            guard = "unread";
            console.error("monitors: trial-guards=unlisted " + (guardLister.completion === null ? "start=failed" : "exit=" + guardLister.completion) + " dir=" + trialDir);
            return;
        }
        const next = Monitors.guardRecheck(guardNames.text.split("\n").filter(name => name !== ""),
            { now: Math.floor(Date.now() / 1000), own: ownToken, due: ownDue, checks: guardChecks });
        guardChecks += 1;
        if (next !== null) {
            guard = "pending";
            guardCheck.interval = next * 1000;
            guardCheck.restart();
            return;
        }
        // The read after the guard is the layout, whatever it shows.
        ownToken = "";
        guard = "rereading";
        readOutputs();
    }

    function overridden(rules) {
        if (outputs === null) return {};
        const out = {};
        for (const id of Object.keys(rules || {})) {
            const output = outputs.find(o => o.identifier === id || o.name === id);
            if (output !== undefined) out[id] = Monitors.overridden(rules[id], output, outputs);
        }
        return out;
    }

    // Apply RULES for 15 s over the owner's SAVED rules; Keep hands back the
    // set to save.
    function trial(id, rules, saved) {
        const ownership = mustOwn(id);
        if (ownership !== "") return ownership;
        if (outputs === null) return "refused: monitors=unread";
        if (trialState.phase !== "idle") return "refused: monitors-trial=active";
        // A restore is captured only from outputs no guard may still change.
        if (guard !== "settled") {
            if (guard === "unread") listGuards();
            else if (guard === "rereading") readOutputs();
            return "refused: monitors-trial=settling";
        }
        if (Monitors.supportNeeded(rules) && Monitors.supportMissing(outputs, support).length > 0) readSupport();
        const trial = Monitors.trialPlan(saved, rules, outputs, support);
        if (!trial.ok) return trial.error;
        const now = Math.floor(Date.now() / 1000);
        // From here a guard may restore, so the copy waits until it is done,
        // a Keep claims the token, or no guard starts. The previous trial's
        // deadline timer must not mark this one due.
        guard = "pending";
        deadline.stop();
        tokenPath = trialDir + "/" + now + "-" + Math.floor(Math.random() * 1000000) + ".token";
        trialLua = trial.lua;
        restoreLua = trial.restore;
        restoreRules = trial.restoreRules;
        keptRules = Logic.clone(trial.kept);
        trialState = { phase: "arming", token: tokenPath, deadline: now + Monitors.TRIAL_SECONDS, failure: "" };
        tokenInit.command = ["bash", "-c", "[[ -x \"$2\" ]] && mkdir -p -- \"${1%/*}\" && : >\"$1\"", "vgs-display-token", tokenPath, guardPath];
        tokenInit.running = true;
        return "ok";
    }

    function keep(id, token, done) {
        const ownership = mustOwn(id);
        if (ownership !== "") return ownership;
        if (token !== trialState.token || trialState.phase !== "holding") return "refused: monitors-token=unknown";
        keeper.done = typeof done === "function" ? done : null;
        keeper.rules = Logic.clone(keptRules);
        keeper.command = ["bash", "-c", "mv -- \"$1\" \"$1.keep\" && rm -f -- \"$1.keep\"", "vgs-display-keep", token];
        keeper.running = true;
        trialState = { phase: "keeping", token: token, deadline: 0, failure: "" };
        return "pending";
    }

    function revert(id, token) {
        const ownership = mustOwn(id);
        if (ownership !== "") return ownership;
        if (token !== trialState.token || trialState.phase === "idle") return "refused: monitors-token=unknown";
        const lua = restoreLua;
        // The deadline timer keeps running: it marks this shell's own token
        // due, which a refused eval leaves to the guard.
        trialState = { phase: "reverting", token: token, deadline: 0, failure: "" };
        // A refused eval runs no callback, and the trial must still end,
        // since the Hyprland layer holds its writes while one runs. Its
        // token stays unclaimed, so the detached guard restores at the
        // deadline; only a queued restore claims it.
        const queued = Compositor.monitorEval(lua, answer => endRevert(answer));
        if (queued !== "ok") {
            endRevert(queued);
            return queued;
        }
        reverter.command = ["bash", "-c", "mv -- \"$1\" \"$1.revert\" && rm -f -- \"$1.revert\"", "vgs-display-revert", token];
        reverter.running = true;
        return "ok";
    }

    // A refused eval leaves the token to the guard. A queued one's claim
    // runs beside the eval, and the directory is listed once it ended: its
    // rename either took the token, or found the guard's claim.
    function endRevert(answer) {
        trialState = { phase: "idle", token: "", deadline: 0, failure: answer === "ok" ? "" : answer };
        keptRules = {};
        readOutputs();
        if (!reverter.running) listGuards();
    }

    Connections {
        target: root.active ? Hyprland : null
        function onRawEvent(event) {
            // Hyprland posts each v2 event beside its first form, so the
            // pair drops a panel once.
            switch (event.name) {
            case "monitoradded":
            case "monitorremoved":
            case "configreloaded":
                root.readOutputs();
                return;
            case "monitoraddedv2":
                root.support = Monitors.supportWithout(root.support, event.data);
                root.readOutputs();
                if (root.supportWanted) root.readSupport();
                return;
            case "monitorremovedv2":
                root.support = Monitors.supportWithout(root.support, event.data);
                root.readOutputs();
                return;
            }
        }
    }

    HyprctlReader {
        id: reader
        label: "outputs"
        onReadDone: (request, text, failure) => {
            if (!root.active) return;
            const read = failure === "" ? Monitors.parseOutputs(text) : { ok: false, error: failure };
            if (!read.ok) {
                root.outputs = null;
                console.error("monitors: " + read.error);
            } else {
                if (JSON.stringify(read.outputs) !== JSON.stringify(root.outputs)) root.outputs = read.outputs;
                // HyprctlReader answers only the last read asked for, which
                // started after the guard.
                if (root.guard === "rereading") root.guard = "settled";
            }
        }
    }

    HyprctlReader {
        id: supportReader
        label: "support"
        onReadDone: (request, text, failure) => {
            if (!root.active) return;
            const read = failure === "" ? Monitors.parseSupport(text) : { ok: false, error: failure };
            if (!read.ok) {
                root.support = null;
                console.error("monitors: " + read.error);
            } else if (JSON.stringify(read.support) !== JSON.stringify(root.support)) {
                root.support = read.support;
            }
        }
    }

    Process {
        id: tokenInit
        property var completion: null
        onExited: code => completion = code
        onRunningChanged: {
            if (running) return;
            if (root.trialState.phase !== "arming") return;
            if (completion !== 0) {
                root.guard = "settled";
                root.trialState = { phase: "idle", token: "", deadline: 0, failure: "guard=failed" };
                return;
            }
            const guardCommand = [root.guardPath, String(root.trialState.deadline), root.trialState.token, root.hyprlandSignature, root.restoreLua, JSON.stringify(root.restoreRules)];
            if (!guardPath.length) {
                root.guard = "settled";
                root.trialState = { phase: "idle", token: "", deadline: 0, failure: "guard=missing" };
                return;
            }
            Quickshell.execDetached({ command: guardCommand, environment: { VGSHELL_RUNNER_PID: null } });
            root.ownToken = root.trialState.token.slice(root.trialDir.length + 1);
            root.ownDue = false;
            root.trialState = { phase: "holding", token: root.trialState.token, deadline: root.trialState.deadline, failure: "" };
            deadline.interval = Math.max(1, root.trialState.deadline - Math.floor(Date.now() / 1000)) * 1000;
            deadline.restart();
            // The answer can come after Keep or Revert ended this trial;
            // its failure then belongs to no trial.
            const token = root.trialState.token;
            Compositor.monitorEval(root.trialLua, answer => {
                if (answer !== "ok" && root.trialState.phase === "holding" && root.trialState.token === token)
                    root.trialState = { phase: "holding", token: token, deadline: root.trialState.deadline, failure: answer };
                else if (answer !== "ok") console.warn("monitors: trial eval " + answer + " after its trial ended");
                root.readOutputs();
            });
        }
    }

    Timer {
        id: deadline
        // The guard's sleep for this shell's own token ends now, on the same
        // clock, so listings count from here.
        onTriggered: {
            root.ownDue = true;
            root.guardChecks = 0;
            if (root.trialState.phase === "holding") {
                root.trialState = { phase: "idle", token: "", deadline: 0, failure: "deadline" };
                root.keptRules = {};
                root.readOutputs();
                // The detached guard owns the actual restore.
                root.listGuards();
            } else if (root.guard === "pending" && root.trialState.phase === "idle") {
                root.listGuards();
            }
        }
    }

    Process {
        id: keeper
        property var done: null
        property var rules: ({})
        property var completion: null
        onExited: code => completion = code
        onRunningChanged: {
            if (running) return;
            const callback = done;
            const saved = rules;
            done = null;
            rules = {};
            // Kept, no guard restores. Claimed, the guard took the token
            // before Keep and restores.
            if (completion === 0) {
                root.ownToken = "";
                root.guard = "settled";
            }
            if (root.trialState.phase === "keeping") root.trialState = { phase: "idle", token: "", deadline: 0, failure: completion === 0 ? "" : "claimed" };
            root.keptRules = {};
            if (completion !== 0) root.listGuards();
            if (callback !== null) callback(completion === 0 ? { ok: true, rules: saved } : { ok: false, error: "refused: monitors-token=claimed" });
        }
    }
    Process {
        id: reverter
        onRunningChanged: if (!running && root.guard === "pending" && root.trialState.phase === "idle") root.listGuards()
    }

    // The trial directory's entries, one per line; a missing directory has
    // none. Its stdout is complete once running turns false
    // (StdioCollector.waitForEnd, as the keeper's and copier's runs read it).
    Process {
        id: guardLister
        property var completion: null
        property bool again: false
        command: ["bash", "-c", "[[ -e $1 ]] || exit 0; cd -- \"$1\" && shopt -s nullglob dotglob && printf '%s\\n' *", "vgs-display-guards", root.trialDir]
        stdout: StdioCollector { id: guardNames; waitForEnd: true }
        onExited: code => completion = code
        onRunningChanged: if (!running) root.guardsListed()
    }

    // One second past a pending guard's deadline, then each second while it
    // may still be at work, until MonitorLogic.GUARD_GRACE_SECONDS past it.
    Timer {
        id: guardCheck
        onTriggered: root.listGuards()
    }
}
