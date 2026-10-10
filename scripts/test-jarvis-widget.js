#!/usr/bin/env node
// What the Jarvis bar widget shows, shell/plugins/vgs.jarvis/WidgetView.js,
// under node: the state, icon, tone and tooltip for the status values the
// service publishes, the keyed refusal of every value outside them, the
// effective keys and the talk mode. Each Session record comes from
// Session.js's own initial state with the named regions set, passes
// Session.validate, and takes its phase from Session.phaseOf, as the daemon
// publishes it. Every expected value is written out by hand, but for the
// words of a fault, the audio problem and a remaining Setup step: those
// come from the view's own table under the kind or step this suite names.
// No process, network or audio is used.
//
// The controls at the end edit a copy of the view, one rule at a time, and
// require this suite to fail an assertion on each copy.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { load } = require("../bin/lib/qml-library.js");

const dir = path.join(__dirname, "..", "shell", "plugins", "vgs.jarvis");
const Session = load(path.join(dir, "Session.js"));
const SetupGate = load(path.join(dir, "SetupGate.js"));
const Lucide = load(path.join(__dirname, "..", "shell", "Ui", "icons", "Lucide.js"));
const KeyNavLogic = load(path.join(__dirname, "..", "shell", "Ui", "foundation", "KeyNavLogic.js"));
const MANIFEST_KEYS = Object.fromEntries(JSON.parse(fs.readFileSync(path.join(__dirname, "..", "shell", "plugins", "vgs.jarvis", "manifest.json"), "utf8"))
    .hyprland.binds.map(bind => [bind.shortcut, bind.key]));
const copy = value => JSON.parse(JSON.stringify(value));
const KEYS = { talk: "Super+Right Alt", mute: "Super+Shift+Right Alt", stop: "Super+Alt+Period", confirm: "Super+Alt+Y" };
const UNBOUND = { talk: null, mute: null, stop: null, confirm: null };

// A detail as the service publishes it: the Session record with REGIONS
// over a raised gate, its phase from Session.phaseOf.
function detail(regions) {
    const s = Object.assign(copy(Session.initial()), { gate: { kind: "up" } }, copy(regions));
    assert.equal(Session.validate(s), true, "fixture is a Session record: " + JSON.stringify(regions));
    return { phase: Session.phaseOf(s), seq: 1, state: s };
}
const down = reason => ({ gate: { kind: "down", reason } });
const OPEN = { capture: { kind: "open", gen: 1, op: 2, mode: "hold" } };
const CLOSING = { capture: { kind: "closing", gen: 1, op: 3 } };
const THINKING = { turn: { kind: "thinking", gen: 1, op: 4, deadline: 70 } };
const MUTED = { mute: { kind: "on" } };
const READY = { tone: "info", text: "Ready; no capture" };
const DEVICES = { tone: "ok", text: "Device list ready" };
const FLOOR = { tone: "danger", text: "Stopped after a problem. Turn Jarvis off and on again." };
const OVERFLOW = { tone: "danger", text: "capture-overflow" };
const up = (regions, extra) => Object.assign({ daemon: READY, audio: DEVICES, detail: detail(regions) }, extra);

