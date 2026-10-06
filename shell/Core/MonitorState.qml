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
// each (docs/architecture/runtime-hyprland.md). A failed read is logged
// and returns `outputs` to null. The plugin that owns `hyprland.monitors`
// may run a guarded trial: the guard is detached from Quickshell, and the
// token file is the only state it shares with the shell.
Scope {
    id: root

    // Whether anything needs the outputs: a plugin holds `monitors`.
    property bool active: false
    // parseOutputs's outputs, null until read while active and after a
    // failed read.
    property var outputs: null
    property string ownerId: ""
    property var trialState: ({ phase: "idle", token: "", deadline: 0, failure: "" })
    property string restoreLua: ""
    property var restoreRules: ({})
    property var trialRules: ({})
    property string trialLua: ""
    property string tokenPath: ""
    readonly property string trialDir: Paths.stateDir + "/display-trials"
    readonly property string guardPath: Quickshell.shellDir + "/../bin/vgshell-display-guard"
    readonly property string hyprlandSignature: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")

    onActiveChanged: {
        if (active) {
            readOutputs();
            return;
        }
        outputs = null;
    }

    // The capability. It holds nothing to release.
    function provider(ctx) {
        return Object.freeze({
            get outputs() { return root.outputs === null ? null : Logic.frozenJson(root.outputs); },
            get trialState() { return Logic.frozenJson(root.trialState); },
            overridden: rules => root.overridden(rules),
            trial: rules => root.trial(ctx.id, rules),
            keep: (token, done) => root.keep(ctx.id, token, done),
            revert: token => root.revert(ctx.id, token)
        });
    }

    function record() {
        return { active: root.active };
    }

    function readOutputs() {
        reader.read(Monitors.OUTPUTS_REQUEST, null);
    }

    function mustOwn(id) {
        return id === ownerId ? "" : "refused: monitors-owner=" + ownerId + " caller=" + id;
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

    function trial(id, rules) {
        const ownership = mustOwn(id);
        if (ownership !== "") return ownership;
        if (outputs === null) return "refused: monitors=unread";
        if (trialState.phase !== "idle") return "refused: monitors-trial=active";
        const bad = Monitors.layoutError(rules, outputs);
        if (bad !== "") return bad;
        const trial = Monitors.rulesLua(rules);
        if (!trial.ok) return trial.error;
        const restore = Monitors.rulesLua(Monitors.captureRules(outputs, Object.keys(rules)));
        if (!restore.ok) return restore.error;
        const now = Math.floor(Date.now() / 1000);
        tokenPath = trialDir + "/" + now + "-" + Math.floor(Math.random() * 1000000) + ".token";
        trialLua = trial.lua;
        restoreLua = restore.lua;
        restoreRules = Monitors.captureRules(outputs, Object.keys(rules));
        trialRules = Logic.clone(rules);
        trialState = { phase: "arming", token: tokenPath, deadline: now + 15, failure: "" };
        tokenInit.command = ["bash", "-c", "[[ -x \"$2\" ]] && mkdir -p -- \"${1%/*}\" && : >\"$1\"", "vgs-display-token", tokenPath, guardPath];
        tokenInit.running = true;
        return "ok";
    }

    function keep(id, token, done) {
        const ownership = mustOwn(id);
        if (ownership !== "") return ownership;
        if (token !== trialState.token || trialState.phase !== "holding") return "refused: monitors-token=unknown";
        keeper.done = typeof done === "function" ? done : null;
        keeper.rules = Logic.clone(trialRules);
        keeper.command = ["bash", "-c", "mv -- \"$1\" \"$1.keep\" && rm -f -- \"$1.keep\"", "vgs-display-keep", token];
        keeper.running = true;
        trialState = { phase: "keeping", token: token, deadline: 0, failure: "" };
        return "pending";
    }

    function revert(id, token) {
        const ownership = mustOwn(id);
        if (ownership !== "") return ownership;
        if (token !== trialState.token || trialState.phase === "idle") return "refused: monitors-token=unknown";
        reverter.command = ["bash", "-c", "mv -- \"$1\" \"$1.revert\" && rm -f -- \"$1.revert\"", "vgs-display-revert", token];
        reverter.running = true;
        const lua = restoreLua;
        deadline.stop();
        trialState = { phase: "reverting", token: token, deadline: 0, failure: "" };
        Compositor.monitorEval(lua, answer => {
            root.trialState = { phase: "idle", token: "", deadline: 0, failure: answer === "ok" ? "" : answer };
            root.trialRules = {};
            root.readOutputs();
        });
        return "ok";
    }

    Connections {
        target: root.active ? Hyprland : null
        function onRawEvent(event) {
            switch (event.name) {
            case "monitoradded":
            case "monitoraddedv2":
            case "monitorremoved":
            case "monitorremovedv2":
            case "configreloaded":
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
            } else if (JSON.stringify(read.outputs) !== JSON.stringify(root.outputs)) {
                root.outputs = read.outputs;
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
                root.trialState = { phase: "idle", token: "", deadline: 0, failure: "guard=failed" };
                return;
            }
            const guardCommand = [root.guardPath, String(root.trialState.deadline), root.trialState.token, root.hyprlandSignature, root.restoreLua, JSON.stringify(root.restoreRules)];
            if (!guardPath.length) {
                root.trialState = { phase: "idle", token: "", deadline: 0, failure: "guard=missing" };
                return;
            }
            Quickshell.execDetached({ command: guardCommand, environment: { VGSHELL_RUNNER_PID: null } });
            root.trialState = { phase: "holding", token: root.trialState.token, deadline: root.trialState.deadline, failure: "" };
            deadline.interval = Math.max(1, root.trialState.deadline - Math.floor(Date.now() / 1000)) * 1000;
            deadline.restart();
            Compositor.monitorEval(root.trialLua, answer => {
                if (answer !== "ok") root.trialState = { phase: "holding", token: root.trialState.token, deadline: root.trialState.deadline, failure: answer };
                root.readOutputs();
            });
        }
    }

    Timer {
        id: deadline
        onTriggered: {
            if (root.trialState.phase !== "holding") return;
            const token = root.trialState.token;
            root.trialState = { phase: "idle", token: "", deadline: 0, failure: "deadline" };
            root.trialRules = {};
            root.readOutputs();
            // The detached guard owns the actual restore.
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
            if (root.trialState.phase === "keeping") root.trialState = { phase: "idle", token: "", deadline: 0, failure: completion === 0 ? "" : "claimed" };
            root.trialRules = {};
            if (callback !== null) callback(completion === 0 ? { ok: true, rules: saved } : { ok: false, error: "refused: monitors-token=claimed" });
        }
    }
    Process { id: reverter }
}