const MUTE = "Click or press Super+Shift+Right Alt to mute.";
const UNMUTE = "Click or press Super+Shift+Right Alt to unmute.";
const HOLD = "Hold Super+Right Alt and speak.";
const STOP = "Press Super+Alt+Period to stop.";
const CONFIRM = "Confirm on screen, or press Super+Alt+Y.";
const fault = kind => v => v.FAULT_TEXT[kind];
const retrying = v => v.RETRYING;
const audioText = v => v.AUDIO_TEXT;
const setupStep = key => v => v.SETUP_TEXT.find(([name]) => name === key)[1];
const unconfigured = v => v.GATE_TEXT.unconfigured;
const WITH = (line, details) => v => [line(v).title, [line(v).action].concat(details)];
function expected(row, view) {
    const tip = typeof row[3] === "function" ? row[3](view) : row[3];
    return [row[0], row[1], row[2], tip[0], tip[1]];
}
const tip = (title, details) => [title, details];
// The Setup steps as the service publishes them (SetupGate.readiness).
const TODO = { tone: "warning", text: "To do", lines: ["fixture line"], action: true };
const DONE = { tone: "ok", text: "Done", action: false };
const MODEL_TODO = { tone: "warning", text: "To do", hint: "fixture hint", action: "key" };
const MODEL_SIGN_IN = { tone: "warning", text: "To do", hint: "fixture hint", action: "signIn" };
const MODEL_DONE = { tone: "ok", text: "Done" };
// [label, status values, [state, icon, tone, [tooltip title, detail lines]]].
const CASES = [
    ["nothing published yet", {}, ["loading", "loader", "info", tip("Jarvis is starting", ["Wait for Jarvis to start.", MUTE])]],
    ["starting before the first state", { daemon: { tone: "info", text: "Starting" }, detail: null, audio: { tone: "info", text: "Reading devices" } },
        ["loading", "loader", "info", tip("Jarvis is starting", ["Wait for Jarvis to start.", MUTE])]],
    ["restarting", { daemon: { tone: "warning", text: "Restarting after a problem" }, detail: null },
        ["loading", "loader", "info", tip("Jarvis is starting", ["Wait for Jarvis to start.", MUTE])]],
    ["mute pending", { daemon: { tone: "warning", text: "Mute pending; disabling Jarvis cancels the request" }, detail: null },
        ["loading", "loader", "info", tip("Jarvis is starting", ["Wait for Jarvis to start.", MUTE])]],
    ["ready", up({}), ["ready", "mic", "calm", tip("Jarvis is ready", [HOLD, MUTE])]],
    ["listening", up(OPEN), ["listening", "audio-lines", "accent", tip("Jarvis is listening", ["Speak now.", MUTE])]],
    ["capture opening", up({ capture: { kind: "opening", gen: 1, op: 2, mode: "conversation" } }),
        ["listening", "audio-lines", "accent", tip("Jarvis is listening", ["Speak now.", MUTE])]],
    ["armed", up({ capture: { kind: "open", gen: 1, op: 2, mode: "armed" } }),
        ["listening", "audio-lines", "accent", tip("Jarvis is listening for Hey Jarvis", ["Say Hey Jarvis.", MUTE])]],
    ["muting while capture closes", up({ mute: { kind: "muting" }, ...CLOSING }),
        ["listening", "audio-lines", "accent", tip("Jarvis is listening", ["Speak now.", UNMUTE])]],
    ["capture closing after a lock", up({ ...down("locked"), ...CLOSING }),
        ["listening", "audio-lines", "accent", tip("Jarvis is listening", ["Speak now.", MUTE])]],
    ["listening over an audio problem", up(OPEN, { audio: OVERFLOW }),
        ["listening", "audio-lines", "accent", tip("Jarvis is listening", ["Speak now.", MUTE])]],
    ["permanent daemon problem", { daemon: FLOOR, detail: null, audio: DEVICES },
        ["problem", "circle-alert", "danger", tip("Jarvis stopped after a problem", ["Turn Jarvis off and on again in Settings > Jarvis.", MUTE])]],
    ["Session error", up({ fault: { kind: "error", reason: "thinking-timeout", retry: 0 } }),
        ["problem", "circle-alert", "danger", WITH(fault("slow"), [MUTE])]],
    ["Session retrying a lost device", up({ fault: { kind: "retrying", reason: "device-lost", retry: 1 } }),
        ["problem", "circle-alert", "danger", WITH(retrying, [MUTE])]],
    ["audio fault", up({}, { audio: OVERFLOW }), ["problem", "circle-alert", "danger", WITH(audioText, [MUTE])]],
    ["audio fault before the first state", { daemon: { tone: "info", text: "Starting" }, detail: null, audio: OVERFLOW },
        ["problem", "circle-alert", "danger", WITH(audioText, [MUTE])]],
    ["problem over mute", up(MUTED, { audio: OVERFLOW }), ["problem", "circle-alert", "danger", WITH(audioText, [UNMUTE])]],
    ["Session error while muted", up({ ...MUTED, fault: { kind: "error", reason: "thinking-timeout", retry: 0 } }),
        ["problem", "circle-alert", "danger", WITH(fault("slow"), [UNMUTE])]],
    ...[["a lost device", "device-lost", "device"], ["a brain stream error", "brain=stream-error", "brain"],
        ["a harness exit", "brain=harness-exit", "brain"], ["a network refusal", "net=timeout", "brain"],
        ["local speech", "speech=local-not-ready", "voice"], ["a capture start", "audio-start: device-busy", "audio"],
        ["a device probe", "device-probe: pw-dump-exit", "audio"], ["a busy player", "playback-busy", "audio"],
        ["a home text over its bound", "guidance=home-too-large", "home"], ["a home skill list over its bound", "guidance=home-skills-too-large", "home"],
        ["a link in the home folder", "home=link", "home"],
        ["an unexpected engine failure", "engine=unexpected", "other"]].map(([label, reason, kind]) =>
        [label, up({ fault: { kind: "error", reason, retry: 0 } }), ["problem", "circle-alert", "danger", WITH(fault(kind), [MUTE])]]),
    // A model its app refused reads with the model's name, from the reason.
    ["a refused model", up({ fault: { kind: "error", reason: "brain=harness-model-refused model=claude-fable-5-1", retry: 0 } }),
        ["problem", "circle-alert", "danger", WITH(v => ({ title: v.FAULT_TEXT.model.title + " claude-fable-5-1", action: v.FAULT_TEXT.model.action }), [MUTE])]],
    ["muted", up(MUTED), ["muted", "mic-off", "neutral", tip("Jarvis is muted", [UNMUTE])]],
    ["muted while locked", up({ ...MUTED, ...down("locked") }), ["muted", "mic-off", "neutral", tip("Jarvis is muted", [UNMUTE])]],
    ["muted over a cancelling turn", up({ ...MUTED, turn: { kind: "cancelling", gen: 1, op: 4, deadline: 70 } }),
        ["muted", "mic-off", "neutral", tip("Jarvis is muted", [UNMUTE])]],
    ["muting with capture closed", up({ mute: { kind: "muting" } }), ["muted", "mic-off", "neutral", tip("Jarvis is muted", [UNMUTE])]],
    ["gate starting", up(down("starting")), ["loading", "loader", "info", tip("Jarvis is starting", ["Wait for Jarvis to start.", MUTE])]],
    ["gate unconfigured, nothing published", up(down("unconfigured")), ["off", "power-off", "neutral", WITH(unconfigured, [MUTE])]],
    ["local voice to do", up(down("unconfigured"), { setupVoice: TODO, setupModel: MODEL_TODO }),
        ["off", "power-off", "neutral", WITH(setupStep("setupVoice"), [MUTE])]],
    ["the AI model to do", up(down("unconfigured"), { setupVoice: DONE, setupModel: MODEL_TODO }),
        ["off", "power-off", "neutral", WITH(setupStep("setupModel"), [MUTE])]],
    ["the AI model to sign in", up(down("unconfigured"), { setupVoice: DONE, setupModel: MODEL_SIGN_IN }),
        ["off", "power-off", "neutral", WITH(setupStep("setupModel"), [MUTE])]],
    ["gate node", up(down("node")), ["off", "power-off", "neutral", tip("Jarvis needs Node 22 or later", ["Use the requirement notice to install Node.", MUTE])]],
    ["gate lock unknown", up(down("lock-unknown")), ["off", "power-off", "neutral", tip("Jarvis is checking the screen lock", ["Wait for the screen lock check.", MUTE])]],
    ["gate locked", up(down("locked")), ["off", "power-off", "neutral", tip("Jarvis is off while the screen is locked", ["Unlock the screen to use Jarvis.", MUTE])]],
    ["thinking", up(THINKING), ["working", "brain", "info", tip("Jarvis is thinking", [STOP, MUTE])]],
    ["cancelling a turn", up({ turn: { kind: "cancelling", gen: 1, op: 4, deadline: 70 } }), ["working", "brain", "info", tip("Jarvis is thinking", [STOP, MUTE])]],
    ["speaking", up({ playback: { kind: "playing", gen: 1, op: 5, source: 4, interruptible: true, admission: { kind: "started" }, deadline: null } }),
        ["speaking", "volume-2", "accent", tip("Jarvis is speaking", [STOP, MUTE])]],
    ["confirming", up({ approval: { kind: "held", purpose: "action", gen: 1, op: 6, id: "a1", digest: "d1", deadline: 90, shownAt: null,
        physical: true, text: "Fixture action", tool: "fixture", timeoutMs: 1000, cancellable: false, brain: 4 } }),
        ["working", "brain", "info", tip("Jarvis is waiting for your confirmation", [CONFIRM, MUTE])]],
    ["acting", up({ action: { kind: "running", gen: 1, op: 7, tool: "shell", brain: 4, limit: { kind: "expired" }, cancellation: { kind: "available" } } }),
        ["working", "brain", "info", tip("Jarvis is running a task", [STOP, MUTE])]]
];

function bent(regions, change) {
    const values = up(regions);
    change(values.detail);
    return values;
}
const REFUSALS = [
    ["daemon tone outside its set", { daemon: { tone: "ok", text: "Ready" } }, /^jarvis widget: daemon=\{"tone":"ok","text":"Ready"\} unexpected$/],
    ["daemon without text", { daemon: { tone: "info" } }, /^jarvis widget: daemon=/],
    ["daemon null", { daemon: null }, /^jarvis widget: daemon=null unexpected$/],
    ["audio tone outside its set", { audio: { tone: "warning", text: "Reading devices" } }, /^jarvis widget: audio=/],
    ["detail not a record", { detail: "idle" }, /^jarvis widget: detail="idle" unexpected$/],
    ["detail without a state", { detail: { phase: "idle", seq: 1, state: null } }, /^jarvis widget: detail=/],
    ["unknown capture", bent({}, d => { d.state.capture = { kind: "ajar" }; }), /^jarvis widget: capture=\{"kind":"ajar"\} unexpected$/],
    ["unknown mute", bent({}, d => { d.state.mute = { kind: "maybe" }; }), /^jarvis widget: mute=/],
    ["unknown gate kind", bent({}, d => { d.state.gate = { kind: "sideways" }; }), /^jarvis widget: gate=/],
    ["unknown gate reason", bent(down("locked"), d => { d.state.gate.reason = "asleep"; }), /^jarvis widget: gate=\{"kind":"down","reason":"asleep"\} unexpected$/],
    ["listening with capture closed", bent({}, d => { d.phase = "listening"; }), /^jarvis widget: phase="listening" unexpected$/],
    ["down with the gate up", bent({}, d => { d.phase = "down"; }), /^jarvis widget: phase="down" unexpected$/],
    ["unknown phase", bent({}, d => { d.phase = "dreaming"; }), /^jarvis widget: phase="dreaming" unexpected$/],
    ["error without a fault", bent({}, d => { d.phase = "error"; }), /^jarvis widget: fault=\{"kind":"none"\} unexpected$/],
    ["keys missing talk", up({}), /^jarvis widget: keys=/, { mute: "M", stop: "S", confirm: "C" }],
    ["keys string instead of record", up({}), /^jarvis widget: keys="keys" unexpected$/, "keys"],
    ["mode outside manifest options", up({}), /^jarvis widget: mode="tap" unexpected$/, KEYS, "tap"]
];

function callView(view, values, keys = KEYS, mode = "hold") {
    return view.view(copy(values), copy(keys), mode);
}

function verify(view) {
    const loading = SetupGate.readiness({ kind: "answered", causes: ["speech=local-loading"] });
    const checking = SetupGate.readiness({ kind: "checking" });
    for (const [label, values, want] of [
        ["speech loading", up(down("unconfigured"), loading), ["loading", "loader", "info"]],
        ["loading admitted", up({}, loading), ["loading", "loader", "info"]],
        ["setup checking", up(down("unconfigured"), checking), ["loading", "loader", "info"]],
        ["loading with open microphone", up({ ...down("unconfigured"), ...OPEN }, loading), ["listening", "audio-lines", "accent"]],
        ["loading with daemon danger", up(down("unconfigured"), { ...loading, daemon: FLOOR }), ["problem", "circle-alert", "danger"]],
        ["loading with audio danger", up(down("unconfigured"), { ...loading, audio: OVERFLOW }), ["problem", "circle-alert", "danger"]],
        ["checking setup with Session fault", up({ fault: { kind: "error", reason: "brain=stream-error", retry: 0 } }, loading), ["problem", "circle-alert", "danger"]],
        ["loading while muted", up({ ...down("unconfigured"), ...MUTED }, loading), ["muted", "mic-off", "neutral"]],
        ["loading with missing model", up(down("unconfigured"), SetupGate.readiness({ kind: "answered", causes: ["speech=local-loading", "brain=unselected"] })), ["off", "power-off", "neutral"]],
        ["missing command with no setup action", up(down("unconfigured"), { setupVoice: { tone: "warning", action: false }, setupModel: MODEL_DONE }), ["off", "power-off", "neutral"]],
        ["missing command while model checks", up(down("unconfigured"), { setupVoice: { tone: "warning", action: false }, setupModel: checking.setupModel }), ["off", "power-off", "neutral"]],
        ["checking tone with setup action", up(down("unconfigured"), { setupVoice: { tone: "info", action: true }, setupModel: MODEL_DONE }), ["off", "power-off", "neutral"]],
        ["unpublished model while voice checks", up(down("unconfigured"), { setupVoice: loading.setupVoice }), ["off", "power-off", "neutral"]],
        ["both steps done with gate down", up(down("unconfigured"), SetupGate.readiness({ kind: "answered", causes: [] })), ["off", "power-off", "neutral"]],
        ["loading while locked", up(down("locked"), loading), ["off", "power-off", "neutral"]]
    ]) {
        let out;
        assert.doesNotThrow(() => { out = callView(view, values); }, label);
        assert.deepEqual([out.state, out.icon, out.tone], want, label);
    }
    assert.deepEqual([callView(view, up({}), KEYS, "toggle").tooltipDetails[0], callView(view, up({}), KEYS, "always").tooltipDetails[0]],
        ["Press Super+Right Alt to start talking.", "Say Hey Jarvis, or press Super+Right Alt."], "talk modes name the Talk key");
    assert.deepEqual([
        callView(view, up({}), UNBOUND, "hold").tooltipDetails[0],
        callView(view, up(THINKING), UNBOUND).tooltipDetails[0],
        callView(view, up({ approval: { kind: "held", purpose: "action", gen: 1, op: 6, id: "a1", digest: "d1", deadline: 90, shownAt: null, physical: true, text: "Fixture action", tool: "fixture", timeoutMs: 1000, cancellable: false, brain: 4 } }), UNBOUND).tooltipDetails[0],
        callView(view, up(MUTED), UNBOUND).tooltipDetails[0]
    ], ["Set Talk key in Settings > Jarvis.", "Set Stop key in Settings > Jarvis.",
        "Confirm on screen, or set Confirm key in Settings > Jarvis.", "Click, or set Mute key in Settings > Jarvis, to unmute."],
        "unbound keys tell the user to set that key");

    // The keys as the widget and the console hand them in: the manifest's
    // default binds spelled by the shell's own KeyNavLogic.
    assert.deepEqual(copy(view.spelledKeys(MANIFEST_KEYS, KeyNavLogic.keyCaps)), KEYS, "the default keys spell as people read them");
    assert.deepEqual(copy(view.spelledKeys(null, KeyNavLogic.keyCaps)), UNBOUND, "no shell reads as no key");
    assert.deepEqual(view.spelledKeys({ ...MANIFEST_KEYS, stop: null }, KeyNavLogic.keyCaps).stop, null, "an unbound key stays unbound");
    assert.deepEqual(copy(view.spelledKeys({}, KeyNavLogic.keyCaps)), UNBOUND, "an absent key reads unbound, not spelled empty");

    assert.equal(view.approvalPrompt(null), null);
    for (const tool of ["files.delete", "apps.open", "harness.files", "filesOther", "fixture"]) {
        for (const purpose of ["action", "release"]) {
            const prompt = view.approvalPrompt({ tool, purpose, text: "A\nBB\nCCC" });
            const file = purpose === "action" && ["files.delete", "apps.open", "harness.files"].includes(tool);
            assert.equal(prompt.filePrompt, file);
            assert.equal(prompt.detail, file);
            assert.deepEqual([prompt.question, prompt.path, prompt.payload].map(value => Buffer.byteLength(value)),
                file ? [1, 2, 3] : [8, 0, 0]);
        }
    }
    const incomplete = view.approvalPrompt({ tool: "files.delete", purpose: "action", text: "A" });
    assert.equal(incomplete.detail, false);
    assert.deepEqual([incomplete.question, incomplete.path, incomplete.payload].map(value => Buffer.byteLength(value)), [1, 0, 0]);
    assert.deepEqual(Object.keys(view.LOOKS).sort(), ["listening", "loading", "muted", "off", "problem", "ready", "speaking", "working"], "the widget states");
    const icons = [];
    for (const [state, look] of Object.entries(view.LOOKS)) {
        assert.ok(Object.prototype.hasOwnProperty.call(Lucide.ICONS, look.icon), state + ": icon " + look.icon + " ships");
        icons.push(look.icon);
    }
    assert.equal(new Set(icons).size, icons.length, "each widget state has its own icon");
    for (const [label, values, want] of CASES) {
        let got;
        try {
            const out = callView(view, values);
            got = [out.state, out.icon, out.tone, out.tooltip, out.tooltipDetails];
        } catch (e) {
            got = "threw: " + e.message;
        }
        assert.deepEqual(copy(got), expected(want, view), label);
        if (typeof got !== "string") assert.equal(/[a-z-]+=[a-z0-9-]/.test(got[3]), false, label + ": no keyed cause on screen");
    }
    for (const kind of ["slow", "device", "home", "brain", "voice", "audio", "other"])
        assert.equal(typeof view.FAULT_TEXT[kind].title === "string" && typeof view.FAULT_TEXT[kind].action === "string", true, kind);
    const words = [view.GATE_TEXT.unconfigured.action, ...view.SETUP_TEXT.map(([, line]) => line.action)];
    assert.equal(new Set(words).size, words.length, "each remaining step says its own sentence");
    for (const [label, values, pattern, keys = KEYS, mode = "hold"] of REFUSALS)
        assert.throws(() => callView(view, values, keys, mode), error => pattern.test(error.message), label);
    for (const cause of ["speech=local-memory-insufficient", "speech=local-memory-unavailable"]) {
        const status = SetupGate.readiness({ kind: "answered", causes: [cause] });
        const got = callView(view, up(down("unconfigured"), status));
        assert.deepEqual([got.state, got.icon, got.tone], ["off", "power-off", "neutral"]);
        assert.equal(got.tooltip.startsWith(status.setupVoice.text), true);
        assert.equal(got.tooltipDetails[0].includes(status.setupVoice.hint), true, "the widget carries the published recovery explanation");
    }
    for (const causes of [["home=link", "brain=unselected"], ["guidance=home-too-large", "speech=local-loading"]]) {
        const status = SetupGate.readiness({ kind: "answered", causes });
        const got = callView(view, up(down("unconfigured"), status));
        assert.deepEqual([got.state, got.icon, got.tone], ["off", "power-off", "neutral"], causes[0]);
        assert.equal(got.tooltipDetails[0].includes(status.setupHome.hint), true, causes[0] + ": the widget says what to change in the home folder");
    }
    const idle = callView(view, up(down("unconfigured"), { ...SetupGate.readiness({ kind: "answered", causes: ["brain=unselected"] }), setupHome: { tone: "ok", text: "Done", hint: "fixture" } }));
    assert.equal(idle.tooltipDetails.join(" ").includes("fixture"), false);
}

verify(load(path.join(dir, "WidgetView.js")));

// Each control removes one rule from a copy of the view and keeps the text
// around it: [label, needle, replacement].
const CONTROLS = [
    ["memory explanation discarded", 'return { title: step.text, action: "Open Settings > Jarvis. " + step.hint };', 'return GATE_TEXT.unconfigured;'],
    ["checking setup reads off", 'state.gate.reason === "unconfigured" && setupChecking(values)', 'state.gate.reason === "unconfigured" && false'],
    ["checking hides an offered setup action", '!step || offered(step) ||', '!step ||'],
    ["a refused home folder reads as another step", 'if (down && state.gate.reason === "unconfigured" && homeRefused(values)) return textLook("off", homeText(values), muteOn, effectiveKeys);', ''],
    ["a home folder step with nothing to ask reads refused", 'return !!home && home.tone === "warning" && ', 'return !!home && '],
    ["missing requirements read checking", '(step.tone !== "info" && step.tone !== "ok")', 'false'],
    ["done steps read checking", 'return checking;', 'return true;'],
    ["cleared prompt retains a record", "if (hold === null) return null;", "if (hold === null) return {};"],
    ["file prompt loses its path", 'path: filePrompt && lines.length > 1 ? lines[1] : ""', 'path: filePrompt && lines.length > 1 ? lines[0] : ""'],
    ["file prompt repeats its path as detail", 'lines.slice(2).join("\\n")', 'lines.slice(1).join("\\n")'],
    ["detail flag is dropped", 'detail: filePrompt && lines.length > 2', 'detail: false'],
    ["an open microphone is not listening", "microphoneOpen(state.capture)) return", "false) return"],
    ["a daemon problem is not a problem", 'daemon.tone === "danger") return', 'false) return'],
    ["a Session error is not a problem", 'detail.phase === "error") return', 'false) return'],
    ["an audio problem is not a problem", 'audio.tone === "danger") return', 'false) return'],
    ["no state yet is not loading", 'if (state === null) return textLook("loading"', 'if (false) return textLook("loading"'],
    ["mute is not shown", 'if (muteOn) return look("muted"', 'if (false) return look("muted"'],
    ["muting is not muted", 'case "muting": case "on": return true;', 'case "on": return true;'],
    ["a lowered gate is not off", 'if (down) return textLook("off"', 'if (false) return textLook("off"'],
    ["loading reads ready", 'return look("loading", "Jarvis is loading its voice", ["Wait for local voice to load."], muteOn, effectiveKeys);', 'return look("ready", "Jarvis is ready", [readyAction(effectiveMode, effectiveKeys)], muteOn, effectiveKeys);'],
    ["loading overrides a privacy gate", '(!down || state.gate.reason === "unconfigured") && voiceLoading(values)', 'voiceLoading(values)'],
    ["thinking reads speaking", 'case "thinking":\n        return look("working", WORK_TEXT[detail.phase], [stopAction(effectiveKeys)], muteOn, effectiveKeys);', 'case "thinking":\n        return look("speaking", "Jarvis is speaking", [stopAction(effectiveKeys)], muteOn, effectiveKeys);'],
    ["speaking reads working", 'return look("speaking", "Jarvis is speaking", [stopAction(effectiveKeys)], muteOn, effectiveKeys);', 'return look("working", "Jarvis is speaking", [stopAction(effectiveKeys)], muteOn, effectiveKeys);'],
    ["the click line follows the icon, not the mute region", 'var verb = muteOn ? "unmute" : "mute";', 'var verb = false ? "unmute" : "mute";'],
    ["any report tone is accepted", "tones.indexOf(value.tone) === -1", "false"],
    ["an unknown capture is closed", 'default: refuse("capture", capture);', "default: return false;"],
    ["an unknown gate reason is off", 'if (!hasOwn(GATE_TEXT, gate.reason)) refuse("gate", gate);', ""],
    ["an unexpected phase reads ready", 'refuse("phase", detail.phase);', 'return look("ready", "Jarvis is ready", [readyAction(effectiveMode, effectiveKeys)], muteOn, effectiveKeys);'],
    ["a fault shows its keyed reason", 'return fault.kind === "retrying" ? RETRYING : FAULT_TEXT[kind];', 'return { title: "Problem: " + fault.reason, action: RESTART };'],
    ["a brain fault reads as another", '[/^(brain|net)=/, "brain"],', ""],
    ["a refused model reads as any brain fault", '    [MODEL_REFUSED, "model"],\n', ""],
    ["a refused model is not named", 'title: FAULT_TEXT.model.title + " " + MODEL_REFUSED.exec(fault.reason)[1]', "title: FAULT_TEXT.model.title"],
    ["a home folder fault reads as another", '[/^(home=|guidance=home-)/, "home"],', ""],
    ["a home text fault reads as another", '[/^(home=|guidance=home-)/, "home"],', '[/^home=/, "home"],'],
    ["a slow answer reads as another", '[/^thinking-timeout$/, "slow"],', ""],
    ["a retry asks for a restart", 'fault.kind === "retrying" ? RETRYING : FAULT_TEXT[kind]', "FAULT_TEXT[kind]"],
    ["an audio problem shows its text", 'return textLook("problem", AUDIO_TEXT, muteOn, effectiveKeys)', 'return look("problem", "Audio problem: " + audio.text, [RESTART], muteOn, effectiveKeys)'],
    ["an unconfigured gate names no step", 'state.gate.reason === "unconfigured" ? unconfiguredText(values) : GATE_TEXT[state.gate.reason]', 'GATE_TEXT[state.gate.reason]'],
    ["a step done reads as to do", 'return step.action === true || typeof step.action === "string";', "return step.action !== undefined;"],
    ["a named action reads as none", ' || typeof step.action === "string";', ";"],
    ["the AI model reads before local voice", "function unconfiguredText(values) {\n    for (var i = 0; i < SETUP_TEXT.length; i++) {", "function unconfiguredText(values) {\n    for (var i = SETUP_TEXT.length - 1; i >= 0; i--) {"],
    ["keys are not spelled", 'key === null || key === undefined ? null : caps(key).join("+");', 'key;'],
    ["an absent key spells empty", 'key === null || key === undefined ? null : caps(key).join("+");', 'key === null ? null : caps(key).join("+");'],
    ["shared icons are accepted", '"working": { icon: "brain", tone: "info" }', '"working": { icon: "loader", tone: "info" }'],
    ["toggle mode reads like hold", 'if (mode === "toggle") return keys.talk === null ? keySetting("Talk") : "Press " + keys.talk + " to start talking.";', 'if (mode === "toggle") return keys.talk === null ? keySetting("Talk") : "Hold " + keys.talk + " and speak.";'],
    ["unbound talk key names no setting", 'if (mode === "hold") return keys.talk === null ? keySetting("Talk") : "Hold " + keys.talk + " and speak.";', 'if (mode === "hold") return keys.talk === null ? "Hold Talk and speak." : "Hold " + keys.talk + " and speak.";'],
    ["unbound stop key names no setting", 'return keys.stop === null ? keySetting("Stop") : "Press " + keys.stop + " to stop.";', 'return keys.stop === null ? "Press Stop to stop." : "Press " + keys.stop + " to stop.";'],
    ["unbound confirm key names no setting", 'return keys.confirm === null ? "Confirm on screen, or set Confirm key in Settings > Jarvis."', 'return keys.confirm === null ? "Confirm on screen, or press Confirm."'],
    ["unbound mute key names no setting", 'return keys.mute === null ? "Click, or set Mute key in Settings > Jarvis, to " + verb + "."', 'return keys.mute === null ? "Click or press Mute to " + verb + "."']
];

const source = fs.readFileSync(path.join(dir, "WidgetView.js"), "utf8");
const scratchRoot = path.join(__dirname, "..", "tmp");
fs.mkdirSync(scratchRoot, { recursive: true });
const temp = fs.mkdtempSync(path.join(scratchRoot, "jarvis-widget-control-"));
try {
    for (const [label, needle, replacement] of CONTROLS) {
        assert.equal(source.split(needle).length, 2, `control "${label}": the text to replace must occur once`);
        const changed = source.replace(needle, () => replacement);
        assert.notEqual(changed, source, `control "${label}": the copy changed`);
        const file = path.join(temp, "WidgetView.js");
        fs.writeFileSync(file, changed);
        let failure = null;
        try {
            verify(load(file));
        } catch (e) {
            failure = e;
        }
        assert.ok(failure instanceof assert.AssertionError, `control "${label}": the suite passed on a copy without that rule` +
            (failure === null ? "" : ", or failed on something other than an assertion: " + failure));
    }
} finally {
    fs.rmSync(temp, { recursive: true, force: true });
}

// Execute Bubble's shipped callbacks with controlled GUI/render ordering.
// The nested bubble row proves rendering; this case proves which queued frame
// may acknowledge a real Session hold, without a second frame owner.
function approvalFrames(source) {
    let state = detail({ conversation: { kind: "active" }, gen: 1, ...THINKING }).state;
    let at = 0;
    const dispatch = e => {
        const result = Session.reduce(state, { ...e, at });
        state = result.state;
        return result.effects;
    };
    const later = [];
    const root = { shown: true, visible: true, presented: true, displayedHold: null,
        approvalFrames: [], synchronizedHold: null,
        service: { shownApproval: (bubble, hold) => dispatch({ type: "shown", gen: hold.gen, op: hold.op, id: hold.id }) } };
    Object.defineProperty(root, "hold", { get: () => state.approval.kind === "held" ? state.approval : null });
    const approvalText = { height: 40, implicitHeight: 40 };
    Object.defineProperty(approvalText, "text", { get: () => root.hold?.text ?? "" });
    const ctx = vm.createContext({ root, approvalText, Qt: { callLater: fn => later.push(fn) } });
    for (const name of ["approvalPolished", "approvalSynchronized", "approvalSwapped"]) {
        const matches = [...source.matchAll(new RegExp("^    function " + name + "\\(\\) \\{\\n[\\s\\S]*?^    \\}", "gm"))];
        assert.equal(matches.length, 1, "one shipped Bubble callback: " + name);
        const run = vm.runInContext("(function() { with(root) { return (" + matches[0][0] + ").call(root); } })", ctx);
        root[name] = run;
    }
    const flush = () => { while (later.length) later.shift()(); };
    const propose = id => dispatch({ type: "approval", gen: 1, op: 4, id, digest: id, purpose: "action",
        text: "Fixture action", physical: false, tool: "fixture", timeoutMs: 1000, cancellable: false });
    const confirm = h => dispatch({ type: "confirm", gen: h.gen, id: h.id, digest: h.digest, source: "button" });

    root.approvalPolished();
    propose("first");
    const h = root.hold;
    root.approvalPolished();
    root.approvalSynchronized();
    root.approvalSwapped();
    flush();
    assert.equal(state.approval.shownAt, null, "an earlier frame cannot acknowledge a newer request");
    at = 1000;
    assert.equal(confirm(h).find(e => e.kind === "confirm-refused")?.reason, "early",
        "confirmation stays refused until the request's frame completes");
    root.approvalSynchronized();
    root.approvalSwapped();
    flush();
    assert.equal(state.approval.shownAt, 1000, "the matching frame acknowledges its request");
    at += Session.APPROVAL_DRAW_MS;
    assert.ok(confirm(h).some(e => e.kind === "tool-start"), "the matching frame starts the full draw interval");

    state.action = { kind: "none" };
    propose("second");
    root.displayedHold = null;
    root.approvalPolished();
    root.approvalSynchronized();
    root.approvalSwapped();
    dispatch({ type: "approval-cancel", gen: 1, id: "second" });
    propose("third");
    flush();
    assert.equal(state.approval.shownAt, null, "a deferred acknowledgment cannot cross request replacement");
    root.presented = false;
    root.approvalPolished();
    root.approvalSynchronized();
    root.approvalSwapped();
    flush();
    assert.equal(state.approval.shownAt, null, "a hidden host cannot acknowledge");
}
const bubble = fs.readFileSync(path.join(dir, "Bubble.qml"), "utf8");
approvalFrames(bubble);
const frameNeedle = "const drawn = synchronizedHold;";
assert.equal(bubble.split(frameNeedle).length, 2, "one frame identity control match");
assert.throws(() => approvalFrames(bubble.replace(frameNeedle, "const drawn = root.hold;")), assert.AssertionError,
    "delivery from the current hold must fail the earlier-frame assertion");
console.log(`test-jarvis-widget: ok cases=${CASES.length} refusals=${REFUSALS.length} controls=${CONTROLS.length + 1} frame-control=detected`);
