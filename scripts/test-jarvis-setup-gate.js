#!/usr/bin/env node
// Which setup step Jarvis offers while a command its setup needs is missing,
// shell/plugins/vgs.jarvis/SetupGate.js, under node: the value a setup reader
// publishes for its probe's value and the requirements capability's missing
// list, the value of a requirement's own Install row, and the Setup
// section's summary and steps from the daemon's answer, read by their tone,
// action and line count. The shipped account and service callbacks also
// determine the model action. No shell process, network or audio is used.
//
// The controls at the end edit a copy of the library, one rule at a time,
// and require this suite to fail an assertion on each copy.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const vm = require("node:vm");
const cp = require("node:child_process");
const { load } = require("../bin/lib/qml-library.js");
const judge = load(path.join(__dirname, "..", "shell", "Core", "PluginLogic.js"));
const settings = load(path.join(__dirname, "..", "shell", "plugins", "vgs.settings", "Steps.js"));
// Required Setup projection and Details action decisions from Steps.js.
const settingsRows = sections => sections.reduce((all, section) => all.concat(section.items), []);
// The facts the Details tab draws of STATUS while Jarvis is on
// (Steps.detailEntries), each with the actions beside it
// (Steps.detailButtons).
const jarvisOn = { enabled: true, name: "Jarvis", error: "" };
const detailActionRows = status => Array.from(settings.detailEntries(status)).map(entry => {
    const buttons = settings.detailButtons(entry, jarvisOn);
    return { key: entry.key, entry, button: buttons.action, aside: buttons.aside };
});

const protocol = load(path.join(__dirname, "..", "shell", "plugins", "vgs.jarvis", "JarvisProtocol.js"));
const session = load(path.join(__dirname, "..", "shell", "plugins", "vgs.jarvis", "Session.js"));
const widget = load(path.join(__dirname, "..", "shell", "plugins", "vgs.jarvis", "WidgetView.js"));
const pageReference = load(path.join(__dirname, "..", "shell", "Commons", "PageReference.js"));
let manifestControlCount = 0;

function changedManifest(source, change) {
    const raw = JSON.parse(source);
    const before = JSON.stringify(raw);
    change(raw);
    const after = JSON.stringify(raw);
    assert.notEqual(after, before, "the manifest control changes its field");
    return after;
}
function withoutOption(options, value) {
    assert.equal(options.filter(option => option.value === value).length, 1, value + ": one option to remove");
    return options.filter(option => option.value !== value);
}


// This terminal only sends the request. It never owns capture or opens audio.
function verifyMicrophoneAction(script, root) {
    const library = path.join(root, "tui-lib"), command = path.join(root, "vgshell");
    fs.writeFileSync(library, 'vgs_tui_header() { printf "%s\\n" "$@"; }\nvgs_tui_error() { printf "%s\\n" "$*" >&2; }\n');
    fs.writeFileSync(command, '#!/bin/bash\n[[ $# == 6 && $1 == ipc && $2 == call && $3 == vgs.jarvis && $4 == invoke && $5 == check-microphone && -z $6 ]] || exit 2\nprintf "%s\\n" "$CHECK_REPLY"\n', { mode: 0o700 });
    for (const reply of ["ok", "refused: microphone-check=unavailable"]) {
        const result = cp.spawnSync("/bin/bash", [script], { encoding: "utf8",
            env: { PATH: root, VGS_TUI_LIB: library, CHECK_REPLY: reply } });
        assert.equal(result.status, reply === "ok" ? 0 : 1, "the action reports daemon refusal");
        assert.match(result.stdout, /Say Hey Jarvis.*three seconds/);
        assert.match(result.stdout, /Settings > Jarvis/);
        if (reply !== "ok") assert.match(result.stderr, /cannot check the microphone/);
    }
}

// The Preview screen asks the service, and for a cloud voice asks the
// user first; it speaks nothing itself. Each refusal key shows its own
// message. A stub vgshell logs each invoke and answers from the scenario.
function runScreen(script, root, scenario) {
    const library = path.join(root, "tui-lib"), command = path.join(root, "vgshell"), log = path.join(root, "screen.log");
    fs.rmSync(log, { force: true });
    fs.writeFileSync(library, [
        'vgs_tui_header() { :; }', 'vgs_tui_success() { printf "success\\n" >> "$SCREEN_LOG"; }',
        'vgs_tui_error() { printf "%s\\n" "$*" >&2; }',
        'vgs_tui_confirm() { printf "confirm\\n" >> "$SCREEN_LOG"; [[ $CONFIRM == yes ]]; }',
        'vgs_tui_close_prompt() { printf "close %s\\n" "$1" >> "$SCREEN_LOG"; }', ""].join("\n"));
    fs.writeFileSync(command, '#!/bin/bash\n[[ $# == 6 && $1 == ipc && $2 == call && $3 == vgs.jarvis && $4 == invoke ]] || exit 2\n'
        + 'printf "%s %s\\n" "$5" "$6" >> "$SCREEN_LOG"\ncase $6 in kind) printf "%s\\n" "$KIND" ;; play) printf "%s\\n" "$PLAY" ;; *) printf "%s\\n" "$FILE" ;; esac\n', { mode: 0o700 });
    const result = cp.spawnSync("/bin/bash", [script], { encoding: "utf8",
        env: { PATH: root + ":/usr/bin:/bin", VGS_TUI_LIB: library, SCREEN_LOG: log, KIND: "", PLAY: "", FILE: "", CONFIRM: "", ...scenario } });
    return { status: result.status, stderr: result.stderr, log: fs.existsSync(log) ? fs.readFileSync(log, "utf8").trim().split("\n") : [] };
}
function verifyPreviewAction(script, root) {
    const run = scenario => runScreen(script, root, scenario);
    assert.deepEqual(run({ KIND: "local", PLAY: "ok" }), { status: 0, stderr: "", log: ["preview-voice kind", "preview-voice play", "success"] },
        "a local preview plays without asking");
    assert.deepEqual(run({ KIND: "cloud", PLAY: "ok", CONFIRM: "yes" }).log, ["preview-voice kind", "confirm", "preview-voice play", "success"],
        "a cloud preview asks before it plays");
    assert.deepEqual(run({ KIND: "cloud", PLAY: "ok", CONFIRM: "no" }), { status: 0, stderr: "", log: ["preview-voice kind", "confirm"] },
        "a cloud preview the user declines plays nothing");
    const causes = ["refused: preview=muted", "refused: preview=busy", "refused: preview=down", "refused: jarvis=not-ready"].map(key => {
        const asked = run({ KIND: key });
        assert.deepEqual([asked.status, asked.log], [1, ["preview-voice kind"]], key + ": nothing plays");
        assert.notEqual(asked.stderr, "", key + ": the screen says why");
        const played = run({ KIND: "local", PLAY: key });
        assert.deepEqual([played.status, played.stderr], [1, asked.stderr], key + ": the same cause when the play is refused");
        return asked.stderr;
    });
    assert.equal(new Set(causes).size, causes.length, "each refusal key has its own cause");
}
// Edit uses the shared production helper. Only IPC and editors are stand-ins;
// the close prompt records its status instead of waiting for a key.
function verifyEditAction(script, root) {
    const library = path.join(root, "edit-lib"), log = path.join(root, "edit.log");
    const realLibrary = path.join(__dirname, "..", "bin/lib/tui.sh");
    fs.writeFileSync(library, 'source "' + realLibrary + '"\nvgs_tui_close_prompt() { printf "close %s\\n" "$1" >> "$SCREEN_LOG"; }\n');
    fs.writeFileSync(path.join(root, "vgshell"), '#!/bin/bash\n[[ $# == 6 && $1 == ipc && $2 == call && $3 == vgs.jarvis && $4 == invoke && $5 == personality-file && -z $6 ]] || exit 2\nprintf "personality-file\\n" >> "$SCREEN_LOG"\nprintf "%s\\n" "$FILE"\n', { mode: 0o700 });
    for (const name of ["nvim", "nano", "code", "codium"])
        fs.writeFileSync(path.join(root, name), '#!/bin/bash\nprintf "' + name + ' %s\\n" "$*" >> "$SCREEN_LOG"\nprintf "editor: error=fixture\\n" >&2\nexit "$EDIT_STATUS"\n', { mode: 0o700 });
    const file = "/home/user/Jarvis/AGENTS.md";
    for (const [name, visual, editor, code, expected] of [
        ["visual", "nvim -R", "nano", 0, "nvim -R " + file],
        ["editor", "", "nano -w", 0, "nano -w " + file],
        ["code", "code --wait -w --reuse-window", "nano", 0, "code --reuse-window " + file],
        ["codium", "", "codium --wait", 0, "codium " + file],
        ["failed-editor", "nvim", "nano", 4, "nvim " + file],
        ["homeless", "nvim", "", 1, null]
    ]) {
        fs.rmSync(log, { force: true });
        const result = cp.spawnSync("/bin/bash", [script], { encoding: "utf8", timeout: 5000,
            env: { PATH: root, VGS_TUI_LIB: library, SCREEN_LOG: log,
                FILE: expected === null ? "refused: home=none" : file,
                VISUAL: visual, EDITOR: editor, EDIT_STATUS: String(code), VGS_TEST_RUN: "1" } });
        assert.equal(result.status, code, name + ": status");
        const calls = fs.readFileSync(log, "utf8").trim().split("\n");
        assert.deepEqual(calls, ["personality-file", ...(expected ? [expected] : []), ...(code ? ["close " + code] : [])], name + ": calls");
        if (expected) assert.equal(result.stderr, "editor: error=fixture\n", name + ": real editor error");
        else assert.notEqual(result.stderr, "", name + ": missing home cause");
    }
}

const file = path.join(__dirname, "..", "shell", "plugins", "vgs.jarvis", "SetupGate.js");
const manifest = judge.validateManifest(JSON.parse(fs.readFileSync(path.join(path.dirname(file), "manifest.json"), "utf8")), path.dirname(file)).manifest;

// The real Edit declaration must raise the installation notice when its
// picker is unavailable. Other Jarvis tools do not hold this file editor.
{
    const raw = JSON.parse(fs.readFileSync(path.join(path.dirname(file), "manifest.json"), "utf8"));
    function verifyEditRequirements(source) {
        const judged = judge.validateManifest(source, path.dirname(file));
        assert.equal(judged.ok, true);
        for (const [missing, expected] of [[[], []], [["gum"], ["gum"]], [["gio"], []], [["gio", "gum"], ["gum"]]]) {
            assert.deepEqual(Array.from(judge.tuiMissingRequirements(judged.manifest, "edit-personality", missing)), expected);
            const request = judge.tuiRunFor(judged.manifest, true, "/snapshot", { launcher: "present", busy: [], run: "fixture" }, "edit-personality", missing);
            assert.equal(request.ok, true);
            assert.equal(request.kind || "launch", expected.length ? "install" : "launch");
        }
    }
    verifyEditRequirements(raw);
    const withoutPicker = structuredClone(raw);
    withoutPicker.tui["edit-personality"].requires = ["gio"];
    assert.throws(() => verifyEditRequirements(withoutPicker), assert.AssertionError);
    console.log("test-jarvis-setup-gate: control=edit-picker-requirement rejected=true");
}

// Optional actions belong beside their fact on Details.
{
    const MOVED = [
        ["keyStore", "Add key"],
        ["accountSearch", "Accounts"],
        ["voicePreview", "Preview"],
        ["voiceKey", "Add key"],
        ["localRuntime", "Set up local voice"],
        ["input", "Check input"]
    ];
    const values = Object.fromEntries(MOVED.map(([key]) => [key, { tone: "warning", text: "To do", action: true }]));
    values.setupVoice = { tone: "ok", text: "Ready", action: "check" };
    const status = judge.statusRows(manifest, values);
    const tuis = judge.listedTuis(manifest);
    const setup = settingsRows(settings.setupSections(tuis, status));
    for (const [key, label] of MOVED) {
        const rows = detailActionRows(status).filter(row => row.key === key);
        assert.equal(rows.length, 1, key + ": one fact on Details");
        assert.equal(rows[0].button.label, label, key + ": its action stays beside that fact");
        assert.equal(setup.some(item => item.key === key), false, key + ": no optional row on Setup");
    }
    const INSTALLED = ["shell", "voxtype", "claude", "codex", "browserDriver"];
    const lacking = Object.fromEntries(INSTALLED.map(key => [key, { tone: "warning", text: "Not installed", action: true }]));
    const lackingStatus = judge.statusRows(manifest, lacking);
    assert.deepEqual(Array.from(lackingStatus).filter(entry => INSTALLED.includes(entry.key) && entry.action !== null).map(entry => String(entry.key)), [],
        "tool facts declare no install action");
}
const ABSENT = { tone: "warning", text: "Browser needs setup", action: true };
const READY = { tone: "ok", text: "Private browser ready", action: false };
const INPUT_ABSENT = { tone: "warning", text: "Input tools unavailable", action: true };
const INPUT_READY = { tone: "ok", text: "Keys ready; pointer ready", action: true };
const LOCAL_ABSENT = { tone: "warning", text: "Not set up", action: true };
const LOCAL_READY = { tone: "ok", text: "Ready: small", action: false };
// Required Setup and optional Settings actions from the published status:
// local voice, browser and input each offer their action once while it applies.
// Provider key actions belong beside their Account fields. [label, the voice the daemon runs, the daemon's causes, the local
// voice, browser and input readings, the rows of the tab that offer those
// three screens, the Local voice row's chip tone].
const ONCE = [
    ["partial under Local", "local", ["brain=unselected", "speech=local-not-set-up"], LOCAL_ABSENT, ABSENT, INPUT_ABSENT,
        { "setup-local": ["setupVoice"], "setup-browser": ["browser"], "setup-input": ["input"] }, "info"],
    ["local voice open under Local beside a done Voice step", "local", ["brain=unselected"], LOCAL_ABSENT, ABSENT, INPUT_ABSENT,
        { "setup-local": ["localRuntime"], "setup-browser": ["browser"], "setup-input": ["input"] }, "warning"],
    ["dictation setup leaves local voice maintenance available", "local", ["speech=dictation-absent"], LOCAL_ABSENT, ABSENT, INPUT_ABSENT,
        { "setup-local": ["localRuntime"], "setup-browser": ["browser"], "setup-input": ["input"] }, "warning"],
    ["done under Local", "local", [], LOCAL_READY, READY, INPUT_READY, { "setup-local": [], "setup-browser": [], "setup-input": ["input"] }, "success"],
    ["partial under Realtime", "realtime", ["brain=unselected"], LOCAL_ABSENT, ABSENT, INPUT_ABSENT,
        { "setup-local": ["localRuntime"], "setup-browser": ["browser"], "setup-input": ["input"] }, "info"]
];
// One task, setting up the local voice, takes one open step of the Setup
// tab (VGS-1508). Every pair of a Voice step and a Local voice reading under
// each voice: `voice` is [label, the daemon's answer the Voice step reads],
// `local` is [label, setup-local's reading, or the kind of a failed check
// (SetupGate.checkFailure)].
// The start causes of the jarvis-causes scenes whose Voice step reads Not
// checked: [label, the daemon's cause].
const FAILED_STARTS = [
    ["hello timeout", "jarvis: hello=timeout"],
    ["node too old", "jarvis: node=20.19.5 need=22"],
    ["daemon exit", "jarvis: daemon=exit code=1 status=0"],
    ["wire defect", "jarvis: protocol=identity"]];
const LOCAL_VOICE_TASK = {
    voice: [
        ["To do: not set up", { kind: "answered", causes: ["speech=local-not-set-up"] }],
        ["checking", { kind: "checking" }],
        ["stopped", { kind: "stopped" }],
        ["a failed start", { kind: "problem", cause: "jarvis: hello=timeout" }],
        ["done", { kind: "answered", causes: [] }],
        ["To do: did not start", { kind: "answered", causes: ["speech=local-not-ready"] }],
        ["timed out", { kind: "answered", causes: ["speech=local-ready-timeout"] }],
        ["loading", { kind: "answered", causes: ["speech=local-loading"] }],
        ["not enough memory", { kind: "answered", causes: ["speech=local-memory-insufficient"] }],
        ["dictation to set up", { kind: "answered", causes: ["speech=dictation-absent"] }],
        ["a cloud voice key to choose", { kind: "answered", causes: ["speech=live-key-required"] }]
    ],
    local: [
        ["not set up", LOCAL_ABSENT],
        ["setting up", { tone: "info", text: "Setting up", action: false }],
        ["ready", LOCAL_READY],
        ["needs verification", { tone: "warning", text: "Setup needs verification", action: true }],
        ["check failed", "failed"],
        ["check unreadable", "unreadable"],
        ["check timed out", "timeout"]
    ],
    providers: ["local", "elevenlabs", "realtime", "gemini"]
};
// [label, probe value, requires, missing, null for the probe value itself or
// the commands the withheld value names].
const SETUP = [
    ["nothing required", ABSENT, [], ["agent-browser"], null],
    ["required and found", ABSENT, ["agent-browser"], [], null],
    ["another command missing", ABSENT, ["agent-browser"], ["bwrap", "uv"], null],
    ["ready with its command found", READY, ["agent-browser"], ["bwrap"], null],
    ["required and missing", ABSENT, ["agent-browser"], ["bwrap", "agent-browser"], ["agent-browser"]],
    ["ready yet missing", READY, ["agent-browser"], ["agent-browser"], ["agent-browser"]],
    ["two of three missing", ABSENT, ["node", "agent-browser", "chromium"], ["chromium", "node"], ["node", "chromium"]]
];
// The local voice's dictation recording: [label, the voice, the lent state,
// the commands the scan misses, the cause the hello carries, the Voice
// step's value (the cause's DICTATION entry, the withheld form, LOADING or
// DONE as the Voice step carries them, with no action), whether it offers
// Set up dictation]. voxtype missing reads failed
// in the core. Set up dictation is offered where the core's setup applies;
// another voxtype or another microphone is the user's to change in Voice.
const DICTATION = [
    ["configured engine missing", "local", { daemon: "absent", device: "default", setup: { engine: "moonshine", model: "base", version: "voxtype 1.1.0", compiled: false, installed: true } }, [], "speech=dictation-absent", "named", true, ["moonshine"]],
    ["configured model missing", "local", { daemon: "absent", device: "default", setup: { engine: "moonshine", model: "base", version: "voxtype 1.1.0", compiled: true, installed: false } }, [], "speech=dictation-absent", "named", true, ["base"]],
    ["configured engine and model missing", "local", { daemon: "absent", device: "default", setup: { engine: "moonshine", model: "base", version: "voxtype 1.1.0", compiled: false, installed: false } }, [], "speech=dictation-absent", "named", true, ["moonshine", "base"]],
    ["voxtype missing", "local", { daemon: "failed", device: "" }, ["voxtype"], "speech=dictation-failed", "withheld", true],
    ["daemon absent", "local", { daemon: "absent", device: "" }, [], "speech=dictation-absent", "entry", true],
    ["daemon failed", "local", { daemon: "failed", device: "" }, [], "speech=dictation-failed", "entry", true],
    ["another voxtype", "local", { daemon: "elsewhere", device: "" }, [], "speech=dictation-elsewhere", "entry", false],
    ["another device", "local", { daemon: "ready", device: "alsa_input.usb-fixture" }, [], "speech=dictation-device", "entry", false],
    ["daemon starting", "local", { daemon: "starting", device: "" }, [], "speech=dictation-starting", "loading", false],
    ["ready on the default", "local", { daemon: "ready", device: "default" }, [], "", "done", false],
    ["Realtime voice", "realtime", { daemon: "failed", device: "" }, ["voxtype"], "", "done", false],
    ["ElevenLabs voice, which hears through dictation", "elevenlabs", { daemon: "failed", device: "" }, ["voxtype"], "speech=dictation-failed", "withheld", true],
    ["ElevenLabs voice on another device", "elevenlabs", { daemon: "ready", device: "alsa_input.usb-fixture" }, [], "speech=dictation-device", "entry", false],
    ["state unread", "local", null, [], "", "done", false]
];
// The Agent fleet row: [label, the home folder, the mail tool found in it,
// whether the row shows and offers setup].
const FLEET = [
    ["no home chosen", null, null, false, false],
    ["a home without the mail tool", "/h/Jarvis", null, true, true],
    ["a home with the mail tool", "/h/Jarvis", "/h/Jarvis/.agents/skills/mailbox/scripts/lane-mail", true, false]
];
// The Cloned voice setup row (VGS-1385): [label, setup-local's clone status
// answer, the voice the daemon runs, the published row's tone and action,
// whether it carries a hint of why, the TUI its press opens or null, the
// withheld reason of SetupGate's CLONE_WITHHELD it shows or null]. Set
// up is withheld for the Realtime voice and beside a tier off the graphics
// card; Remove recording stays offered whatever the voice. The row is an
// optional Details fact: no value of it opens the required Setup warning.
const CLONE_ANSWER = { tone: "info", text: "Not set up", action: "setup", recording: false, tierReady: true };
const CLONE_READY = { tone: "ok", text: "Ready", action: "remove", recording: true, tierReady: true };
const CLONED = [
    ["a resolved Local voice on the Large model offers setup", CLONE_ANSWER, "local", "info", "setup", false, "clone-voice", null],
    ["the Realtime voice withholds setup", CLONE_ANSWER, "realtime", "info", undefined, true, null, "provider"],
    ["the ElevenLabs voice withholds setup", CLONE_ANSWER, "elevenlabs", "info", undefined, true, null, "provider"],
    ["a tier off the graphics card withholds setup", { ...CLONE_ANSWER, tierReady: false }, "local", "info", undefined, true, null, "tier"],
    ["a ready cloned voice offers Remove and says what the recording gives", CLONE_READY, "local", "ok", "remove", true, "clone-voice-remove", null],
    ["a recording keeps Remove under the Realtime voice", CLONE_READY, "realtime", "ok", "remove", true, "clone-voice-remove", "provider"],
    ["a recording keeps Remove beside another tier", { ...CLONE_READY, tone: "warning", tierReady: false }, "local", "info", "remove", true, "clone-voice-remove", "tier"],
    ["a failed read offers setup", { tone: "warning", text: "Setup check failed", action: true }, "local", "info", "setup", false, "clone-voice", null],
    ["a timed-out read words its state", { tone: "warning", text: "Setup check timed out", hint: "Try again", action: true, lines: ["setup=probe-timeout"] },
        "local", "info", "setup", true, "clone-voice", null],
    ["a setup in progress offers nothing", { ...CLONE_ANSWER, text: "Setting up", action: false }, "local", "info", undefined, false, null, null],
];
// A hint's sentences and the copy rule are the manifest judge's
// (judge.hintSentences, judge.hintFits).
function oneSentence(text) {
    return judge.hintSentences(text).length === 1 && judge.hintFits(text);
}
function verifyClonedVoice(gate, judged) {
    for (const [label, answer, provider, tone, action, reasoned, tui, reason] of CLONED) {
        const value = plain(gate.clonedVoiceStep(answer, provider));
        assert.equal(judge.statusWrite(judged, {}, "clonedVoiceSetup", value).ok, true, label + ": the manifest judge accepts the row");
        assert.deepEqual([value.tone, value.action, value.hint !== undefined], [tone, action, reasoned], label);
        assert.deepEqual(keyedCauses(value, ["text", "hint", "lines"]), [], label + ": the row draws no keyed cause");
        const withheld = reason === null ? null : gate.CLONE_WITHHELD[reason];
        assert.equal(reason === null ? Object.values(gate.CLONE_WITHHELD).some(row => row.hint === value.hint) : value.hint === withheld.hint, reason !== null,
            label + ": the hint names " + (reason ?? "no withheld reason"));
        if (withheld !== null && action === undefined) assert.equal(value.text, withheld.text, label + ": the text names the reason");
        assert.equal(value.hint === gate.CLONE_READY_HINT, tone === "ok" && reason === null, label + ": only a ready row with nothing withheld takes the done hint");
        const row = judge.statusRows(judged, { clonedVoiceSetup: value }).find(entry => entry.key === "clonedVoiceSetup");
        assert.deepEqual([row.action.offered, row.action.tui || null], [tui !== null, tui], label + ": its press");
        const tuis = judge.listedTuis(judged);
        assert.equal(settings.setupNeeds([row], [], true).open, false, label + ": the row alone opens no Setup needed");
        assert.equal(settings.detailEntries([row]).length, 1, label + ": Details draws it once");
        const steps = settingsRows(settings.setupSections(tuis, judge.statusRows(judged,
            { setupVoice: { tone: "warning", text: "To do", action: "setup" }, clonedVoiceSetup: value })));
        assert.equal(steps.some(item => item.key === "clonedVoiceSetup"), false, label + ": the optional cloned voice stays off Setup");
        assert.deepEqual(detailActionRows([row]).map(line => line.key), ["clonedVoiceSetup"],
            label + ": the cloned voice action belongs beside its fact on Details");
        if (tui !== null)
            assert.deepEqual(plain(judge.statusActionRequest(judged, "vgs.jarvis", true, { clonedVoiceSetup: value }, "clonedVoiceSetup")),
                { ok: true, kind: "tui", name: tui }, label + ": the press opens its TUI");
    }
    assert.notEqual(gate.CLONE_READY_HINT, judged.status.clonedVoiceSetup.hint, "the done hint is not the declared setup instruction");
    assert.equal(oneSentence(gate.CLONE_READY_HINT), true, "the ready hint is one sentence");
    assert.equal(oneSentence(judged.status.clonedVoiceSetup.hint), true, "the declared setup hint is one sentence");
    assert.equal(judged.tui["clone-voice"].requires.includes("pw-record"), true, "the setup TUI needs its recorder");
}

// A command with a floor: [label, missing, outdated, expected value]. Its
// row says whether it is missing, below its floor or found, and offers no
// action: the page's Requirements section installs or updates it.
const FLOORED = [
    ["found at its floor", ["bwrap"], ["pi"], { tone: "ok", text: "Installed" }],
    ["missing", ["agent-browser"], [], { tone: "warning", text: "Not installed" }],
    ["below its floor", [], ["pi", "agent-browser"], { tone: "warning", text: "Needs an update" }]
];
// [label, command, missing, expected value].
const REQUIREMENT = [
    ["found", "agent-browser", [], { tone: "ok", text: "Installed" }],
    ["another command missing", "agent-browser", ["bwrap"], { tone: "ok", text: "Installed" }],
    ["missing", "agent-browser", ["bwrap", "agent-browser"], { tone: "warning", text: "Not installed" }]
];

// The Setup section from the daemon's answer: [label, answer, the summary's
// tone, the steps still to do, the steps to do that keep their declared
// hint, the AI model's named action while to do, "key" when left out, null
// for none]. A
// step to do is a warning with its action and, unless its action already
// says what it asks, a hint of its own; a done step is ok with neither.
// No value the Setup group draws holds a keyed cause (area=cause): the
// summary says its state and hint, and each step words its own cause.
const READINESS = [
    ["ready", { kind: "answered", causes: [] }, "ok", [], []],
    ["nothing set up", { kind: "answered", causes: ["speech=local-not-set-up", "brain=unselected"] }, "warning", ["setupVoice", "setupModel"], ["setupVoice"]],
    ["local voice only", { kind: "answered", causes: ["speech=local-not-ready"] }, "warning", ["setupVoice"], []],
    ["local voice ready timeout", { kind: "answered", causes: ["speech=local-ready-timeout"] }, "warning", ["setupVoice"], []],
    ["probe timeout", { kind: "answered", causes: ["setup=probe-timeout"] }, "ok", [], []],
    ["probe timeout beside an AI model cause", { kind: "answered", causes: ["setup=probe-timeout", "brain=unselected"] }, "warning", ["setupModel"], []],
    ["the AI model only", { kind: "answered", causes: ["brain=account-unavailable"] }, "warning", ["setupModel"], []],
    // ChainedEngine's cause while no speech row exists has no hint of its own.
    ["a cause with no hint of its own", { kind: "answered", causes: ["speech=no-adapter"] }, "warning", ["setupVoice"], ["setupVoice"]],
    // A brain cause with no hint of its own takes the step's.
    ["a brain cause with no hint of its own", { kind: "answered", causes: ["brain=unnamed"] }, "warning", ["setupModel"], []],
    ["a signed-out AI model", { kind: "answered", causes: ["brain=signed-out"] }, "warning", ["setupModel"], [], "signIn"],
    ["a Pi older than the Pi brain's floor", { kind: "answered", causes: ["brain=pi-update"] }, "warning", ["setupModel"], [], null]
];
// Each step's action once done: the voice step's boolean; the AI model's
// manifest entry declares named actions, so its value carries none.
const DONE_ACTION = { setupVoice: false, setupModel: undefined };
// The home folder's causes: Home.js's and Guidance.js's. One without a hint
// of its own takes the step's.
const HOME_CAUSES = ["home=link", "home=path", "home=unwritable", "guidance=home-too-large", "guidance=home-skills-too-large", "guidance=home-memory-too-large"];
// Each brain cause asks for its own action.
const BRAIN_CAUSES = ["brain=unselected", "brain=account-unavailable", "brain=model-required", "brain=accounts-unreadable", "brain=signed-out",
    "brain=pi-update"];
// The TUI each of the AI model's named actions opens, from the manifest.
const MODEL_TUI = { key: "add-key", signIn: "sign-in" };
const plain = value => JSON.parse(JSON.stringify(value));
// The voice the daemon hears of: [label, the settings a user changed over the
// manifest's own, the stored cloud voice keys the account reader holds or
// undefined while it has no answer, the voice]. A fresh settings file holds
// only the manifest's values, and a saved choice keeps its value.
const KEY = [{ value: "openai-1", label: "OpenAI / fixture", provider: "openai" }];
const GEMINI_KEY = [{ value: "gemini-1", label: "Gemini / fixture", provider: "gemini" }];
const ELEVEN_KEY = [{ value: "eleven-1", label: "ElevenLabs / fixture", provider: "elevenlabs" }];
const VOICE = [
    ["a fresh settings file with no key", {}, [], "local"],
    ["a fresh settings file beside a stored named key", { voiceAccount: "openai-1" }, KEY, "local"],
    ["Auto saved beside a stored named key", { voiceProvider: "auto", voiceAccount: "openai-1" }, KEY, "realtime"],
    ["Auto saved beside a stored key the Realtime key setting does not name", { voiceProvider: "auto" }, KEY, "local"],
    ["Auto saved with the named key removed", { voiceProvider: "auto", voiceAccount: "openai-1" }, [], "local"],
    ["Auto saved with the named key before the reader answers: its provider is unknown", { voiceProvider: "auto", voiceAccount: "openai-1" }, undefined, "local"],
    ["Auto saved with a named Gemini key before the reader answers", { voiceProvider: "auto", voiceAccount: "gemini-1" }, undefined, "local"],
    ["Auto saved with no key before the reader answers", { voiceProvider: "auto" }, undefined, "local"],
    ["Local chosen beside a stored key", { voiceProvider: "local", voiceAccount: "openai-1" }, KEY, "local"],
    ["Realtime saved with no key", { voiceProvider: "realtime" }, [], "realtime"],
    ["Realtime saved beside a stored named key", { voiceProvider: "realtime", voiceAccount: "openai-1" }, KEY, "realtime"],
    ["Always talk mode with Auto saved beside a stored key", { mode: "always", voiceProvider: "auto", voiceAccount: "openai-1" }, KEY, "local"],
    ["Always talk mode with Realtime chosen", { mode: "always", voiceProvider: "realtime", voiceAccount: "openai-1" }, KEY, "realtime"],
    ["Gemini saved with no key", { voiceProvider: "gemini" }, [], "gemini"],
    ["Gemini saved beside a stored named key", { voiceProvider: "gemini", voiceAccount: "gemini-1" }, GEMINI_KEY, "gemini"],
    ["Auto saved beside a named Gemini key: Auto means Realtime", { voiceProvider: "auto", voiceAccount: "gemini-1" }, GEMINI_KEY, "local"],
    ["ElevenLabs saved with no key", { voiceProvider: "elevenlabs" }, [], "elevenlabs"],
    ["ElevenLabs saved beside a stored named key", { voiceProvider: "elevenlabs", voiceAccount: "eleven-1" }, ELEVEN_KEY, "elevenlabs"],
    ["Always talk mode with ElevenLabs chosen", { mode: "always", voiceProvider: "elevenlabs", voiceAccount: "eleven-1" }, ELEVEN_KEY, "elevenlabs"],
    ["Auto never runs ElevenLabs", { voiceProvider: "auto", voiceAccount: "eleven-1" }, [...KEY, ...ELEVEN_KEY], "local"]
];
// The Voice group's key row: [label, the stored cloud voice keys or null
// for a failed read, the Voice provider, the key row's tone and whether it
// offers Add key].
const VOICE_KEY = [["no key", [], "realtime", ["info", true]], ["a stored key", KEY, "realtime", ["ok", false]],
    ["keys unread", null, "realtime", ["warning", true]], ["a stored key of the other voice", KEY, "gemini", ["info", true]],
    ["a stored Gemini key", [...KEY, ...GEMINI_KEY], "gemini", ["ok", false]], ["Gemini keys unread", null, "gemini", ["warning", true]],
    ["Local beside a stored key", KEY, "local", ["ok", false]], ["Local with no key", [], "local", ["info", true]],
    ["Auto with no key", [], "auto", ["info", true]],
    ["a stored ElevenLabs key", [...KEY, ...ELEVEN_KEY], "elevenlabs", ["ok", false]], ["no ElevenLabs key", KEY, "elevenlabs", ["info", true]]];
// The keyed start causes the service can publish before the first ready state.
// The widget and the Setup page both read these words from SetupGate.
const START_CAUSES = [
    ["hello timeout", "jarvis: hello=timeout", "hello-timeout"],
    ["Node too old", "jarvis: node=20.19.5 need=22", "node-too-old"],
    ["Node exit", "jarvis: daemon=exit code=78 status=0", "node-too-old"],
    ["daemon exit", "jarvis: daemon=exit code=1 status=0", "daemon-exit"],
    ["daemon ended", "jarvis: daemon=ended", "daemon-exit"],
    ["wire defect", "jarvis: protocol=identity", "wire-defect"]
];
const ARBITRARY_STDERR = "SyntaxError: fixture";
// The widest start cause title the VGS-1228 sheets show whole in the Setup
// status chip at the Settings window's default width: "Jarvis did not
// answer in time" (tmp/landed-sheets/VGS-1228/r2/jarvis-setup-dark-1.png in
// the base checkout, After 55f0ab7e). The chip draws capitals in a fixed
// width font, so a title's characters measure its width.
const CHIP_TITLE_MAX = "Jarvis did not answer in time".length;
// The Local voice setting: [label, the setting, the pick, the ready tier or
// null, the run a change to the setting starts (null for none), the setting
// after a run ended with that ready tier (null to keep it)].
const TIERS = [
    ["auto on a fresh computer installs the pick", "auto", "large", null, [], null],
    ["a chosen tier on a fresh computer installs it", "medium", "large", null, ["medium"], null],
    ["auto while the pick is ready starts nothing", "auto", "large", "large", null, null],
    ["a chosen tier that is ready starts nothing", "medium", "large", "medium", null, null],
    ["auto beside another ready tier installs the pick", "auto", "large", "small", [], "small"],
    ["a chosen tier beside the ready pick installs it", "medium", "large", "large", ["medium"], "auto"],
    ["choosing the pick by name beside another tier installs it", "large", "large", "small", ["large"], "small"],
    ["a chosen tier beside a third ready tier", "medium", "large", "small", ["medium"], "small"],
    ["the pick by name while it is ready starts nothing", "large", "large", "large", null, null]
];

// The model and effort the Jarvis page offers and saves. Each list is the
// page's read for one sign-in, as its program's adapter narrows it: the
// program's own default first. Copilot's adapter names no effort level.
const LEVELS = ["low", "medium", "high", "xhigh", "max"];
const offer = (value, label, efforts = LEVELS, effort = "") => ({ value, label, efforts, effort });
const FABLE = offer("claude-fable-5-1", "Fable 5.1"), OPUS = offer("claude-opus-5-5[1m]", "Opus 5.5");
const HAIKU = offer("claude-haiku-4-5", "Haiku 4.5", []), SONNET = offer("claude-sonnet-5-5", "Sonnet 5.5", ["low", "high", "xhigh"]);
const CLAUDE = [OPUS, FABLE, HAIKU, SONNET];
const COPILOT = [offer("auto", "Auto", []), offer("claude-opus-5.5", "Claude Opus 5.5", []), offer("gpt-6.1-sol", "GPT-6.1-Sol", [])];
const CODEX = [offer("gpt-6.1-sol", "GPT-6.1-Sol", [...LEVELS, "ultra"], "low"), offer("gpt-6-luna", "GPT-6-Luna", LEVELS, "medium")];
// An Anthropic key's list, its row's own, each at the API's own default.
const ANTHROPIC_KEY = [offer("claude-opus-5-5", "Claude Opus 5.5", LEVELS, "medium"), offer("claude-sonnet-5-5", "Claude Sonnet 5.5", LEVELS, "high"),
    offer("claude-haiku-4-5", "Claude Haiku 4.5", [], "")];
const read = offers => ({ kind: "read", offers });
const CLAUDE_VALUES = ["claude-fable-5-1", "claude-opus-5-5[1m]", "claude-haiku-4-5", "claude-sonnet-5-5"];
const FAILED = { kind: "failed", reason: "harness-exit" };
// [label, the saved model and effort, the page's read, the model and effort
// the page saves, the page's model and effort choices by value, the
// sign-in's provider where the row needs one].
const CHOICE = [
    ["Claude Code and nothing saved", {}, read(CLAUDE), ["claude-fable-5-1", "high"], CLAUDE_VALUES, ["high", "low", "medium", "xhigh", "max"]],
    ["Copilot, which offers Opus 5.5, no Fable and no effort level", { effort: "high" }, read(COPILOT), ["claude-opus-5.5", ""], ["claude-opus-5.5", "auto", "gpt-6.1-sol"], []],
    ["Claude Code without Fable", {}, read([OPUS, HAIKU, SONNET]), ["claude-opus-5-5[1m]", "high"], CLAUDE_VALUES.slice(1), ["high", "low", "medium", "xhigh", "max"]],
    ["a sign-in that offers neither, whose program names its effort", {}, read(CODEX), ["gpt-6.1-sol", "low"], ["gpt-6.1-sol", "gpt-6-luna"], ["low", "medium", "high", "xhigh", "max", "ultra"]],
    ["a preferred model that takes no high effort", {}, read([offer("claude-fable-5-1", "Fable 5.1", ["low", "medium"])]), ["claude-fable-5-1", ""], ["claude-fable-5-1"], ["default", "low", "medium"]],
    ["a saved model and effort", { model: "claude-sonnet-5-5", effort: "low" }, read(CLAUDE), ["claude-sonnet-5-5", "low"], CLAUDE_VALUES, ["default", "low", "high", "xhigh"]],
    ["a saved model whose program names no effort", { model: "claude-sonnet-5-5" }, read(CLAUDE), ["claude-sonnet-5-5", ""], CLAUDE_VALUES, ["default", "low", "high", "xhigh"]],
    ["the second preferred model saved beside the first", { model: "claude-opus-5-5[1m]" }, read(CLAUDE), ["claude-opus-5-5[1m]", "high"], CLAUDE_VALUES, ["high", "low", "medium", "xhigh", "max"]],
    ["a saved model the list does not name", { model: "gpt-6.1-sol", effort: "max" }, read(CLAUDE), ["gpt-6.1-sol", "max"], CLAUDE_VALUES, ["max"]],
    ["a saved effort the model does not offer", { model: "claude-fable-5-1", effort: "ultra" }, read(CLAUDE), ["claude-fable-5-1", "high"], CLAUDE_VALUES, ["high", "low", "medium", "xhigh", "max"]],
    ["a saved model that takes no effort", { model: "claude-haiku-4-5", effort: "high" }, read(CLAUDE), ["claude-haiku-4-5", ""], CLAUDE_VALUES, []],
    ["a sign-in whose list is empty", { model: "claude-fable-5-1", effort: "high" }, read([]), ["claude-fable-5-1", "high"], [], []],
    ["no read, as while the page is closed", { model: "claude-fable-5-1", effort: "xhigh" }, { kind: "none" }, ["claude-fable-5-1", "xhigh"], ["claude-fable-5-1"], ["xhigh"]],
    ["a read that has not answered and nothing saved", {}, { kind: "reading" }, ["", ""], [], [], "claude"],
    ["a read its program did not answer", { model: "claude-fable-5-1", effort: "high" }, FAILED, ["claude-fable-5-1", "high"], ["claude-fable-5-1"], ["high"]],
    // Nothing saved and no list: the page shows what Jarvis runs, and saves nothing.
    ["a failed read and nothing saved, for Claude Code", {}, FAILED, ["", ""], ["claude-fable-5-1"], ["high"], "claude"],
    ["a failed read and nothing saved, for a program that runs its own model", {}, FAILED, ["", ""], ["default"], [], "codex"],
    ["an Anthropic key and nothing saved", {}, read(ANTHROPIC_KEY), ["claude-opus-5-5", "high"],
        ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-4-5"], ["high", "low", "medium", "xhigh", "max"], "anthropic"],
    ["an Anthropic key and its model saved at the API's default", { model: "claude-sonnet-5-5", effort: "high" }, read(ANTHROPIC_KEY),
        ["claude-sonnet-5-5", "high"], ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-4-5"], ["high", "low", "medium", "xhigh", "max"], "anthropic"],
    ["no read and nothing saved, for an Anthropic key", {}, FAILED, ["", ""], ["claude-opus-5-5"], ["high"], "anthropic"]
];
// What the daemon gets with no list read. [label, the saved model and
// effort, the chosen sign-in's provider as the last account read names it,
// undefined before one, the model and effort in the hello].
const UNLISTED = [
    ["Claude Code and nothing saved", {}, "claude", ["claude-fable-5-1", "high"]],
    ["Claude Code and an effort saved alone", { effort: "max" }, "claude", ["claude-fable-5-1", "max"]],
    ["Claude Code and a saved model", { model: "claude-haiku-4-5" }, "claude", ["claude-haiku-4-5", ""]],
    ["Codex and nothing saved", {}, "codex", ["", ""]],
    ["Copilot and a saved model", { model: "auto" }, "copilot", ["auto", ""]],
    ["an Anthropic key and nothing saved", {}, "anthropic", ["claude-opus-5-5", "high"]],
    ["an Anthropic key and an effort saved alone", { effort: "max" }, "anthropic", ["claude-opus-5-5", "max"]],
    ["an Anthropic key and a saved model", { model: "claude-haiku-4-5" }, "anthropic", ["claude-haiku-4-5", ""]],
    ["an OpenAI key and nothing saved", {}, "openai", ["", ""]],
    ["no account read yet", {}, undefined, ["", ""]]
];

// The shipped choice rule against the manifest and the page's select model.
function verifyModelChoice(providers) {
    const manifest = judge.validateManifest(JSON.parse(fs.readFileSync(path.join(path.dirname(file), "manifest.json"), "utf8")), path.dirname(file)).manifest;
    try {
        for (const [label, saved, listed, want, models, efforts, provider] of CHOICE) {
            const settings = { ...plain(manifest.settings), brain: "claude-team", ...saved };
            const choice = providers.modelChoice(settings, listed, provider);
            assert.deepEqual([choice.model, choice.effort], want, label + ": the model and effort the page saves");
            assert.deepEqual([choice.models.map(row => row.value), choice.efforts.map(row => row.value)], [models, efforts], label + ": the page's choices");
            const values = {};
            for (const [key, value] of [["models", choice.models], ["efforts", choice.efforts]]) {
                assert.equal(judge.statusWrite(manifest, values, key, value).ok, true, label + ": accepted status " + key);
                values[key] = value;
            }
            // A field with nothing offered is not drawn, whatever is saved.
            const page = plain(judge.settingChoices(manifest, values, settings));
            assert.deepEqual([page.model.length === 0, page.effort.length === 0], [models.length === 0, efforts.length === 0], label + ": the fields the page draws");
            // A drawn Model field preserves every offer's real ID. The
            // placeholder carries an unset choice until the reader saves it.
            if (models.length > 0 && settings.model !== "") assert.equal(page.model.some(row => row.value === settings.model), true,
                label + ": the Model field shows what is saved");
        }
        const activationSource = fs.readFileSync(path.join(__dirname, "../shell/plugins/vgs.settings/SettingField.qml"), "utf8");
        const activated = [...activationSource.matchAll(/onActivated: index => \{\n                const row = rows\[index\];([\s\S]*?)\n            \}/g)];
        assert.equal(activated.length, 1);
        for (const [provider, ids] of [
            ["ollama", ["fixture-model"]], ["lm-studio", ["fixture-model", "fixture-other"]],
            ["llama-server", ["fixture-model"]], ["codex", ["default", "fixture-model"]]
        ]) {
            const local = provider !== "codex";
            const listed = read(ids.map(id => offer(id, id, [])));
            const choice = providers.modelChoice({ model: "", effort: "" }, listed, provider);
            assert.equal(choice.model, local ? "" : "default", provider + ": local choice is explicit and program default stays selected");
            const saved = { ...manifest.settings, model: choice.model };
            const page = plain(judge.settingChoices(manifest, { models: choice.models }, saved)).model;
            assert.deepEqual(page.map(row => row.value), ids, provider + ": every offered ID reaches Settings");
            for (const [index, id] of ids.entries()) {
                const writes = [];
                const root = { value: saved.model, customChosen: false, apply: value => writes.push(value) };
                vm.runInNewContext("(index => {\n                const row = rows[index];" + activated[0][1]
                    + "\n})(" + index + ");", { root, rows: page, dynamic: true, shownIndex: -1, currentIndex: -1,
                    Qt: { binding: value => value } });
                assert.deepEqual(writes, id === saved.model ? [] : [id], provider + ": activation writes the offered ID");
            }
        }
        // Labels a user reads: a level by its word, the program's own by
        // name, a model with no list by its saved name, marked when its
        // list could not be read.
        const shown = providers.modelChoice({ model: "claude-sonnet-5-5", effort: "" }, read(CLAUDE)).efforts;
        assert.deepEqual(plain(shown), [{ label: "Model default", value: "default" }, { label: "Low", value: "low" }, { label: "High", value: "high" }, { label: "Extra high", value: "xhigh" }]);
        assert.deepEqual(plain(providers.modelChoice({ model: "claude-fable-5-1", effort: "xhigh" }, { kind: "none" }).models.concat(
            providers.modelChoice({ model: "claude-fable-5-1", effort: "xhigh" }, { kind: "failed" }).models,
            providers.modelChoice({ model: "claude-fable-5-1", effort: "xhigh" }, { kind: "none" }).efforts)),
            [{ label: "claude-fable-5-1", value: "claude-fable-5-1" }, { label: "claude-fable-5-1 (list not read)", value: "claude-fable-5-1" }, { label: "Extra high", value: "xhigh" }]);
    } catch (error) {
        if (error instanceof assert.AssertionError) error.check = "model-choice";
        throw error;
    }
}

// The shipped account reader's model list read, run as the page drives it:
// its bindings, its functions and its process's end, over a stand-in
// process. VIEWED is whether the Settings window shows the Jarvis page.
// A call the reader queues with Qt.callLater runs at settle(), once per
// function, as the engine runs it back in the event loop. The engine's own
// order of a binding's update and its handlers is
// scripts/qml-tests/tst_jarvis_accounts.qml's to hold.
function listReader(accountsSource, providers, saved, viewed) {
    const binding = name => accountsSource.match(new RegExp("^    readonly property \\w+ " + name + ": (.*)$", "m"));
    const fn = name => accountsSource.match(new RegExp("^    function " + name + "\\([^)]*\\) \\{\\n[\\s\\S]*?^    \\}", "m"));
    const changed = accountsSource.match(/^    onBrainChanged: (.*)$/m);
    const ended = accountsSource.match(/^        id: lister\n[\s\S]*?^        onRunningChanged: \{\n([\s\S]*?)^        \}/m);
    const settings = { brain: "claude-team", model: "", effort: "", ...saved };
    const writes = [], warnings = [], values = {}, queued = [];
    const root = { program: "/fixture/accounts.js", listed: { brain: "", kind: "none" }, seenBrain: null, providers: {},
        lister: { running: false, dropped: false, output: "", command: [] },
        shell: { settings, status: { viewed, set: (key, value) => { values[key] = value; return "ok"; } },
            configure: { set: (key, value) => { writes.push([key, value]); settings[key] = value; return "ok"; } } } };
    const globals = { root, Providers: providers, Quickshell: { shellDir: "/fixture/shell" }, console: { warn: text => warnings.push(text) },
        Qt: { callLater: call => { if (!queued.includes(call)) queued.push(call); } } };
    const run = text => vm.runInNewContext("(function() { with(root) { return (" + text + "); } })()", globals);
    for (const name of ["brain", "wanted", "list", "choice"]) {
        assert.ok(binding(name), "the reader binds " + name);
        Object.defineProperty(root, name, { get: () => run(binding(name)[1]) });
    }
    for (const name of ["save", "publishChoice", "readList", "listRead"]) {
        assert.ok(fn(name), "the reader holds " + name);
        root[name] = run(fn(name)[0]);
    }
    assert.ok(changed && ended);
    return { root, settings, writes, warnings, values,
        brainChanged: () => { run(changed[1]); },
        settle() { while (queued.length > 0) queued.shift()(); },
        // The choice's change handler, then the turn's queued calls.
        publish() { root.publishChoice(); this.settle(); },
        // The process ends: with OUTPUT on its stdout, or ended by readList.
        end(output) {
            root.lister.running = false;
            if (output !== undefined) root.lister.output = output;
            vm.runInNewContext("(function() { with(root.lister) { " + ended[1] + " } })()", globals);
        } };
}

function verifyListRead(providers, accountsSource) {
    try {
        // The shell starts with a saved choice and the page closed: no read
        // starts, the saved choice is published and nothing is written.
        const closed = listReader(accountsSource, providers, { model: "claude-fable-5-1", effort: "high" }, false);
        assert.equal(closed.root.wanted, "", "no list is wanted while the page is closed");
        closed.root.readList();
        closed.publish();
        assert.deepEqual(plain([closed.root.lister.running, closed.root.lister.command, closed.root.listed.kind, closed.values.models, closed.writes]),
            [false, [], "none", [{ label: "claude-fable-5-1", value: "claude-fable-5-1" }], []], "no read with the page closed");
        // A sign-in changed with the page closed keeps what is saved.
        closed.brainChanged();
        closed.settle();
        closed.settings.brain = "codex-team";
        closed.brainChanged();
        closed.settle();
        assert.deepEqual(closed.writes, [], "only a sign-in changed on the page drops the saved choice");
        // The page opens: one read for the chosen sign-in, and its list's
        // default is saved.
        const open = listReader(accountsSource, providers, {}, true);
        assert.equal(open.root.wanted, "claude-team");
        // A reader built while the page is open, as after a rescan, sees
        // the saved sign-in for the first time: no change, nothing dropped.
        const rebuilt = listReader(accountsSource, providers, { model: "claude-haiku-4-5" }, true);
        rebuilt.brainChanged();
        rebuilt.settle();
        assert.deepEqual(rebuilt.writes, [], "the first sight of the saved sign-in drops nothing");
        open.brainChanged();
        open.settle();
        open.root.readList();
        assert.deepEqual(plain([open.root.lister.running, open.root.lister.command.slice(-2), open.root.listed]),
            [true, ["models", "claude-team"], { brain: "claude-team", kind: "reading" }], "one read for the chosen sign-in");
        open.end(JSON.stringify(read(CLAUDE)));
        open.root.publishChoice();
        assert.deepEqual(open.writes, [], "a save waits for the turn's end");
        open.settle();
        assert.deepEqual(plain([open.values.models.map(row => row.value), open.values.efforts.map(row => row.value), open.writes]),
            [CLAUDE_VALUES, ["high", "low", "medium", "xhigh", "max"], [["model", "claude-fable-5-1"], ["effort", "high"]]],
            "a read list offers its models and efforts and saves its default");
        open.publish();
        assert.equal(open.writes.length, 2, "a saved choice is not written again");
        // The sign-in changes on the page while its read runs: the saved
        // choice is dropped, the running read runs to its end and its
        // answer is not taken, and the new sign-in's read starts at that end.
        open.settings.brain = "codex-team";
        open.brainChanged();
        open.publish();
        assert.deepEqual(open.writes.slice(2), [["model", ""], ["effort", ""]], "a sign-in changed on the page drops the saved model and effort");
        open.root.readList();
        assert.equal(open.root.lister.running, true);
        open.settings.brain = "copilot-team";
        open.root.readList();
        assert.deepEqual(plain([open.root.lister.running, open.root.lister.command.slice(-2)]), [true, ["models", "codex-team"]],
            "a changed sign-in leaves the running read to its end");
        open.end(JSON.stringify(read(CLAUDE)));
        assert.deepEqual(plain([open.root.listed, open.root.lister.running, open.root.lister.command.slice(-2)]),
            [{ brain: "copilot-team", kind: "reading" }, true, ["models", "copilot-team"]], "the ended read's answer is dropped and the next read starts");
        // A list read for an earlier sign-in changes nothing.
        open.end(JSON.stringify(read(COPILOT)));
        open.settings.brain = "claude-team";
        open.publish();
        assert.deepEqual(plain([open.root.list, open.values.models, open.writes.slice(4)]), [{ kind: "none" }, [], []], "a list for another sign-in offers and saves nothing");
        // A read its program does not answer: the saved choice with its
        // note, the cause in the log, nothing written.
        const failed = listReader(accountsSource, providers, { model: "claude-fable-5-1", effort: "high" }, true);
        failed.root.readList();
        failed.end(JSON.stringify(FAILED));
        failed.publish();
        assert.deepEqual(plain([failed.values.models, failed.warnings, failed.writes]),
            [[{ label: "claude-fable-5-1 (list not read)", value: "claude-fable-5-1" }], ["jarvis-accounts: models=harness-exit"], []], "a failed read");
        // With nothing saved the page shows what Jarvis runs for the
        // sign-in's provider, and saves nothing without a read list.
        const unsaved = listReader(accountsSource, providers, {}, true);
        unsaved.root.providers = { "claude-team": "claude" };
        unsaved.root.readList();
        unsaved.end(JSON.stringify(FAILED));
        unsaved.publish();
        assert.deepEqual(plain([unsaved.values.models.map(row => row.value), unsaved.writes]), [["claude-fable-5-1"], []], "a failed read with nothing saved");
        // A helper that prints no answer is a failed read, whatever an
        // earlier read printed.
        failed.root.readList();
        failed.end();
        assert.deepEqual(plain([failed.root.listed, failed.warnings.slice(1)]), [{ brain: "claude-team", kind: "failed", reason: "helper" }, ["jarvis-accounts: models=helper"]],
            "a helper that prints no answer");
        // The page closes: the running read runs to its end, its answer is
        // not taken and none starts.
        failed.root.readList();
        failed.root.shell.status.viewed = false;
        failed.root.readList();
        assert.equal(failed.root.lister.running, true, "a closed page leaves the running read to its end");
        failed.end(JSON.stringify(read(CLAUDE)));
        assert.deepEqual(plain([failed.root.listed, failed.root.lister.running]), [{ brain: "", kind: "none" }, false], "a closed page takes no answer and starts no read");
    } catch (error) {
        if (error instanceof assert.AssertionError) error.check = "model-choice";
        throw error;
    }
}

// The shipped Setup row projection reads the published status; the nested
// smoke and pictures check the rendered page.
const serviceFile = path.join(path.dirname(file), "Service.qml");
const accountsFile = path.join(path.dirname(file), "Accounts.qml");
const localRuntimeFile = path.join(path.dirname(file), "LocalRuntime.qml");
const providersFile = path.join(path.dirname(file), "AccountProviders.js");
const words = require(path.join(path.dirname(file), "AccountStatus.js"));
// Remove key draws on the API keys row beside Add key, in the danger tone
// that leads with the trash mark, while a key is stored, and never on a
// More settings row: [where it draws on the page, its tone] for MANIFEST, a
// judged manifest, and the keyStore value of WORDS.keysValue's OUTCOME.
function removeKeyPlacement(judged, outcome) {
    const status = judge.statusRows(judged, { keyStore: plain(words.keysValue(outcome)) });
    const tuis = judge.listedTuis(judged);
    const rows = detailActionRows(status).filter(row => row.aside !== null)
        .map(row => ["row " + row.key + " beside " + row.button.label, row.aside.label, row.aside.tone]);
    const more = Array.from(settings.freeScreens(tuis, status, "Settings", jarvisOn)).filter(button => button.name === "remove-key")
        .map(button => ["More settings", button.label, button.tone]);
    return rows.concat(more);
}
{
    const key = { label: "OpenAI / fixture", value: "present" };
    for (const [label, outcome, want] of [
        ["two keys stored", { kind: "listed", rows: [key, Object.assign({}, key, { label: "Gemini / fixture" })] }, [["row keyStore beside Add key", "Remove key", "danger"]]],
        ["one key stored", { kind: "listed", rows: [key] }, [["row keyStore beside Add key", "Remove key", "danger"]]],
        ["no key stored", { kind: "listed", rows: [] }, []],
        ["the keyring unread", { kind: "failed" }, []]])
        assert.deepEqual(removeKeyPlacement(manifest, outcome), want, label + ": Remove key draws on the API keys row alone");
    // Its control: the remove-key screen marked as a More settings screen and
    // the API keys row with no aside, which draws it on More settings.
    const raw = JSON.parse(fs.readFileSync(path.join(path.dirname(file), "manifest.json"), "utf8"));
    raw.tui["remove-key"].entry.settings = true;
    delete raw.status.keyStore.aside;
    const unaside = judge.validateManifest(raw, path.dirname(file));
    assert.equal(unaside.ok, true, "the control's manifest is judged");
    assert.deepEqual(removeKeyPlacement(unaside.manifest, { kind: "listed", rows: [key] }), [["More settings", "Remove key", ""]],
        "control: with no aside Remove key draws on More settings and not on the API keys row");
}
const UNSELECTED = { kind: "answered", causes: ["brain=unselected"] };
const SIGNED_OUT = { kind: "answered", causes: ["brain=signed-out"] };

// Config.writeUser produces the two refused replies. Execute the shipped
// shortcut and notice bodies, with only their capability endpoints supplied.
function verifyHomeSwitch(serviceSource) {
    const switchHome = serviceSource.match(/^    function switchHome\(item\) \{\n[\s\S]*?^    \}/m);
    const notice = serviceSource.match(/^    function notice\(options\) \{\n[\s\S]*?^    \}/m);
    assert.ok(switchHome && notice, "the home shortcut and notice helper are present");
    const id = "h0123456789ab", selected = "~/Other home", previous = "~/Current home";
    for (const [name, item, reply] of [
        ["saved", id, "ok"],
        ["unreadable", id, "refused: user-config=unreadable path=/fixture/shell.json"],
        ["read-only", id, "refused: user-config=unwritable path=/fixture/shell.json error=permission-denied"],
        ["unlisted", "h000000000000", "ok"]
    ]) {
        let saved = previous;
        const writes = [], notices = [], warnings = [];
        const shell = {
            configure: { set(key, value) { writes.push([key, value]); if (reply === "ok") saved = value; return reply; } },
            notify: { send(options) { notices.push(JSON.parse(JSON.stringify(options))); return "ok"; } }
        };
        const result = vm.runInNewContext(notice[0] + "\n" + switchHome[0] + "\nswitchHome(" + JSON.stringify(item) + ");",
            { shell, homeMessage: { homes: [{ id, value: selected }] }, console: { warn: text => warnings.push(text) } });
        const listed = item === id, refused = listed && reply !== "ok";
        assert.equal(result, listed ? reply : "refused: home=" + item + " reason=unlisted", name + ": the write result is retained");
        assert.deepEqual(writes, listed ? [["home", selected]] : [], name + ": only a listed home writes");
        assert.equal(saved, listed && !refused ? selected : previous, name + ": refused writes keep the home");
        assert.equal(notices.length, refused ? 1 : 0, name + ": only a refused write sends a notice");
        assert.deepEqual(warnings, refused ? ["jarvis: home-setting " + reply] : [], name + ": the refusal stays in the log");
        if (refused) {
            assert.equal(notices[0].tone, "danger");
            assert.equal(notices[0].icon, "folder");
            assert.ok(notices[0].title.length > 0 && notices[0].message.length > 0);
            assert.doesNotMatch(notices[0].message, /user-config=|permission-denied/, name + ": diagnostics stay out of the notice");
        }
    }
}
// want: the AI model step's tone and the named action it offers, undefined
// for none. An app is an account row of the helper's status: signIn is
// whether Sign in serves its signed-out account.
const MODEL = [
    { name: "key only before model discovery", keys: [{ value: "present" }], apps: [], answer: UNSELECTED, want: ["warning", undefined] },
    { name: "signed-in app before model discovery", keys: [], apps: [{ source: "cli", state: "signed-in" }], answer: UNSELECTED, want: ["warning", undefined] },
    { name: "verified app", keys: [], apps: [{ source: "cli", state: "verified" }], answer: UNSELECTED, want: ["warning", undefined] },
    { name: "app verification pending", keys: [], apps: [{ source: "cli", state: "verifying" }], answer: UNSELECTED, want: ["warning", undefined] },
    { name: "neither key nor app", keys: [], apps: [], answer: UNSELECTED, want: ["warning", "key"] },
    { name: "found app folder Sign in does not serve", keys: [], apps: [{ source: "cli", state: "found" }], answer: UNSELECTED, want: ["warning", "key"] },
    { name: "signed-out app folder", keys: [], apps: [{ source: "cli", state: "found", signIn: true }], answer: UNSELECTED, want: ["warning", "signIn"] },
    { name: "signed-out app beside a signed-in one", keys: [], apps: [{ source: "cli", state: "found", signIn: true }, { source: "cli", state: "signed-in" }],
        answer: UNSELECTED, want: ["warning", undefined] },
    { name: "signed-out app beside a key", keys: [{ value: "present" }], apps: [{ source: "cli", state: "found", signIn: true }], answer: UNSELECTED, want: ["warning", undefined] },
    { name: "signed-out AI model chosen", keys: [{ value: "present" }], apps: [{ source: "cli", state: "signed-in" }], answer: SIGNED_OUT, want: ["warning", "signIn"] },
    { name: "unchecked app folder", keys: [], apps: [{ source: "cli", state: "unchecked" }], answer: UNSELECTED, want: ["warning", "key"] },
    { name: "locked key", keys: [{ value: "locked" }], apps: [], answer: UNSELECTED, want: ["warning", undefined] },
    { name: "unavailable key reader", keys: [{ value: "unavailable" }], apps: [], answer: UNSELECTED, want: ["warning", undefined] },
    { name: "key reader has not answered", keys: undefined, apps: [], answer: UNSELECTED, want: ["warning", undefined] },
    { name: "app reader failed", keys: [], apps: [], code: 1, answer: UNSELECTED, want: ["warning", undefined] },
    { name: "selected model", keys: [{ value: "present" }], apps: [], answer: { kind: "answered", causes: [] }, want: ["ok", undefined] },
    { name: "checking", keys: [], apps: [], answer: { kind: "checking" }, want: ["info", undefined] }
];

// Run both shipped publication functions. Accounts supplies typed sign-in
// facts; Service publishes the model row without relying on offered models.
function verifyModelConsumers(gate, serviceSource, accountsSource) {
    const publishAccounts = [accountsPublication(accountsSource)];
    const publishSetup = serviceSource.match(/^    function publishSetup\(answer\) \{\n[\s\S]*?^    \}/m);
    assert.ok(publishAccounts && publishSetup);
    const manifest = judge.validateManifest(JSON.parse(fs.readFileSync(path.join(path.dirname(file), "manifest.json"), "utf8")), path.dirname(file)).manifest;
    for (const row of MODEL) {
        const values = row.keys === undefined ? {} : { keys: row.keys.map(key => ({ label: "Fixture key", ...key })) };
        if (row.keys !== undefined) assert.equal(judge.statusWrite(manifest, {}, "keys", values.keys).ok, true);
        const shell = { settings: { voiceAccount: "" }, requirements: { missing: [] }, status: { values, set: (key, value) => {
            const accepted = judge.statusWrite(manifest, values, key, value);
            assert.equal(accepted.ok, true, row.name + ": accepted status " + key);
            values[key] = value;
            return "ok";
        } } };
        const root = { shell, modelAccess: { kind: "checking" }, pending: false, removedFrom: undefined,
            completion: { kind: "exited", code: row.code ?? 0 }, diagnostic: { kind: "collected", text: "" },
            output: JSON.stringify({ accounts: row.apps.map(app => ({ label: "Fixture app", value: "present", plan: "", email: "", mismatch: false, signIn: false, ...app })),
                brains: [], voiceAccounts: [], search: { found: row.apps.length, partial: "" } }), refreshed: () => {} };
        vm.runInNewContext(publishAccounts[0],
            { root, Gate: gate, Words: words, Providers: { probeFailure: () => "jarvis-accounts: probe=failed" }, console: { warn: () => {} } });
        vm.runInNewContext("(" + publishSetup[0] + ")", { Gate: gate, shell, dictationState: null, accountReader: root, localRuntime: { setupCause: "", republish: () => {} }, voiceStep: null, sessionState: null, sessionStart: { result: null }, shellSetupCauses: [], setupAnswer: { kind: "checking" } })(row.answer);
        try {
            assert.deepEqual([values.setupModel.tone, values.setupModel.action], row.want, row.name);
            const entry = judge.statusRows(manifest, values).find(item => item.key === "setupModel");
            assert.equal(entry.action.offered, row.want[1] !== undefined, row.name + ": the actual row action");
            const setupRow = settingsRows(settings.setupSections([{ name: "add-key" }, { name: "sign-in" }], judge.statusRows(manifest, values)))
                .find(item => item.entry.key === "setupModel");
            assert.equal(setupRow.button === null ? undefined : setupRow.button.name, MODEL_TUI[row.want[1]], row.name + ": Settings link");
            // A signed-out app replaces the cause's hint with its own.
            if (row.answer === UNSELECTED) {
                const unselected = gate.readiness(UNSELECTED).setupModel.hint;
                const hint = settings.statusView(setupRow.entry, String).hint;
                if (row.want[1] !== "signIn")
                    assert.equal(hint, "Choose an AI model in [Settings > Jarvis > AI model](page:vgs.jarvis/Settings)", row.name + ": Setup AI model hint");
                else assert.deepEqual([typeof hint, hint === unselected], ["string", false],
                    row.name + ": Setup signed-out hint replaces the unselected one");
            }
        } catch (error) {
            error.check = "setup-model-action";
            error.case = row.name;
            throw error;
        }
    }
}
// Run the shipped hello and the shipped account publication: the daemon's
// own protocol judge accepts each hello, whose voice is the row's, and the
// Voice group's key row offers Add key until a key is stored.
// The settings of the hello the shipped service writes for SETTINGS and
// READER, its account reader's last read.
function helloSettings(gate, serviceSource, providers, manifest, settings, reader, label) {
    const hello = serviceSource.match(/^    function hello\(\) \{\n[\s\S]*?^    \}/m);
    assert.ok(hello);
    const keys = Object.fromEntries(manifest.hyprland.binds.map(bind => [bind.shortcut, bind.key]));
    let wire = null;
    const root = { accountReader: reader, shell: { settings,
        shortcut: { keys }, manifest: { hyprland: manifest.hyprland, __revision: "a".repeat(64) } },
        child: { running: true, write: text => { wire = text; } }, cause: "", lifetime: { kind: "starting" }, sessionState: null, dictationCause: "",
        feedbackSounds: false, lockObservation: () => false, broken: reason => assert.fail(label + ": the daemon refuses the hello: " + reason) };
    vm.runInNewContext("(function() { with(root) { return (" + hello[0] + ").call(root); } })()", { root, Gate: gate, Protocol: protocol,
        Quickshell: { env: name => "/fixture/" + name }, Paths: { stateDir: "/fixture/state" }, Providers: { ...providers, runtimeDirectory: () => "/fixture/run" } });
    return JSON.parse(wire).settings;
}

// The account reader's shipped publication as a script over `root`: publish
// and the voice publication it calls.
function accountsPublication(source) {
    const [publish, voice] = ["publish", "publishVoice"].map(name => source.match(new RegExp("^    function " + name + "\\([a-z]*\\) \\{\\n[\\s\\S]*?^    \\}", "m")));
    assert.ok(publish && voice, "the account reader's publication");
    return "(function() { with(root) { root.publishVoice = (" + voice[0] + "); return (" + publish[0] + ").call(root); } })()";
}

function verifySignIn(gate, accountsSource) {
    for (const [label, brain, brains, code, tone, offered] of [
        ["no account selected", "", [], 0, "info", true],
        ["selected app", "app", [{ value: "app", label: "App" }], 0, "ok", false],
        ["selected key", "key", [{ value: "key", label: "Key" }], 0, "ok", false],
        ["selected local server", "local", [{ value: "local", label: "Local" }], 0, "ok", false],
        ["another account available", "missing", [{ value: "app", label: "App" }], 0, "info", true],
        ["account read failed", "app", [{ value: "app", label: "App" }], 1, "info", false]
    ]) {
        const values = {};
        const root = { shell: { settings: { ...plain(manifest.settings), brain }, status: { values, set: (key, value) => {
            assert.equal(judge.statusWrite(manifest, values, key, value).ok, true, label + ": accepted " + key);
            values[key] = value;
            return "ok";
        } } }, pending: false, removedFrom: undefined, completion: { kind: "exited", code },
            diagnostic: { kind: "collected", text: "" }, output: JSON.stringify({ accounts: [], brains, voiceAccounts: [], providers: {}, search: { found: brains.length, partial: "" } }),
            refreshed: () => {} };
        vm.runInNewContext(accountsPublication(accountsSource), { root, Gate: gate, Words: words,
            Providers: { probeFailure: () => "jarvis-accounts: process=failed" }, console: { warn: () => {} } });
        assert.deepEqual([values.setupSignIn.tone, values.setupSignIn.action], [tone, offered], label + ": sign-in follows the selected account");
        const row = judge.statusRows(manifest, values).find(item => item.key === "setupSignIn");
        assert.equal(row.action.offered, offered, label + ": sign-in action");
        assert.equal(settingsRows(settings.setupSections([], judge.statusRows(manifest, values))).some(item => item.key === "setupSignIn"), false,
            label + ": sign-in stays off Setup");
    }
}
// The model and effort the daemon gets with no list read.
function verifyUnlisted(gate, providers, serviceSource) {
    const manifest = judge.validateManifest(JSON.parse(fs.readFileSync(path.join(path.dirname(file), "manifest.json"), "utf8")), path.dirname(file)).manifest;
    try {
        for (const [label, saved, provider, want] of UNLISTED) {
            const settings = { ...plain(manifest.settings), brain: "claude-team", ...saved };
            const sent = helloSettings(gate, serviceSource, providers, manifest, settings,
                { voiceKeys: [], providers: provider === undefined ? {} : { "claude-team": provider } }, label);
            assert.deepEqual([sent.model, sent.effort], want, label + ": the model and effort in the hello");
        }
    } catch (error) {
        if (error instanceof assert.AssertionError) error.check = "model-choice";
        throw error;
    }
}

function verifyVoice(gate, serviceSource, accountsSource) {
    const publishAccounts = [accountsPublication(accountsSource)];
    assert.ok(publishAccounts);
    const manifest = judge.validateManifest(JSON.parse(fs.readFileSync(path.join(path.dirname(file), "manifest.json"), "utf8")), path.dirname(file)).manifest;
    try {
        for (const [label, changed, offered, want] of VOICE) {
            const settings = { ...plain(manifest.settings), ...changed };
            assert.equal(helloSettings(gate, serviceSource, require(providersFile), manifest, settings, { voiceKeys: offered, providers: {} }, label).voiceProvider, want, label);
        }
        assert.equal(plain(gate.readiness({ kind: "answered", causes: [] })).setup.tone, "ok", "no cause, as a fresh install with its local voice set up: ready");
        // The Voice provider takes its four options and nothing else, and a
        // value a settings file already holds reads as it is.
        const provider = value => judge.settingRefusal(manifest, "voiceProvider", value);
        const options = "refused: setting=voiceProvider want=one-of:auto|local|realtime|gemini|elevenlabs";
        assert.deepEqual(["auto", "local", "realtime", "gemini", "elevenlabs", "openai", "Gemini Live", "ElevenLabs"].map(provider),
            ["", "", "", "", "", options, options, options], "the Voice provider takes one of its options");
        for (const saved of ["realtime", "gemini", "elevenlabs"])
            assert.equal(judge.settingsFor({ version: 2, plugins: [{ id: "vgs.jarvis", voiceProvider: saved }] }, manifest).voiceProvider, saved,
                saved + ": a saved Voice provider reads unchanged");
        // The Voice key choices follow the selected cloud voice: a switch
        // from Realtime to Gemini offers the Gemini keys of the same read.
        const every = [...KEY, ...GEMINI_KEY, ...ELEVEN_KEY];
        for (const [voiceProvider, want] of [["realtime", ["openai-1"]], ["gemini", ["gemini-1"]], ["elevenlabs", ["eleven-1"]],
            ["auto", ["openai-1"]], ["local", ["openai-1"]]])
            assert.deepEqual(plain(gate.voiceKeys(every, { voiceProvider })), want.map(value =>
                ({ value, label: every.find(key => key.value === value).label })), voiceProvider + ": the Voice key choices");
        const hints = { realtime: new Set(), gemini: new Set(), local: new Set(), auto: new Set(), elevenlabs: new Set() };
        // The hints of the rows with a key stored, by Voice provider.
        const stored = {};
        // The row's one link, as the Settings page draws it: where the hint holds its words.
        const linked = {};
        for (const [label, offered, voiceProvider, want] of VOICE_KEY) {
            const values = {};
            const shell = { settings: { voiceAccount: "openai-1", voiceProvider }, configure: { set: () => "ok" }, status: { values, set: (key, value) => {
                assert.equal(judge.statusWrite(manifest, values, key, value).ok, true, label + ": accepted status " + key);
                values[key] = value;
                return "ok";
            } } };
            const root = { shell, modelAccess: { kind: "checking" }, voiceKeys: "unread", providers: "unread", pending: false, removedFrom: undefined, completion: { kind: "exited", code: offered === null ? 1 : 0 },
                diagnostic: { kind: "collected", text: "" }, refreshed: () => {},
                output: JSON.stringify({ accounts: [], brains: [], providers: { "claude-team": "claude" }, voiceAccounts: offered ?? [], search: { found: 0, partial: "" } }) };
            vm.runInNewContext(publishAccounts[0],
                { root, Gate: gate, Words: words, Providers: { probeFailure: () => "jarvis-accounts: probe=failed" }, console: { warn: () => {} } });
            assert.deepEqual(plain({ keys: root.voiceKeys }), plain({ keys: offered ?? undefined }), label + ": the keys the reader hands the service");
            assert.deepEqual(plain(root.providers), offered === null ? {} : { "claude-team": "claude" }, label + ": the providers the reader hands the service");
            const entry = judge.statusRows(manifest, values).find(item => item.key === "voiceKey");
            assert.deepEqual(plain([entry.group, entry.tone, entry.action.offered, entry.action.tui]),
                ["Voice", { info: "info", ok: "success", warning: "warning" }[want[0]], want[1], want[1] ? "add-key" : ""], label + ": the Voice group's key row");
            assert.equal(typeof entry.hint === "string" && entry.hint !== "", true, label + ": the row says what the key unlocks");
            assert.equal(oneSentence(entry.hint), true, label + ": the key row's hint is one sentence");
            const link = entry.link !== null && entry.hint.includes(entry.link.text) ? entry.link.url : null;
            if (want[0] === "ok") stored[voiceProvider] = { hint: entry.hint, link };
            else {
                hints[voiceProvider].add(entry.hint);
                linked[voiceProvider] = link;
            }
        }
        assert.deepEqual(Object.values(hints).map(set => set.size), [1, 1, 1, 1, 1], "one hint for each Voice provider");
        const [realtimeHint, geminiHint, localHint, autoHint, elevenHint] = ["realtime", "gemini", "local", "auto", "elevenlabs"].map(name => [...hints[name]][0]);
        assert.deepEqual([realtimeHint === geminiHint, localHint === realtimeHint, localHint === geminiHint, localHint === autoHint,
            [realtimeHint, geminiHint, localHint].includes(elevenHint)],
        [false, false, false, true, false], "the key row says what the selected cloud voice's key unlocks, and under Local or Auto both");
        assert.deepEqual(linked, { realtime: null, gemini: "https://aistudio.google.com/apikey", local: "https://aistudio.google.com/apikey",
            auto: "https://aistudio.google.com/apikey", elevenlabs: null }, "the key row links Google AI Studio where its hint names it");
        // The Voice key field names every cloud voice's key and links
        // OpenAI's key page. It names no row of another tab and no page it
        // cannot link: a hint sends nobody elsewhere for a link.
        const field = manifest.schema.voiceAccount;
        const row = manifest.status.voiceKey;
        const eleven = manifest.status.elevenLabs;
        assert.deepEqual([plain(field.link), ["OpenAI", "Gemini", "ElevenLabs", row.label, row.link.text, eleven.label, eleven.link.text]
            .map(words => field.description.includes(words))],
        [{ text: "OpenAI API keys", url: "https://platform.openai.com/api-keys" }, [true, true, true, false, false, false, false]],
        "the Voice key field names every cloud voice's key, links OpenAI API keys and points at no row of another tab");
        // The key row names the page of each key it asks for. Its one link
        // is Google AI Studio; the two other pages read in words alone.
        const pages = [field.link.text, row.link.text, eleven.link.text];
        assert.deepEqual([realtimeHint, geminiHint, localHint, elevenHint].map(hint => pages.map(page => hint.includes(page))),
            [[true, false, false], [false, true, false], [true, true, false], [false, false, true]],
            "the key row names the page of each key its hint asks for");
        // A hint is one sentence; what it no longer says is the entry's info.
        const worded = [field.description, manifest.schema.voice.description, row.hint, eleven.hint];
        assert.deepEqual(worded.map(oneSentence), [true, true, true, true], "each voice hint is one sentence");
        const keyGuide = pageReference.parse(field.info === undefined ? "" : field.info);
        assert.deepEqual([keyGuide.page, keyGuide.tab, keyGuide.words.includes(manifest.status.keyStore.label)], ["vgs.jarvis", "Details", true],
            "the Voice key help links provider keys beside API keys on Details");
        assert.deepEqual([field, manifest.schema.voice, row, eleven].map(entry => typeof entry.info === "string" && entry.info !== ""),
            [true, true, true, true], "each voice entry keeps its longer help behind the info button");
        // The key row is a fact on Details, beside its own Add key.
        assert.equal(pageReference.parse(row.hint).page, "", "the declared key guide, drawn beside its own Add key, links no page");
        assert.deepEqual([field.link.text, row.link.text].map(page => row.hint.includes(page)), [true, true],
            "the declared key guide keeps the provider key sources");
        // A row with a key stored asks for no key: its hint says what the
        // key gives and where another goes in, the API keys row's Add key,
        // which stays offered, and the Voice key field.
        const kept = [stored.realtime, stored.gemini, stored.local, stored.elevenlabs];
        assert.deepEqual(kept.map(item => [[realtimeHint, geminiHint, localHint, elevenHint].includes(item.hint), item.link,
            pages.some(page => item.hint.includes(page))]), kept.map(() => [false, null, false]), "a stored key's row sends nobody for a key");
        assert.deepEqual([stored.local.hint === stored.realtime.hint, new Set(kept.map(item => item.hint)).size], [true, 3],
            "a stored key's row names the voice its key runs");
        const adds = manifest.status.keyStore;
        // The API keys line sits under AI model on Details, the tab this
        // line is drawn on, and the hint names it and the Voice key field.
        assert.deepEqual(kept.map(item => [[adds.label, adds.action.label, adds.group, field.label].map(words => item.hint.includes(words)), pageReference.parse(item.hint).page]),
            kept.map(() => [[true, true, true, true], ""]),
            "a stored key's row names where another key goes in and where it is chosen");
        assert.deepEqual([adds.action.tui, plain(words.keysValue({ kind: "listed", rows: [{ label: "OpenAI", value: "present" }] })).action],
            ["add-key", true], "the API keys row offers Add key while a key is stored");
        // The preview row of a cloud voice names whose key it uses.
        const preview = serviceSource.match(/^    function publishPreview\(\) \{\n[\s\S]*?^    \}/m);
        assert.ok(preview);
        const previewed = voiceProvider => {
            let value = null;
            const root = { accountReader: { voiceKeys: undefined }, sessionState: { engine: { kind: "duplex" } },
                shell: { settings: { ...plain(manifest.settings), voiceProvider }, status: { set: (key, row) => { value = row; return "ok"; } } } };
            vm.runInNewContext("(function() { with(root) { return (" + preview[0] + ").call(root); } })()",
                { root, Gate: gate, Session: { previewRefusal: () => null } });
            assert.equal(judge.statusWrite(manifest, {}, "voicePreview", value).ok, true, voiceProvider + ": accepted status voicePreview");
            return value;
        };
        assert.notDeepEqual(previewed("gemini"), previewed("realtime"), "a cloud voice's preview names its own key");
        // ElevenLabs speaks over the local voice's engine, yet its preview
        // spends the user's key, so the row names it.
        const local = previewed("local");
        assert.equal(local.text, "Plays on this computer", "the local voice's preview plays on this computer");
        assert.equal(new Set([previewed("elevenlabs"), previewed("gemini"), previewed("realtime"), local].map(value => JSON.stringify(value))).size, 4,
            "the ElevenLabs preview names its own key");
    } catch (error) {
        error.check = "voice-default";
        throw error;
    }
}
function verifyVoiceConsumers(gate) {
    const manifest = judge.validateManifest(JSON.parse(fs.readFileSync(path.join(path.dirname(file), "manifest.json"), "utf8")), path.dirname(file)).manifest;
    for (const [provider, causes, expected] of [
        ["realtime", ["brain=unselected"], ["success", false]],
        ["local", ["brain=unselected", "speech=local-not-set-up"], ["warning", true]]
    ]) {
        const values = { ...plain(gate.readiness({ kind: "answered", causes })),
            localRuntime: { tone: "warning", text: "Not set up", action: true } };
        values.setupVoice = gate.voiceCheck(values.setupVoice, null);
        const row = { status: judge.statusRows(manifest, values) };
        const setupEntry = settingsRows(settings.setupSections([], row.status)).find(item => item.entry.key === "setupVoice").entry;
        try {
            assert.deepEqual(plain([setupEntry.tone, setupEntry.action.offered]), expected);
            assert.equal(settings.detailEntries(row.status).some(entry => entry.key === "setupVoice"), false, "the Voice step draws on Setup alone");
        } catch (error) {
            error.check = "setup-voice-consumer-source";
            error.provider = provider;
            throw error;
        }
    }
}

// The keyed causes (area=cause, or jarvis: area=cause) among VALUE's FIELDS,
// as the Setup group draws them.
function keyedCauses(value, fields) {
    return fields.flatMap(field => value[field] === undefined ? [] : [].concat(value[field]))
        .filter(text => /(^|\s)(jarvis: )?[a-z-]+=[a-z0-9-]/.test(text));
}

function verifyReadiness(gate) {
    for (const [label, answer, tone, todo, declared, model] of READINESS) {
        const got = plain(gate.readiness(answer));
        assert.deepEqual(Object.keys(got).sort(), ["setup", "setupHome", "setupModel", "setupVoice"], label);
        assert.deepEqual(got.setupHome, { tone: "ok", text: "Done" }, label + ": the checked Home folder stays visible as Done");
        assert.equal(got.setup.tone, tone, label + ": the summary");
        assert.equal(got.setup.action, undefined, label + ": the summary offers no step");
        assert.deepEqual(keyedCauses(got.setup, ["text", "hint", "lines"]), [], label + ": the summary draws no keyed cause");
        for (const key of ["setupVoice", "setupModel"]) {
            const step = got[key];
            const open = todo.includes(key);
            const action = key === "setupModel" ? (model === null ? undefined : model ?? "key") : true;
            assert.deepEqual([step.tone, step.action, step.lines], open ? ["warning", action, undefined] : ["ok", DONE_ACTION[key], undefined], label + ": " + key);
            assert.deepEqual(keyedCauses(step, ["text", "hint", "lines"]), [], label + ": " + key + " words its cause");
            if (!open || declared.includes(key)) assert.equal(step.hint, undefined, label + ": " + key + " keeps its declared hint");
            else assert.equal(typeof step.hint === "string" && step.hint !== "" && !/=/.test(step.hint), true,
                label + ": a plain hint, no keyed cause on screen");
        }
    }
    const lines = BRAIN_CAUSES.map(cause => plain(gate.readiness({ kind: "answered", causes: [cause] })).setupModel.hint);
    const localNotReady = plain(gate.readiness({ kind: "answered", causes: ["speech=local-not-ready"] })).setupVoice;
    assert.equal(localNotReady.hint, "Set up the local voice again", "local voice setup-broken words");
    const localReadyTimeout = plain(gate.readiness({ kind: "answered", causes: ["speech=local-ready-timeout"] })).setupVoice;
    assert.deepEqual([localReadyTimeout.text, localReadyTimeout.hint], ["Timed out",
        "Local voice timed out: [turn Jarvis off and on again, or set it up again](page:vgs.jarvis/Setup)"], "local voice timeout words");
    const probeTimeout = plain(gate.readiness({ kind: "answered", causes: ["setup=probe-timeout"] }));
    assert.equal(typeof probeTimeout.setup.hint === "string" && probeTimeout.setup.hint !== "" && !/=/.test(probeTimeout.setup.hint), true,
        "probe timeout: the ready summary carries its caution");
    assert.deepEqual(probeTimeout.setupVoice, { tone: "ok", text: "Done", action: false }, "probe timeout: the voice step offers no setup");
    for (const cause of ["speech=local-memory-insufficient", "speech=local-memory-unavailable"]) {
        const got = plain(gate.readiness({ kind: "answered", causes: [cause] }));
        assert.deepEqual([got.setup.tone, got.setupVoice.tone, got.setupVoice.action, got.setupModel.tone],
            ["warning", "warning", false, "ok"], "memory refuses capture without reinstall action");
        assert.equal(got.setupVoice.lines, undefined, "recovery is no state badge");
        assert.equal(typeof got.setupVoice.hint, "string");
        assert.notEqual(got.setupVoice.hint.trim(), "", "memory refusal carries guidance");
    }
    assert.equal(new Set(lines).size, BRAIN_CAUSES.length, "each brain cause says its own hint");
    for (const cause of ["speech=live-account-unselected", "speech=live-account-unreadable", "speech=live-key-required", "speech=always-local-voice",
        "speech=elevenlabs-voice"]) {
        const got = plain(gate.readiness({ kind: "answered", causes: [cause] }));
        assert.deepEqual([got.setupVoice.tone, got.setupVoice.action, typeof got.setupVoice.hint], ["warning", false, "string"],
            "Realtime voice setup never starts local model installation");
        assert.deepEqual(got.setupModel, { tone: "ok", text: "Done" });
    }
    // Before the daemon answers nothing reads ready or to do.
    const checking = plain(gate.readiness({ kind: "checking" }));
    assert.deepEqual([checking.setup.tone, checking.setup.action], ["info", undefined], "checking: setup");
    for (const key of ["setupVoice", "setupModel"])
        assert.deepEqual([checking[key].tone, checking[key].action], ["info", DONE_ACTION[key]], "checking: " + key);
    assert.equal(gate.readiness({ kind: "checking" }).setupVoice, gate.CHECKING);
    assert.equal(gate.readiness({ kind: "answered", causes: ["speech=local-loading"] }).setupVoice, gate.LOADING);
    assert.equal(gate.readiness({ kind: "answered", causes: ["speech=local-loading"] }).setup, gate.LOADING_SUMMARY);
    // ElevenLabs's voices being read load; a read that failed is to do.
    assert.equal(gate.readiness({ kind: "answered", causes: ["speech=elevenlabs-voices-reading"] }).setupVoice, gate.LOADING,
        "ElevenLabs voices being read: loading");
    assert.notEqual(gate.readiness({ kind: "answered", causes: ["speech=elevenlabs-voice"] }).setupVoice.hint,
        gate.readiness({ kind: "answered", causes: ["speech=elevenlabs-voices-reading"] }).setupVoice.hint, "a failed read says so");
    assert.notEqual(gate.LOADING, gate.CHECKING, "loading and initial checking have distinct values");
    for (const causes of [["speech=local-loading"], ["speech=local-loading", "brain=unselected"]]) {
        const loading = plain(gate.readiness({ kind: "answered", causes }));
        assert.deepEqual([loading.setupVoice.tone, loading.setupVoice.action], ["info", false]);
        assert.equal(loading.setup.tone, causes.length === 1 ? "info" : "warning");
        assert.equal(loading.setup.action, undefined);
        assert.deepEqual([loading.setupModel.tone, loading.setupModel.action], causes.length === 1 ? ["ok", undefined] : ["warning", "key"]);
    }
    // A stopped daemon runs no check: its steps claim none and offer none.
    const stopped = plain(gate.readiness({ kind: "stopped" }));
    assert.deepEqual(Object.keys(stopped).sort(), ["setup", "setupHome", "setupModel", "setupVoice"], "stopped");
    assert.deepEqual([stopped.setupHome, checking.setupHome], [{ tone: "warning", text: "Not checked" }, { tone: "warning", text: "Not checked" }], "Home stays pending before the daemon checks it");
    // A refused home folder is the one step to do, with what to change and
    // no action of its own; the voice and the AI model stay done.
    const homeHints = HOME_CAUSES.map(cause => {
        const got = plain(gate.readiness({ kind: "answered", causes: [cause] }));
        assert.deepEqual([got.setup.tone, got.setupHome.tone, got.setupHome.action, got.setupHome.lines, got.setupVoice.tone, got.setupModel.tone],
            ["warning", "warning", undefined, undefined, "ok", "ok"], cause);
        assert.equal(typeof got.setupHome.hint === "string" && got.setupHome.hint !== "" && !/=/.test(got.setupHome.hint), true,
            cause + ": a plain hint, no keyed cause on screen");
        return got.setupHome.hint;
    });
    assert.equal(new Set(homeHints).size, HOME_CAUSES.length, "each home cause says its own hint");
    // The Copilot Memory row shows for a usable GitHub Copilot account alone.
    const account = (provider, value) => ({ provider, value });
    for (const [label, accounts, shown] of [
        ["no account", [], false], ["another app", [account("claude", "present")], false],
        ["a signed-out Copilot", [account("copilot", "signed-out")], false],
        ["a Copilot account", [account("codex", "present"), account("copilot", "present")], true]]) {
        const got = plain(gate.copilotMemory(accounts));
        assert.deepEqual([got.hidden === true, got.tone], shown ? [false, "info"] : [true, undefined], label);
        assert.equal(got.action, undefined, label + ": the user's step runs on GitHub, with no action here");
    }
    assert.equal(stopped.setup.tone, "danger", "stopped: the summary");
    assert.deepEqual([stopped.setup.lines, typeof stopped.setup.hint], [undefined, "string"], "stopped: the summary says why as its hint");
    for (const key of ["setupVoice", "setupModel"])
        assert.deepEqual([stopped[key].tone === checking[key].tone, stopped[key].action], [false, DONE_ACTION[key]], "stopped: " + key);
    assert.throws(() => gate.readiness({ kind: "answered", causes: ["voice=missing"] }), /^Error: jarvis-setup: cause=voice=missing/);
    const manifest = judge.validateManifest(JSON.parse(fs.readFileSync(path.join(path.dirname(file), "manifest.json"), "utf8")), path.dirname(file)).manifest;
    const piFloor = manifest.requirements.find(row => row.name === "pi").floor;
    const piHint = gate.readiness({ kind: "answered", causes: ["brain=pi-update"] }).setupModel.hint;
    assert.equal(piHint.includes(piFloor), true, "Pi recovery names the required version");
    // An optional step reads its reader's state, in the info tone while it
    // is not ok. The Local voice row is a state of the Voice step while
    // that step offers Set up local voice, else required under a voice that
    // hears the user on this computer and optional under another: [label,
    // entry, the reader's value, the voice the daemon runs or null for an
    // optional step, the Voice step's value, the published [tone, text,
    // action]].
    const voiceTodo = gate.voiceCheck(gate.readiness({ kind: "answered", causes: ["speech=local-not-set-up"] }).setupVoice, null);
    const voiceDone = gate.voiceCheck(gate.DONE, null);
    for (const [label, key, value, provider, voice, want] of [
        ["browser ready", "browser", READY, null, null, ["ok", "Private browser ready", false]],
        ["browser to set up", "browser", ABSENT, null, null, ["info", "Browser needs setup", true]],
        ["browser withheld", "browser", { tone: "warning", text: "Needs agent-browser", action: false }, null, null, ["info", "Needs agent-browser", false]],
        ["input ready", "input", INPUT_READY, null, null, ["ok", "Keys ready; pointer ready", true]],
        ["input missing", "input", INPUT_ABSENT, null, null, ["info", "Input tools unavailable", true]],
        ["local voice to set up under Local, beside a Voice step to do", "localRuntime", LOCAL_ABSENT, "local", voiceTodo, ["info", "Not set up", false]],
        ["local voice to set up under Local, beside a done Voice step", "localRuntime", LOCAL_ABSENT, "local", voiceDone, ["warning", "Not set up", true]],
        ["local voice ready under Local", "localRuntime", LOCAL_READY, "local", voiceTodo, ["ok", "Ready: small", false]],
        ["local voice to set up under Realtime", "localRuntime", LOCAL_ABSENT, "realtime", voiceDone, ["info", "Not set up", true]],
        ["local voice to set up under Gemini Live", "localRuntime", LOCAL_ABSENT, "gemini", voiceDone, ["info", "Not set up", true]],
        ["local voice to set up under ElevenLabs, beside a Voice step to do", "localRuntime", LOCAL_ABSENT, "elevenlabs", voiceTodo, ["info", "Not set up", false]],
        ["local voice to set up under ElevenLabs, which hears through it", "localRuntime", LOCAL_ABSENT, "elevenlabs", voiceDone, ["warning", "Not set up", true]]]) {
        const got = plain(provider === null ? gate.optionalStep(value) : gate.localVoiceStep(value, provider, voice));
        assert.deepEqual([got.tone, got.text, got.action], want, label);
        assert.equal(judge.statusWrite(manifest, {}, key, got).ok, true, label + ": the manifest judge accepts " + key);
    }
    // Beside a Voice step that offers Set up local voice, a Local voice
    // reading that would offer that setup itself takes one line saying where
    // it is; a setup that runs, or a failed check whose hint names the
    // action, takes none: [label, the reading, the row's line count].
    for (const [label, value, lines] of [
        ["not set up", LOCAL_ABSENT, 1],
        ["needs verification", { tone: "warning", text: "Setup needs verification", action: true }, 1],
        ["setting up", { tone: "info", text: "Setting up", action: false }, 0],
        ["check failed", gate.checkFailure("failed", manifest.status.localRuntime), 0],
        ["check timed out", gate.checkFailure("timeout", manifest.status.localRuntime), 0]]) {
        const got = plain(gate.localVoiceStep(value, "local", voiceTodo));
        assert.equal((got.lines ?? []).length, lines, "beside a Voice step to do, " + label + ": its line count");
    }
    // After a failed start the Voice step reads Not checked and offers no
    // action, so the Local voice row names no setup there and offers its own.
    for (const [label, cause] of FAILED_STARTS) {
        const voice = plain(gate.voiceCheck(gate.readiness({ kind: "problem", cause }).setupVoice, null));
        const got = plain(gate.localVoiceStep(LOCAL_ABSENT, "local", voice));
        assert.equal(voice.action, undefined, label + ": the Voice step offers no action");
        assert.deepEqual([got.lines, got.action], [undefined, true], label + ": the Local voice row names no Voice step setup");
    }
    // Every value the service publishes is one the manifest judge accepts
    // for its entry, so a refused write cannot stop the service's start.
    const answers = READINESS.map(row => row[1]).concat([{ kind: "checking" }, { kind: "stopped" },
        { kind: "answered", causes: ["speech=local-memory-insufficient"] },
        { kind: "answered", causes: ["speech=local-memory-unavailable"] }], HOME_CAUSES.map(cause => ({ kind: "answered", causes: [cause] })));
    for (const accounts of [[], [{ provider: "copilot", value: "present" }]])
        assert.equal(judge.statusWrite(manifest, {}, "copilotMemory", plain(gate.copilotMemory(accounts))).ok, true, "the manifest judge accepts copilotMemory");
    // The row's link is words of its declared hint, to GitHub alone.
    const memory = judge.statusRows(manifest, { copilotMemory: plain(gate.copilotMemory([{ provider: "copilot", value: "present" }])) })
        .find(entry => entry.key === "copilotMemory");
    assert.equal(memory.hint.includes(memory.link.text) && new URL(memory.link.url).hostname === "github.com", true);
    assert.equal(settings.statusView(memory, String).link.url, memory.link.url, "Settings draws the row's link");
    assert.equal(judge.statusRows(manifest, { copilotMemory: plain(gate.copilotMemory([])) }).some(entry => entry.key === "copilotMemory"), false,
        "no Copilot account, no row");
    for (const answer of answers)
        for (const [key, value] of Object.entries(plain(gate.readiness(answer))))
            assert.equal(judge.statusWrite(manifest, {}, key, key === "setupVoice" ? gate.voiceCheck(value, null) : value).ok, true,
                "the manifest judge accepts " + key + " for " + JSON.stringify(answer));
    const published = {
        ...plain(gate.readiness({ kind: "answered", causes: ["speech=local-memory-insufficient"] })),
        browser: plain(gate.optionalStep(ABSENT)),
        input: plain(gate.optionalStep(INPUT_ABSENT))
    };
    const fixtureManifest = plain(manifest);
    published.setupVoice = gate.voiceCheck(published.setupVoice, null);
    published.setupVoice.hint = "fixture state voice guidance";
    for (const key of ["setupVoice", "browser", "input"]) {
        fixtureManifest.status[key].hint = "fixture declaration " + key;
        if (key !== "setupVoice") {
            assert.equal(published[key].hint, undefined, "optional guidance stays in the manifest");
            assert.equal(typeof manifest.status[key].hint, "string");
            assert.notEqual(manifest.status[key].hint.trim(), "", "the manifest owns the guidance");
        }
        const hint = key === "setupVoice" ? "fixture state voice guidance" : "fixture declaration " + key;
        const accepted = judge.statusWrite(fixtureManifest, {}, key, published[key]);
        assert.equal(accepted.ok, true);
        const row = judge.statusRows(fixtureManifest, accepted.values).find(entry => entry.key === key);
        const view = settings.statusView(row, String);
        assert.deepEqual(plain([view.hint, view.lines]), [hint, []], "Settings draws one badge with plain guidance: " + key);
    }
}

// The run a change of the Local voice setting starts, and the setting after
// a run ended: the written value is one the setting then holds, so it starts
// no run.
function verifyTiers(gate) {
    for (const [label, wanted, pick, ready, run, after] of TIERS) {
        assert.deepEqual(plain(gate.tierRun(wanted, pick, ready)), run, label + ": the run");
        assert.deepEqual(gate.tierAfterRun(wanted, pick, ready), after, label + ": the setting after a run");
        if (after !== null) assert.equal(gate.tierRun(after, pick, ready), null, label + ": the written setting starts no run");
    }
    const choices = [{ value: "auto", label: "Auto: Large, English, graphics card, 1.2 GB" }, { value: "small", label: "Small: English, quick setup, 685 MB" }];
    assert.equal(judge.statusWrite(manifest, {}, "localTiers", choices).ok, true, "the manifest judge accepts the Local voice offers");
    assert.equal(manifest.schema.localTier.optionsFrom, "localTiers", "the Local voice setting reads its offers");
    assert.equal(manifest.settings.localTier, "auto", "the Local voice setting defaults to the pick");
}

// The Jarvis session row: every state and reason pair of the package's
// contract, copied here from the contract and not from SetupGate.js, is a
// row the manifest
// judge accepts, a session that lives reads the same whatever the boot
// setting, only a session that does not run offers Start, only a failure
// offers Retry, and an answer outside the contract is a failure.
const SESSION_CONTRACT = {
    running: ["resumed", "new-no-record", "new-history-gone", "new-selection-changed", "new-requested", "existing"],
    starting: ["launching"], "handing-over": ["succession"], stopping: ["stop-requested"],
    stopped: ["never-started", "stopped", "ended"], off: ["app-off"],
    blocked: ["app-off", "name-conflict", "record-unreadable", "sign-in-required", "selection-conflict", "tmux-missing", "app-missing"],
    failed: ["launch-failed", "handover-failed"]
};
const SESSION_TONES = { running: "ok", starting: "info", "handing-over": "info", stopping: "info", stopped: "info", off: "info", failed: "danger" };
function verifySession(gate) {
    const names = { home: "~/Jarvis", account: "Claude Code, ~/.claude" };
    const offered = value => {
        assert.equal(judge.statusWrite(manifest, {}, "sessionStart", value).ok, true, "the manifest judge accepts the row: " + JSON.stringify(value));
        const request = plain(judge.statusActionRequest(manifest, "vgs.jarvis", true, { sessionStart: value }, "sessionStart"));
        return request.ok ? value.action + ":" + request.name : "none";
    };
    assert.deepEqual(plain(gate.sessionStart(true, null)), { hidden: true }, "no row before the first answer");
    for (const [state, reasons] of Object.entries(SESSION_CONTRACT))
        for (const reason of reasons)
            for (const wanted of [true, false]) {
                const label = state + " " + reason + " boot " + wanted;
                const value = plain(gate.sessionStart(wanted, { kind: "answer", state, reason, detail: "The package's line.", names }));
                const action = offered(value);
                assert.equal(typeof value.text === "string" && value.text !== "" && typeof value.hint === "string" && value.hint !== "", true, label + ": the row has its words");
                if (state === "blocked") assert.equal(value.tone, reason === "app-off" ? "info" : "warning", label + ": the tone");
                else assert.equal(value.tone, SESSION_TONES[state], label + ": the tone");
                assert.equal(action, state === "stopped" ? "start:start-session" : state === "failed" ? "retry:start-session"
                    : "none", label + ": the action the row offers");
                if (state !== "stopped")
                    assert.deepEqual(value, plain(gate.sessionStart(!wanted, { kind: "answer", state, reason, detail: "The package's line.", names })),
                        label + ": the boot setting changes no row of a session that is not stopped");
                if (["failed"].includes(state) || reason === "sign-in-required")
                    assert.equal(value.hint, "The package's line.", label + ": the package's own line is shown");
                if (["resumed", "existing", "new-requested"].includes(reason))
                    assert.equal(value.hint.includes(names.home) && value.hint.includes(names.account), true, label + ": the recorded home and account are named");
            }
    assert.equal(offered(plain(gate.sessionStart(true, { kind: "answer", state: "running", reason: "existing", detail: "", names: null }))), "none",
        "a running session with no recorded names is a row the judge accepts");
    // The status judge's hint limit: a detail at the limit is drawn, and
    // names too long for one hint leave the row its text alone.
    const limit = plain(gate.sessionStart(true, { kind: "answer", state: "failed", reason: "launch-failed", detail: "x".repeat(200), names }));
    assert.deepEqual([limit.hint.length, offered(limit)], [200, "retry:start-session"], "a detail at the hint limit is a row the judge accepts");
    const long = plain(gate.sessionStart(true, { kind: "answer", state: "running", reason: "resumed", detail: "",
        names: { home: "~/" + "h".repeat(120), account: "Claude Code, ~/" + "a".repeat(120) } }));
    assert.deepEqual([long.text, long.hint, offered(long)], [plain(gate.sessionStart(true, { kind: "answer", state: "running", reason: "resumed", detail: "", names })).text, undefined, "none"],
        "names too long for a hint leave a row the judge accepts");
    assert.deepEqual(Object.keys(SESSION_CONTRACT).filter(state => gate.sessionLive(state)), ["running", "starting", "handing-over"], "the states of a session that lives");
    const stopped = wanted => plain(gate.sessionStart(wanted, { kind: "answer", state: "stopped", reason: "ended", detail: "", names: null }));
    assert.notEqual(stopped(true).text, stopped(false).text, "a stopped session reads by the boot setting");
    // A choice the user has not made yet reads as an optional step and keeps
    // its hint; a missing package is a fault to fix.
    for (const [block, tone] of [["no-account", "info"], ["not-app", "info"], ["no-home", "info"], ["package", "warning"]]) {
        const value = plain(gate.sessionStart(true, { kind: "blocked", block }));
        assert.deepEqual([value.tone, value.hint, offered(value)], [tone, gate.SESSION_BLOCKS[block], "none"], block + ": a block's tone, and it offers no start");
    }
    // The no-home hint says where the choice is, as the Personality row does.
    const homeless = plain(gate.sessionStart(true, { kind: "blocked", block: "no-home" })).hint;
    assert.deepEqual([oneSentence(homeless), homeless.includes("Settings > Jarvis > Home folder")], [true, true],
        "no-home: the hint is one sentence that names its Settings path");
    assert.throws(() => gate.sessionStart(true, { kind: "blocked", block: "unknown" }), { message: "jarvis-setup: session=unknown" });
    for (const result of [{ kind: "failed" }, { kind: "answer", state: "running", reason: "launching", detail: "", names: null }, { kind: "other" }]) {
        const value = plain(gate.sessionStart(true, result));
        assert.deepEqual([value.tone, offered(value)], ["danger", "retry:start-session"], "an answer outside the contract is a failure with Retry");
    }
    const kept = plain(gate.sessionStart(true, { kind: "answer", state: "running", reason: "resumed", detail: "", names, unapplied: "not-app" }));
    assert.deepEqual([kept.text === plain(gate.sessionStart(true, { kind: "answer", state: "running", reason: "resumed", detail: "", names })).text,
        Array.isArray(kept.lines) && kept.lines.length === 1 && offered(kept)], [true, "none"], "a selection that failed its check shows beside the session that stays");
    assert.equal(manifest.settings.startAtBoot, false, "the setting is off at first");
    for (const [wanted, values] of [[false, []], [true, ["", "new"]]]) {
        const offers = plain(gate.sessionModes(wanted));
        assert.equal(judge.statusWrite(manifest, {}, "sessionModes", offers).ok, true, "the manifest judge accepts the session offers");
        const drawn = plain(judge.settingChoices(manifest, { sessionModes: offers }, manifest.settings).bootSession);
        assert.deepEqual(drawn.map(choice => choice.value), values, "the session field while the setting is " + wanted);
    }
}

// Run the shipped service's function NAME over ROOT, with GATE.
function serviceCall(serviceSource, name, root, gate) {
    const found = serviceSource.match(new RegExp("^    function " + name + "\\(\\) \\{\\n[\\s\\S]*?^    \\}", "m"));
    assert.ok(found, name);
    vm.runInNewContext("(function() { with(root) { return (" + found[0] + ").call(root); } })()", { root, Gate: gate });
}

// The ElevenLabs voices row through the shipped service's publication, one
// state per fact: [label, facts, the row's tone and text, or "hidden"].
// With a key chosen the row never asks for one. The row's link draws
// where its hint holds the link's words: while the key is the user's step
// and after a failed read, the two states that send the user to that page.
const ELEVEN_KEY_STORED = [{ value: "eleven-1", label: "ElevenLabs / personal", provider: "elevenlabs" }];
const ELEVEN_ROWS = [
    ["another voice", { provider: "local", keys: ELEVEN_KEY_STORED, account: "eleven-1", answer: { kind: "answered", causes: [] }, voices: 3 }, "hidden"],
    ["no key chosen", { provider: "elevenlabs", keys: [], account: "", answer: { kind: "answered", causes: ["speech=live-account-unselected"] }, voices: 0 }, ["info", "Your step"]],
    ["a chosen key no longer stored", { provider: "elevenlabs", keys: [], account: "eleven-1", answer: { kind: "answered", causes: ["speech=live-key-required"] }, voices: 0 }, ["info", "Your step"]],
    ["the voices being read", { provider: "elevenlabs", keys: ELEVEN_KEY_STORED, account: "eleven-1", answer: { kind: "answered", causes: ["speech=elevenlabs-voices-reading"] }, voices: 0 }, ["info", "Reading voices"]],
    ["before the daemon answers", { provider: "elevenlabs", keys: undefined, account: "eleven-1", answer: { kind: "checking" }, voices: 0 }, ["info", "Reading voices"]],
    ["a failed read", { provider: "elevenlabs", keys: ELEVEN_KEY_STORED, account: "eleven-1", answer: { kind: "answered", causes: ["speech=elevenlabs-voice"] }, voices: 0 }, ["warning", "Could not read voices"]],
    ["another cause holding the Voice step", { provider: "elevenlabs", keys: ELEVEN_KEY_STORED, account: "eleven-1", answer: { kind: "answered", causes: ["speech=local-not-set-up"] }, voices: 0 }, ["info", "Waiting for setup"]],
    ["voices listed", { provider: "elevenlabs", keys: ELEVEN_KEY_STORED, account: "eleven-1", answer: { kind: "answered", causes: [] }, voices: 12 }, ["ok", "12 voices"]],
    ["one voice listed", { provider: "elevenlabs", keys: ELEVEN_KEY_STORED, account: "eleven-1", answer: { kind: "answered", causes: ["brain=unselected"] }, voices: 1 }, ["ok", "1 voice"]]
];
function verifyElevenLabsRow(gate, serviceSource) {
    const hints = new Set();
    for (const [label, facts, want] of ELEVEN_ROWS) {
        const values = {};
        const shell = { settings: { voiceAccount: facts.account }, status: { set: (key, value) => {
            assert.equal(judge.statusWrite(manifest, values, key, value).ok, true, label + ": the ElevenLabs voices row is accepted");
            values[key] = value;
            return "ok";
        } } };
        serviceCall(serviceSource, "publishElevenLabs", { shell, accountReader: { voiceProvider: facts.provider, voiceKeys: facts.keys },
            setupAnswer: facts.answer, voiceOffers: facts.voices }, gate);
        const row = judge.statusRows(manifest, values).find(item => item.key === "elevenLabs");
        if (want === "hidden") {
            assert.equal(row, undefined, label + ": the ElevenLabs voices row is hidden");
            continue;
        }
        assert.ok(row !== undefined, label + ": the ElevenLabs voices row shows");
        assert.deepEqual([row.tone, values.elevenLabs.text, row.action], [{ info: "info", ok: "success", warning: "warning" }[want[0]], want[1], null],
            label + ": the ElevenLabs voices row");
        assert.equal(new URL(row.link.url).hostname, "elevenlabs.io", label + ": the ElevenLabs voices row links ElevenLabs");
        assert.equal(row.hint.includes(row.link.text), want[1] === "Your step" || want[1] === "Could not read voices",
            label + ": the ElevenLabs voices row draws its link only where the user needs the key page");
        assert.equal(oneSentence(row.hint), true, label + ": the ElevenLabs voices row's hint is one sentence");
        assert.equal(facts.account !== "" && facts.keys?.length !== 0 && /Get a key/.test(row.hint), false,
            label + ": the ElevenLabs voices row asks for no key once one is chosen");
        hints.add(row.hint);
    }
    assert.equal(hints.size, 5, "the ElevenLabs voices row: each state words its own hint");
    // The failed read reads as the Voice step does.
    assert.equal(gate.elevenLabsStep(ELEVEN_ROWS[5][1]).hint, gate.readiness({ kind: "answered", causes: ["speech=elevenlabs-voice"] }).setupVoice.hint,
        "the ElevenLabs voices row: a failed read reads as the Setup tab does");
}

// The voiceRoute row the service publishes from the chosen Voice
// provider: each provider its own sentence, naming it, drawn as a fact on
// Details.
function verifyVoiceRoute(gate, serviceSource) {
    const sentences = new Set();
    for (const option of manifest.schema.voiceProvider.options) {
        const values = {};
        const shell = { settings: { voiceProvider: option.value }, status: { set: (key, value) => {
            assert.equal(judge.statusWrite(manifest, values, key, value).ok, true, option.value + ": the Voice provider hint is accepted");
            values[key] = value;
            return "ok";
        } } };
        serviceCall(serviceSource, "publishVoiceRoute", { shell }, gate);
        const status = judge.statusRows(manifest, values);
        assert.equal(settings.detailEntries(status).some(entry => entry.key === "voiceRoute"), true, option.value + ": Details draws the route");
        const hint = status.find(entry => entry.key === "voiceRoute").hint;
        assert.equal(hint.includes(option.label), true, option.value + ": the Voice provider hint names " + option.label);
        sentences.add(hint);
    }
    assert.equal(sentences.size, manifest.schema.voiceProvider.options.length, "the Voice provider hint: one sentence per provider");
}

// Every Jarvis session row beside every Setup summary, its states taken
// from SetupGate.js's own tables and required to hold the contract's: a
// warning or danger row stands beside a Ready summary only when that
// summary names the session, and a summary beside any other row is
// readiness's own. ONLY, when given, narrows the session answers to its own.
function verifyOneSessionJudgement(gate, only) {
    const label = manifest.status.sessionStart.label;
    const every = [{ kind: "failed" }, ...Object.keys(gate.SESSION_BLOCKS).map(block => ({ kind: "blocked", block })),
        ...Object.keys(gate.SESSION_ROWS).map(key => ({ kind: "answer", state: key.split(" ")[0], reason: key.split(" ")[1], detail: "The package's line.", names: null }))];
    const results = only === undefined ? every : only;
    for (const [state, reasons] of Object.entries(SESSION_CONTRACT))
        for (const reason of reasons) assert.ok(Object.hasOwn(gate.SESSION_ROWS, state + " " + reason), state + " " + reason + ": a row of the contract is judged");
    for (const block of ["no-home", "no-account", "not-app", "package"]) assert.ok(Object.hasOwn(gate.SESSION_BLOCKS, block), block + ": a block is judged");
    for (const causes of [[], ["setup=probe-timeout"], ["brain=unselected"], ["speech=local-loading"]]) {
        const setup = plain(gate.readiness({ kind: "answered", causes })).setup;
        for (const result of results)
            for (const wanted of [true, false]) {
                const session = plain(gate.sessionStart(wanted, result));
                const summary = plain(gate.sessionSummary(setup, session));
                const name = JSON.stringify(result) + " beside " + (causes.join(",") || "no cause");
                assert.equal(judge.statusWrite(manifest, {}, "setup", summary).ok, true, name + ": the judge accepts the summary");
                const fault = session.tone === "warning" || session.tone === "danger";
                assert.equal(summary.tone !== "ok" || !fault || String(summary.hint).includes(label), true, name + ": one judgement of the session");
                if (!fault || setup.tone !== "ok") assert.deepEqual(summary, setup, name + ": the summary is readiness's own");
                else assert.equal([summary.tone, summary.text].join(" ") === [setup.tone, setup.text].join(" ")
                    && (setup.hint === undefined || String(summary.hint).startsWith(setup.hint.replace(/\.?$/, ". "))), true, name + ": the session keeps the summary and its caution, a sentence of its own");
            }
    }
}

// Every hint the Jarvis page draws on its Setup, Settings and Details tabs
// keeps the copy rule (judge.hintFits): the manifest's status hints and setting
// descriptions, a description being its field's hint, and each hint
// SetupGate.js and AccountStatus.js word over the cases this suite builds.
// The control: one real hint of each length with its full stop put back on
// one sentence or taken off a longer one fails the rule.
function verifyHintStops(gate) {
    const hints = [];
    const take = (where, value) => {
        if (value !== null && typeof value === "object" && typeof value.hint === "string") hints.push([where, value.hint]);
    };
    for (const [key, entry] of Object.entries(manifest.status)) if (entry.hint !== undefined) hints.push(["status." + key, entry.hint]);
    for (const [key, entry] of Object.entries(manifest.schema)) {
        if (entry.description !== undefined) hints.push(["schema." + key, entry.description]);
        for (const [item, field] of Object.entries(entry.items ?? {})) if (field.description !== undefined) hints.push(["schema." + key + "." + item, field.description]);
    }
    const causes = [...Object.keys(gate.TODO), ...Object.keys(gate.DICTATION), ...Object.keys(gate.MEMORY), ...Object.keys(gate.HOME_TODO), ...Object.keys(gate.CAUTION),
        ...HOME_CAUSES, ...BRAIN_CAUSES, "brain=unnamed", "speech=local-not-set-up"];
    const answers = [...READINESS.map(([, answer]) => answer), ...causes.map(cause => ({ kind: "answered", causes: [cause] })),
        { kind: "answered", causes: ["setup=probe-timeout", "brain=unselected"] }, { kind: "stopped" }, { kind: "checking" },
        ...START_CAUSES.flatMap(([, cause]) => [{ kind: "problem", cause }, { kind: "problem", cause, action: gate.RETRYING_START }])];
    for (const answer of answers)
        for (const [key, value] of Object.entries(plain(gate.readiness(answer)))) {
            take(JSON.stringify(answer) + " " + key, value);
            take(JSON.stringify(answer) + " voiceCheck", gate.voiceCheck(value, null));
        }
    for (const check of [{ kind: "waiting" }, { kind: "finishing" }, { kind: "failed", reason: "check-timeout" }, { kind: "done", result: "ready" },
        { kind: "done", result: "silent" }, { kind: "done", result: "not-heard" }, { kind: "ready" }])
        take("voiceCheck " + JSON.stringify(check), gate.voiceCheck(gate.DONE, check));
    for (const [, cause] of START_CAUSES) for (const retrying of [true, false]) take("startStatus " + cause, gate.startStatus(cause, retrying));
    take("modelStep signed out", gate.modelStep({ tone: "warning", text: "To do", action: "key" }, [], { kind: "signed-out" }));
    for (const [label, answer, provider] of CLONED) take("clonedVoiceStep " + label, gate.clonedVoiceStep(answer, provider));
    for (const [label, offered, provider] of VOICE_KEY) take("voiceKey " + label, gate.voiceKey(offered === null ? null : gate.voiceKeys(offered, { voiceProvider: provider }), { voiceProvider: provider }));
    for (const [label, facts] of ELEVEN_ROWS) take("elevenLabsStep " + label, gate.elevenLabsStep(facts));
    for (const option of manifest.schema.voiceProvider.options) take("voiceRoute " + option.value, gate.voiceRoute(option.value));
    for (const provider of ["realtime", "gemini", "elevenlabs"]) take("previewCost " + provider, gate.previewCost(provider));
    for (const kind of ["failed", "unreadable", "timeout"]) take("checkFailure " + kind, gate.checkFailure(kind, manifest.status.localRuntime));
    const results = [{ kind: "failed" }, ...Object.keys(gate.SESSION_BLOCKS).map(block => ({ kind: "blocked", block })),
        ...Object.keys(gate.SESSION_ROWS).flatMap(key => ["", "The package's line"].map(detail => ({ kind: "answer", state: key.split(" ")[0], reason: key.split(" ")[1], detail,
            names: { home: "~/Jarvis", account: "Claude / personal" } })))];
    for (const result of results)
        for (const wanted of [true, false]) {
            const session = gate.sessionStart(wanted, result);
            take("sessionStart " + JSON.stringify(result), session);
            for (const answer of [{ kind: "answered", causes: [] }, { kind: "answered", causes: ["setup=probe-timeout"] }])
                take("sessionSummary " + JSON.stringify(result), gate.sessionSummary(gate.readiness(answer).setup, session));
        }
    for (const value of ["present", "absent", "locked", "unavailable"]) hints.push(["keyHint " + value, words.keyHint({ label: "fixture / test", value })]);
    for (const state of ["signed-in", "found", "unchecked", "verifying", "verified", "locked", "unavailable"])
        for (const source of ["cli", "variable", "keyring", "local"])
            for (const [value, mismatch, update] of [["present", false, false], ["present", true, false], ["signed-out", true, false], ["present", false, true]])
                hints.push(["accountHint " + [state, source, value, mismatch, update].join(" "),
                    words.accountHint({ state, source, value, plan: "pro", email: "team@example.invalid", mismatch, update })]);
    const drawn = hints.filter(([, hint]) => hint !== "");
    assert.ok(drawn.length >= 100 && drawn.some(([, hint]) => judge.hintSentences(hint).length === 1) && drawn.some(([, hint]) => judge.hintSentences(hint).length > 1),
        "the Jarvis hints of one sentence and of several are read");
    for (const [where, hint] of drawn) assert.equal(judge.hintFits(hint), true, where + ": " + JSON.stringify(hint) + " ends as the copy rule says");
    const one = drawn.find(([, hint]) => judge.hintSentences(hint).length === 1)[1];
    const longer = drawn.find(([, hint]) => judge.hintSentences(hint).length > 1)[1];
    assert.deepEqual([judge.hintFits(one + "."), judge.hintFits(longer.slice(0, -1))], [false, false], "a hint that breaks the copy rule fails the check");
}

function verify(gate) {
    verifySession(gate);
    verifyOneSessionJudgement(gate);
    for (const check of [{ kind: "ready" }, { kind: "done", result: "ready" }]) {
        const value = gate.voiceCheck(gate.readiness({ kind: "answered", causes: ["speech=local-ready-timeout"] }).setupVoice, check);
        assert.deepEqual(plain(value), { tone: "warning", text: "Timed out",
            hint: "Local voice timed out: [turn Jarvis off and on again, or set it up again](page:vgs.jarvis/Setup)",
            action: "setup" }, "voice setup cause survives microphone check");
    }
    for (const [check, tone, action] of [[{ kind: "ready" }, "info", "check"],
        [{ kind: "waiting" }, "info", undefined], [{ kind: "recording" }, "info", undefined],
        [{ kind: "finishing" }, "info", undefined], [{ kind: "failed", reason: "check-timeout" }, "danger", "check"],
        [{ kind: "failed", reason: "speech=local-wake-failed" }, "danger", "check"], [{ kind: "done", result: "ready" }, "ok", "check"],
        [{ kind: "done", result: "silent" }, "warning", "check"], [{ kind: "done", result: "not-heard" }, "warning", "check"]]) {
        const value = gate.voiceCheck(gate.DONE, check);
        assert.deepEqual([value.tone, value.action], [tone, action]);
        assert.equal(judge.statusWrite(manifest, {}, "setupVoice", value).ok, true);
    }
    verifyOneReadiness(gate);
    verifyScreensOnce(gate);
    verifyReadiness(gate);
    verifyChipTitles(gate);
    verifyTiers(gate);
    verifyModelConsumers(gate, fs.readFileSync(serviceFile, "utf8"), fs.readFileSync(accountsFile, "utf8"));
    verifySignIn(gate, fs.readFileSync(accountsFile, "utf8"));
    verifyVoice(gate, fs.readFileSync(serviceFile, "utf8"), fs.readFileSync(accountsFile, "utf8"));
    verifyModelChoice(require(providersFile));
    verifyUnlisted(gate, require(providersFile), fs.readFileSync(serviceFile, "utf8"));
    verifyListRead(require(providersFile), fs.readFileSync(accountsFile, "utf8"));
    verifyDictation(gate, fs.readFileSync(serviceFile, "utf8"), fs.readFileSync(accountsFile, "utf8"));
    verifyElevenLabsRow(gate, fs.readFileSync(serviceFile, "utf8"));
    verifyVoiceRoute(gate, fs.readFileSync(serviceFile, "utf8"));
    for (const [label, value, requires, missing, names] of SETUP) {
        const got = gate.setupValue(value, requires, missing);
        if (names === null) {
            assert.equal(got, value, label + ": the probe value is published as it is");
            continue;
        }
        assert.equal(got.tone, "warning", label);
        assert.equal(got.action, false, label + ": the setup step is withheld");
        for (const command of requires)
            assert.equal(got.text.includes(command), names.includes(command), label + ": the text names " + command + " only while it is missing");
        const at = names.map(command => got.text.indexOf(command));
        assert.deepEqual(at, [...at].sort((x, y) => x - y), label + ": the missing commands in declaration order");
    }
    for (const [label, command, missing, want] of REQUIREMENT)
        // The library's objects come from its own context; compare a copy.
        assert.deepEqual(JSON.parse(JSON.stringify(gate.requirementValue(command, missing))), want, label);
    for (const [label, missing, outdated, want] of FLOORED)
        assert.deepEqual(plain(gate.flooredValue("agent-browser", missing, outdated)), want, "a command with a floor: " + label);
    // The manifest gives both programs Jarvis holds to a version their
    // floor, and the judge accepts each value their rows publish.
    const judged = judge.validateManifest(JSON.parse(fs.readFileSync(path.join(path.dirname(file), "manifest.json"), "utf8")), path.dirname(file)).manifest;
    assert.deepEqual(["agent-browser", "pi"].map(command => typeof judged.requirements.find(row => row.name === command).floor), ["string", "string"],
        "the browser driver and Pi declare a floor");
    for (const [, missing, outdated] of FLOORED)
        assert.equal(judge.statusWrite(judged, {}, "browserDriver", plain(gate.flooredValue("agent-browser", missing, outdated))).ok, true, "the manifest judge accepts the driver row");
    // Neither fact installs or updates its tool: Settings holds the
    // tool and its install action beside the feature.
    const update = judge.statusActionRequest(judged, "vgs.jarvis", true, { setupModel: plain(gate.readiness({ kind: "answered", causes: ["brain=pi-update"] })).setupModel }, "setupModel");
    assert.deepEqual(plain(update), { ok: false, answer: "refused: action=setupModel reason=not-offered" }, "a Pi below its floor offers no step on the AI model row");
    assert.deepEqual(plain(judge.statusActionRequest(judged, "vgs.jarvis", true, { browserDriver: plain(gate.flooredValue("agent-browser", [], ["agent-browser"])) }, "browserDriver")),
        { ok: false, answer: "refused: action=browserDriver reason=undeclared" }, "the driver row declares no step");
    // The Agent fleet row: hidden with no home, done with the home's mail
    // tool, else offering its setup terminal, whose press asks for kendex
    // or another command that terminal needs first.
    for (const [label, home, tool, shown, offered] of FLEET) {
        const value = plain(gate.fleetStep(home, tool));
        assert.equal(judge.statusWrite(judged, {}, "setupFleet", value).ok, true, label + ": the manifest judge accepts the row");
        const row = judge.statusRows(judged, { setupFleet: value }).find(entry => entry.key === "setupFleet");
        assert.equal(row !== undefined, shown, label + ": the row shows");
        if (!shown) continue;
        assert.deepEqual([value.tone, row.action.offered, row.action.tui, row.action.label], [offered ? "info" : "ok", offered, offered ? "setup-fleet" : "", judged.status.setupFleet.action.label],
            label + ": the row offers its setup");
        assert.deepEqual(plain(judge.tuiRunFor(judged, true, "/sources", { launcher: "present", busy: [], run: "test" }, "setup-fleet", ["kendex"])),
            { ok: true, kind: "install", commands: ["kendex"] }, label + ": its press without kendex asks for it");
    }
    verifySetupButtons(gate, judged);
    verifyClonedVoice(gate, judged);
    // Its control: the manifest with a launcher entry for the fleet TUI,
    // which the manager then lists in every state.
    const listed = plain(judged);
    listed.tui["setup-fleet"].entry = { label: "Install kendex", icon: "workflow", group: "Jarvis" };
    assert.throws(() => verifySetupButtons(gate, listed), assert.AssertionError, "a listed fleet TUI turns the check red");
    assert.deepEqual(plain(judge.tuiMissingRequirements(judged, "setup-fleet", ["kendex", "git", "tmux"])), ["git", "kendex"],
        "the setup terminal needs git and kendex");
    for (const command of ["git", "kendex"])
        assert.equal(judged.requirements.find(row => row.name === command).optional, true, command + " is optional: Jarvis works without the fleet");
    verifyCheckedReader(gate, fs.readFileSync(localRuntimeFile, "utf8"));
    verifyVoiceStepRepublish(gate, fs.readFileSync(serviceFile, "utf8"));
    verifyCheckFailures(gate);
    verifyOneLocalVoiceTask(gate, gate.localVoiceStep);
    verifyPathForm(gate);
    for (const [label, cause, kind] of START_CAUSES) {
        const words = gate.startCause(cause);
        assert.equal(words.kind, kind, label + ": classified");
        assert.equal(typeof words.title, "string", label + ": title");
        assert.equal(typeof words.action, "string", label + ": action");
        assert.equal(words.lines.length, 1, label + ": detail line");
        const setup = gate.readiness({ kind: "problem", cause }).setup;
        assert.deepEqual([setup.text, setup.hint], [words.title, words.action], label + ": the start failure summary says its state and hint");
        assert.deepEqual([setup.lines, keyedCauses(setup, ["text", "hint"])], [undefined, []], label + ": the start failure summary draws no keyed cause");
    }
    let fallback;
    assert.doesNotThrow(() => { fallback = gate.startCause(ARBITRARY_STDERR); }, "arbitrary stderr maps to daemon exit");
    assert.equal(fallback.kind, "daemon-exit", "arbitrary stderr maps to daemon exit");
    for (const cause of ["jarvis: daemon=exit code=1 status=0 " + "x".repeat(240), "jarvis: protocol=bad\u0001line"]) {
        const words = gate.startCause(cause);
        const daemon = gate.startStatus(cause, false);
        const setup = gate.readiness({ kind: "problem", cause }).setup;
        assert.equal(judge.statusWrite(manifest, {}, "daemon", daemon).ok, true, "daemon accepts bounded cause line");
        assert.equal(judge.statusWrite(manifest, {}, "setup", setup).ok, true, "setup accepts bounded cause line");
        assert.equal(words.lines[0].length <= 200 && !/[\u0000-\u001f]/.test(words.lines[0]), true, "cause line is bounded and printable");
    }
    verifyWordedText(gate);
    verifyHintStops(gate);
}

verify(load(file));
verifyVoiceConsumers(load(file));
console.log("test-jarvis-setup-gate: consumer=Setup hint=Choose an AI model in [Settings > Jarvis > AI model](page:vgs.jarvis/Settings)");

// Each control removes one rule from a copy and keeps the text around it:
// [label, needle, replacement].
const CONTROLS = [
    ["a failed start's tooltip draws its keyed cause", 'hint: retrying ? RETRYING_START : problem.action,', 'hint: retrying ? RETRYING_START : "jarvis: hello=timeout",', "the bar tooltip draws no keyed cause"],
    ["the stopped notice draws its keyed cause", 'message: sentence(problem.action), tone: "danger"', 'message: sentence(cause), tone: "danger"', "the stopped notice draws no keyed cause"],
    ["the mute notice draws its keyed cause", '"Mute request could not be saved: " + startCause(cause).title', '"Mute request could not be saved: " + String(cause)', "the mute refused notice draws no keyed cause"],
    ["the Daemon row loses its cause", 'hint: retrying ? RETRYING_START : problem.action, lines: problem.lines };', 'hint: retrying ? RETRYING_START : problem.action };', "the Daemon row keeps the cause"],
    ["check failure hidden", 'if (check.kind === "failed") return', 'if (false) return'],
    ["microphone check hides a setup cause", 'value.tone !== "ok" || ', "", "voice setup cause survives microphone check"],
    ["silent check is ready", 'if (check.result === "silent") return { tone: "warning"', 'if (check.result === "silent") return { tone: "ok"'],
    ["the AI model hint names the Settings field", '"brain=unselected": "Choose an AI model in [Settings > Jarvis > AI model](page:vgs.jarvis/Settings)"', '"brain=unselected": "Choose an AI model in Settings"', "Setup AI model hint"],
    ["present keys still offer Add key", 'var absent = keys !== undefined && keys.every(function (key) { return key.value === "absent"; });', 'var absent = keys !== undefined;'],
    ["a signed-in app still offers Add key", 'access.kind === "absent"', 'access.kind !== "checking"'],
    ["a signed-out cause offers Add key", 'cause === "brain=signed-out" ? "signIn" : ', "", "a signed-out AI model: setupModel"],
    ["a signed-out cause loses Sign in beside a key", 'if (value.action !== "key") return value;', "if (value.action === undefined) return value;"],
    ["a signed-out app offers Add key", 'if (absent && access.kind === "signed-out") return', "if (false) return"],
    ["a signed-out app keeps the unselected hint", "{ hint: SIGNED_OUT_HINT, action: \"signIn\" }", "{ action: \"signIn\" }",
        "signed-out hint replaces the unselected one"],
    ["a signed-out app reads as none", 'account.signIn === true; }) ? "signed-out"', 'false; }) ? "signed-out"'],
    ["a merely found app suppresses Add key", '["signed-in", "verified", "verifying"].indexOf(account.state) !== -1', '["found", "unchecked", "signed-in", "verified", "verifying"].indexOf(account.state) !== -1'],
    ["checking account discovery offers Add key", 'access.kind === "absent"', 'access.kind !== "present"'],
    ["memory guidance is a badge", "out.setupVoice = MEMORY[cause];", "out.setupVoice = Object.assign({}, MEMORY[cause], { lines: [MEMORY[cause].hint], hint: undefined });"],
    ["an optional reading keeps its open tone", 'value.tone === "ok" ? value : Object.assign({}, value, { tone: "info" })', "value", "the browser and input read optional"],
    ["Local voice offers setup beside the Voice step", 'if (voice.action === "setup") {', "if (false) {", "partial under Local: each screen once"],
    ["Local voice is required under a cloud voice", "return hearsLocally(provider) ? value : optionalStep(value);", "return true ? value : optionalStep(value);", "partial under Realtime: "],
    ["Local voice stays open beside the Voice step", 'var row = { tone: "info", text: value.text,', "var row = { tone: value.tone, text: value.text,", "partial under Local: the browser and input read optional"],
    ["Local voice does not say where its setup is", "value.action === true && value.hint === undefined ? [VOICE_STEP_SETS_UP] : []", "[]", "not set up: its line count"],
    ["Local voice says where its setup is while it runs", "value.action === true && value.hint === undefined ? [VOICE_STEP_SETS_UP] : []", "[VOICE_STEP_SETS_UP]", "setting up: its line count"],
    ["a Voice step with any action takes the local setup", 'if (voice.action === "setup") {', "if (voice.action) {", "dictation setup leaves local voice maintenance available: the rows that offer"],
    ["a timed-out check gets warning severity", 'if (kind === "timeout") return { tone: "info",', 'if (kind === "timeout") return { tone: "warning",', "timeout: the check remains informational"],
    ["a timed-out check offers setup", 'runs it again after the next setup", action: false };', 'runs it again after the next setup", action: true };',
        "the row offers its setup only while setup mends it"],
    ["a timed-out check draws its keyed cause", 'hint: "Jarvis does not need this check to answer and runs it again after the next setup", action: false };', 'hint: "setup=probe-timeout", action: false };',
        "timeout: the row draws no keyed cause"],
    ["the Local voice row names a setup the Voice step does not offer", 'if (voice.action === "setup") {', 'if (voice.action === "setup" || voice.tone === "warning") {',
        "dictation setup leaves local voice maintenance available: the rows that offer"],
    ["a home hint names a path with no page", '"home=path": "Jarvis cannot use this folder: [choose a Home folder](page:vgs.jarvis/Settings) inside your own home directory"',
        '"home=path": "Jarvis cannot use this folder. Choose a folder inside your own home directory in Settings > Home."', "the Settings path has the one form"],
    ["the voices hint names the Voice field in plain words", 'var ELEVENLABS_READY = "[Choose one in the Voice list](page:vgs.jarvis/Settings/voice)";', 'var ELEVENLABS_READY = "Choose one in the Voice list";',
        "the voices hint links the Voice field"],
    ["a failed check names another reader's action", "var label = entry.action !== undefined ? entry.action.label : entry.actions.setup.label;", 'var label = "Set up local voice";', "the hint names"],
    ["memory refusal offers reinstall", 'if (Object.prototype.hasOwnProperty.call(MEMORY, cause)) {', 'if (false) {'],
    ["loading is initial checking", "out.setupVoice = LOADING;", "out.setupVoice = CHECKING;"],
    ["loading offers setup", 'if (cause === "speech=local-loading" || cause === "speech=dictation-starting" || cause === "speech=elevenlabs-voices-reading") {', 'if (cause === "speech=dictation-starting" || cause === "speech=elevenlabs-voices-reading") {'],
    ["a starting recording offers setup", 'if (cause === "speech=local-loading" || cause === "speech=dictation-starting" || cause === "speech=elevenlabs-voices-reading") {', 'if (cause === "speech=local-loading" || cause === "speech=elevenlabs-voices-reading") {', "daemon starting"],
    ["a voice list being read reads as a failed one", 'if (cause === "speech=local-loading" || cause === "speech=dictation-starting" || cause === "speech=elevenlabs-voices-reading") {', 'if (cause === "speech=local-loading" || cause === "speech=dictation-starting") {', "ElevenLabs voices being read"],
    ["missing voxtype is not named", 'var ACTION_REQUIRES = { dictation: ["voxtype"] };', "var ACTION_REQUIRES = {};", "voxtype missing"],
    ["missing voxtype withholds Set up dictation", 'if (value.action === "dictation") withheld.action = "dictation";', 'if (false) withheld.action = "dictation";', "voxtype missing"],
    ["another voxtype offers setup", '"speech=dictation-elsewhere": { tone:',
        '"speech=dictation-elsewhere": { action: "dictation", tone:', "another voxtype"],
    ["the holder omits a missing engine name", 'if (!setup.compiled) lines.push(', 'if (false) lines.push(', "the holder names"],
    ["the holder omits a missing model name", 'if (!setup.installed) lines.push(', 'if (false) lines.push(', "the holder names"],
    ["a failed daemon offers no setup", '"speech=dictation-failed": { tone: "warning", text: "To do", hint: "Set up dictation again", action: "dictation" },',
        '"speech=dictation-failed": { tone: "warning", text: "To do", hint: "Set up dictation again" },', "the Voice step"],
    ["the voxtype row shows for any voice", 'return hearsLocally(provider) ? requirementValue("voxtype", missing) : { hidden: true };', 'return requirementValue("voxtype", missing);', "Realtime voice"],
    ["the ElevenLabs voices row never shows", 'if (facts.provider !== "elevenlabs") return { hidden: true };', "return { hidden: true };", "the ElevenLabs voices row"],
    ["a stored ElevenLabs key still reads as the user's step", 'if (!chosen) return { tone: "info", text: "Your step" };', 'return { tone: "info", text: "Your step" };', "the ElevenLabs voices row"],
    ["a failed voice read reads as being read", 'if (causes.indexOf("speech=elevenlabs-voice") !== -1) return', "if (false) return", "the ElevenLabs voices row"],
    ["listed voices still link the key page", 'var ELEVENLABS_READY = "[Choose one in the Voice list](page:vgs.jarvis/Settings/voice)";', 'var ELEVENLABS_READY = "[Choose one in the Voice list](page:vgs.jarvis/Settings/voice), or open ElevenLabs API keys";',
        "draws its link only where the user needs the key page"],
    ["a failed voice read names no key page", "check under ElevenLabs API keys that it may read voices", "check that it may read voices",
        "draws its link only where the user needs the key page"],
    ["an ElevenLabs voices hint has more than one sentence", 'var ELEVENLABS_READING = "Jarvis is reading the voices of your ElevenLabs key";',
        'var ELEVENLABS_READING = "Jarvis is reading the voices of your ElevenLabs key. It takes a moment.";', "hint is one sentence"],
    ["a key row hint has more than one sentence", 'gemini: "Get a Gemini key from Google AI Studio to use the Gemini Live voice"',
        'gemini: "Get a Gemini key from Google AI Studio. It serves the Gemini Live voice."', "the key row's hint is one sentence"],
    ["the ElevenLabs key row names no key page", "Get an ElevenLabs key from ElevenLabs API keys to speak", "Get an ElevenLabs key to speak",
        "the key row names the page of each key its hint asks for"],
    ["every voice provider reads as Local", "var route = VOICE_ROUTES[setting];", "var route = VOICE_ROUTES.local;", "the Voice provider hint"],
    ["the ElevenLabs voice runs no dictation", 'return provider === "local" || provider === "elevenlabs";', 'return provider === "local";', "ElevenLabs"],
    ["another device is no cause", 'return otherDevice(state) ? "speech=dictation-device" : "";', 'return "";', "another device"],
    ["the Realtime voice takes the cause", 'if (!hearsLocally(provider) || state === null) return "";', 'if (state === null) return "";', "Realtime voice"],
    ["the service starts another device", 'return otherDevice(state) ? "refused: dictation=device" : "";', 'return "";', "another device"],
    ["a step's named action is dropped", ': typeof value.action === "string" ? value : noAction(value);', ': noAction(value);', "the Voice step"],
    ["a stored key replaces the voice the user chose", 'if (settings.voiceProvider !== "auto") return settings.voiceProvider;', 'if (false) return settings.voiceProvider;'],
    ["a removed key keeps Realtime", 'offered.some(function (key) { return key.provider === "openai" && key.value === settings.voiceAccount; })', "true"],
    ["Auto runs a Gemini key as Realtime", 'return key.provider === "openai" && key.value === settings.voiceAccount;', "return key.value === settings.voiceAccount;"],
    ["the key row offers another voice's keys", "return keys.filter(function (key) { return key.provider === provider; })", "return keys.filter(function (key) { return key.provider === \"openai\"; })"],
    ["the key row names one voice's key", 'var hint = VOICE_KEY_HINTS[cloudSpeech(settings.voiceProvider) ? settings.voiceProvider : "other"];',
        "var hint = VOICE_KEY_HINTS.realtime;"],
    ["Local and Auto read the Realtime key's hint", '? settings.voiceProvider : "other"];', '? settings.voiceProvider : "realtime"];'],
    ["the preview names one voice's key", "return PREVIEW_COSTS[provider];", "return PREVIEW_COSTS.realtime;"],
    ["the ElevenLabs preview plays as local", 'return provider === "realtime" || provider === "gemini" || provider === "elevenlabs";', 'return provider === "realtime" || provider === "gemini";'],
    ["an unread key list runs Realtime", ' || offered === undefined) return "local";', ') return "local";\n    if (offered === undefined) return "realtime";'],
    ["Always talk mode runs Realtime", 'if (settings.mode === "always" || ', "if ("],
    ["no key offers no Add key", 'text: "No key stored", hint: hint, action: true }', 'text: "No key stored", hint: hint, action: false }'],
    ["a stored key still offers Add key", 'hint: VOICE_KEY_STORED[voiceKeyProvider(settings)], action: false }', 'hint: VOICE_KEY_STORED[voiceKeyProvider(settings)], action: true }'],
    ["a stored key's row says to get a key", 'hint: VOICE_KEY_STORED[voiceKeyProvider(settings)], action: false }', 'hint: hint, action: false }'],
    ["a stored key's row names one voice", 'hint: VOICE_KEY_STORED[voiceKeyProvider(settings)], action: false }', 'hint: VOICE_KEY_STORED.openai, action: false }'],
    ["a stored key's row names no field", 'then choose it in Voice key"', 'then choose it"',
        "names where another key goes in and where it is chosen"],
    ["a stored key's row links the tab it is drawn on", 'then choose it in Voice key"',
        'then choose it in [Voice key](page:vgs.jarvis/Settings)"', "names where another key goes in and where it is chosen"],
    ["a failed key read offers no Add key", 'text: "Could not check", hint: hint, action: true }', 'text: "Could not check", hint: hint, action: false }'],
    ["the Realtime voice offers clone setup", 'var reason = provider !== "local" ? CLONE_WITHHELD.provider : ', "var reason = ", "the Realtime voice withholds setup"],
    ["a tier off the graphics card offers clone setup", 'value.tierReady === false ? CLONE_WITHHELD.tier : null', "null", "a tier off the graphics card withholds setup"],
    ["the two withheld reasons swapped", 'provider !== "local" ? CLONE_WITHHELD.provider : value.tierReady === false ? CLONE_WITHHELD.tier : null',
        'provider !== "local" ? CLONE_WITHHELD.tier : value.tierReady === false ? CLONE_WITHHELD.provider : null', "the Realtime voice withholds setup: the hint names provider"],
    ["a not-ready clone row reads as an open step", 'var row = { tone: value.tone === "ok" ? "ok" : "info", text: value.text };', "var row = { tone: value.tone, text: value.text };",
        "a recording keeps Remove beside another tier"],
    ["a recording loses Remove under another voice", 'if (reason !== null && action !== "remove")', "if (reason !== null)", "a recording keeps Remove under the Realtime voice"],
    ["a clone row keeps a failed read's keyed line", "    else if (row.tone === \"ok\") row.hint = CLONE_READY_HINT;\n    return row;",
        "    else if (row.tone === \"ok\") row.hint = CLONE_READY_HINT;\n    if (value.lines !== undefined) row.lines = value.lines;\n    return row;",
        "a timed-out read words its state: the row draws no keyed cause"],
    ["a ready clone row keeps the setup instruction", '    else if (row.tone === "ok") row.hint = CLONE_READY_HINT;\n', "", "a ready cloned voice offers Remove and says what the recording gives"],
    ["a ready clone hint has more than one sentence", 'var CLONE_READY_HINT = "Jarvis speaks in this voice while Cloned voice is on";',
        'var CLONE_READY_HINT = "The recording is ready. Jarvis speaks in this voice while Cloned voice is on.";'],
    ["a failed clone read offers a boolean", 'var action = value.action === true ? "setup" : value.action;', "var action = value.action;", "a failed read offers setup"],
    ["the fleet row shows with no home", "if (home === null)", "if (false)", "no home chosen: the row shows"],
    ["the fleet row hides once the tool is found", "if (tool !== null) return DONE;", "if (tool !== null) return { hidden: true };", "a home with the mail tool: the row shows"],
    ["the fleet row offers no setup", 'if (tool !== null) return DONE;\n    return { tone: "info", text: "Optional", action: true };', 'if (tool !== null) return DONE;\n    return { tone: "info", text: "Optional", action: false };'],
    ["a selected account still offers sign-in", 'if (brains.some(function (choice) { return choice.value === brain; }))', 'if (false)', "sign-in follows the selected account"],
    ["an unread account offers sign-in", 'if (brains === null) return Object.assign({}, CHECKING, { hint: "Jarvis is checking your accounts" });', 'if (brains === null) return { tone: "info", text: "Optional", action: true };', "sign-in follows the selected account"],
    ["a missing command does not withhold setup", "return missing.indexOf(command) !== -1; });", "return false; });"],
    ["the withheld step keeps its action", 'else if (typeof value.action !== "string") withheld.action = false;', 'else withheld.action = value.action;'],
    ["a withheld named action reads false", 'if (value.action === "dictation") withheld.action = "dictation";\n    else if (typeof value.action !== "string") withheld.action = false;', 'withheld.action = false;', "accepted status setupVoice"],
    ["any missing command withholds setup", "var lacking = requires.filter(", "var lacking = missing.filter("],
    ["the withheld text names every required command", 'lacking.join(" and ")', 'requires.join(" and ")'],
    ["a missing requirement offers no install", 'if (missing.indexOf(command) === -1) return { tone: "ok"', 'if (true) return { tone: "ok"'],
    ["a found requirement offers its install", 'if (missing.indexOf(command) === -1) return { tone: "ok"', 'if (false) return { tone: "ok"'],
    ["the Realtime voice offers the local install action", 'return cause.indexOf("speech=live-") !== 0 && ', 'return true && '],
    ["Always mode offers the local install action", ' && cause !== "speech=always-local-voice";', ";"],
    ["Always mode has no hint of its own", '    "speech=always-local-voice": ', '    "speech=always-local-voice-unused": '],
    ["a cause marks no step", "out[REQUIRED[step]] = hint === undefined", "void (hint === undefined)"],
    ["a cause marks the other step", 'speech: "setupVoice", brain: "setupModel" };', 'speech: "setupModel", brain: "setupVoice" };'],
    ["a caution reads not ready", 'blocking.length === 0 ? { tone: "ok", text: "Ready", hint:', 'false ? { tone: "ok", text: "Ready", hint:', "the bar and the Setup status state one readiness"],
    ["a caution turns its step to do", 'var blocking = answer.causes.filter(function (cause) { return !Object.prototype.hasOwnProperty.call(CAUTION, cause); });\n        var out',
        'var blocking = answer.causes.filter(function (cause) { return !Object.prototype.hasOwnProperty.call(CAUTION, cause); });\n        REQUIRED.setup = "setupVoice"; TODO["setup=probe-timeout"] = CAUTION["setup=probe-timeout"]; blocking = answer.causes;\n        var out'],
    ["the timed-out Local voice row asks for a restart", 'hint: "Jarvis does not need this check to answer and runs it again after the next setup", action: false };',
        "hint: START_RESTART, action: false };", "probe timeout: the Local voice row asks for no restart beside Ready"],
    ["the probe timeout caution asks for a restart", '"setup=probe-timeout": "Jarvis answers, but its check of the local voice did not finish"',
        '"setup=probe-timeout": "Turn Jarvis off and on again in [Settings > Jarvis](page:vgs.jarvis/Settings)"', "probe timeout: the caution asks for no restart beside Ready"],
    ["a wire-defect title overflows the chip", 'title: "Jarvis message error"', 'title: "Jarvis and its daemon could not understand each other"', "fits the Setup status chip"],
    ["a home cause marks no step", 'if (REQUIRED[step] === "setupHome") {', 'if (false) {'],
    ["a home text cause marks the voice step", 'guidance: "setupHome", ', 'guidance: "setupVoice", '],
    ["the home causes share one hint", "hint: Object.prototype.hasOwnProperty.call(HOME_TODO, cause) ? HOME_TODO[cause] : HOME_STEP_TODO };", "hint: HOME_STEP_TODO };"],
    ["the completed Home folder step disappears", 'var HOME_READY = { tone: "ok", text: "Done" };', "var HOME_READY = { hidden: true };"],
    ["the unchecked Home folder reads Done", 'var HOME_UNCHECKED = { tone: "warning", text: "Not checked" };', 'var HOME_UNCHECKED = { tone: "ok", text: "Done" };'],
    ["the home folder step offers an action", 'out.setupHome = { tone: "warning", text: "To do",', 'out.setupHome = { tone: "warning", text: "To do", action: true,'],
    ["any account shows Copilot Memory", 'account.provider === "copilot" && ', ""],
    ["a signed-out Copilot shows Copilot Memory", ' && account.value === "present"; })', "; })"],
    ["a command below its floor reads as installed", 'if (outdated.indexOf(command) !== -1) return { tone: "warning", text: "Needs an update" };', ""],
    ["a missing command with a floor reads as installed", 'if (missing.indexOf(command) !== -1) return { tone: "warning", text: "Not installed" };', ""],
    ["a Pi older than its floor offers Add key", '            if (cause === "brain=pi-update") out[REQUIRED[step]] = noAction(out[REQUIRED[step]]);\n', ""],
    ["a Pi older than its floor takes the step's hint", '    "brain=pi-update": ', '    "brain=pi-update-removed": ', "Pi recovery names the required version"],
    ["the brain causes share one hint", "var hint = Object.prototype.hasOwnProperty.call(TODO, cause) ? TODO[cause] : STEP_TODO[step];", "var hint = STEP_TODO[step];"],
    ["an unknown cause has no hint", "var hint = Object.prototype.hasOwnProperty.call(TODO, cause) ? TODO[cause] : STEP_TODO[step];", "var hint = TODO[cause];"],
    ["local voice repeats its action as its hint", "var STEP_TODO = { brain:", 'var STEP_TODO = { speech: "fixture repeat", brain:'],
    ["the timed-out Voice step draws its cause", ': { tone: "warning", text: text, hint: hint, action: action };',
        ': cause === "speech=local-ready-timeout" ? { tone: "warning", text: text, hint: hint, action: action, lines: [String(cause)] } : { tone: "warning", text: text, hint: hint, action: action };',
        "voice setup cause survives microphone check"],
    ["the timed-out Voice step reads to do", 'var text = cause === "speech=local-ready-timeout" ? TIMED_OUT : "To do";', 'var text = "To do";', "voice setup cause survives microphone check"],
    ["a start failure summary draws its cause", "hint: answer.action || problem.action },", "hint: answer.action || problem.action, lines: problem.lines },",
        "hello timeout: the start failure summary draws no keyed cause"],
    ["a stopped summary draws its reason as a line", 'hint: "Turn Jarvis off and on again" }', 'lines: ["Turn Jarvis off and on again"] }'],
    ["the not-ready summary draws its causes", ': { tone: "warning", text: "Not ready" },', ': { tone: "warning", text: "Not ready", lines: answer.causes.map(String) },', "nothing set up: the summary draws no keyed cause"],
    ["a caution summary draws its cause", 'return CAUTION[cause]; })) }', 'return CAUTION[cause]; })), lines: answer.causes.map(String) }', "probe timeout: the summary draws no keyed cause"],
    ["causes leave the summary ready", 'setup: answer.causes.length === 0 ? { tone: "ok", text: "Ready" }', 'setup: true ? { tone: "ok", text: "Ready" }'],
    ["checking reads done", 'return { setup: CHECKING_SUMMARY, setupHome: HOME_UNCHECKED, setupVoice: CHECKING, setupModel: noAction(CHECKING) };', 'return { setup: CHECKING_SUMMARY, setupHome: HOME_UNCHECKED, setupVoice: DONE, setupModel: noAction(DONE) };'],
    ["an optional step reads open when ok", 'return value.tone === "ok" ? value :', "return false ? value :", "done under Local: the browser and input read optional"],
    ["an optional step drops its action", 'Object.assign({}, value, { tone: "info" })', 'Object.assign({}, value, { tone: "info", action: false })', "partial under Local: the rows that offer"],
    ["the checking summary offers a step", "return { setup: CHECKING_SUMMARY,", "return { setup: CHECKING,"],
    ["a stopped daemon's steps read checking", 'case "stopped":\n        return { setup: { tone: "danger", text: "Not ready", hint: "Turn Jarvis off and on again" },\n            setupHome: HOME_UNCHECKED, setupVoice: UNCHECKED, setupModel: noAction(UNCHECKED) };',
        'case "stopped":\n        return { setup: { tone: "danger", text: "Not ready", hint: "Turn Jarvis off and on again" },\n            setupHome: HOME_UNCHECKED, setupVoice: CHECKING, setupModel: noAction(CHECKING) };'],
    ["a keyed start cause has no words", '[/^jarvis: hello=timeout$/, { kind: "hello-timeout", title: "Jarvis did not answer in time", detail: "Jarvis could not finish starting.", action: START_RESTART }],', ""],
    ["an arbitrary stderr line has no words", "return { kind: DAEMON_EXIT.kind, title: DAEMON_EXIT.title, action: DAEMON_EXIT.action, lines: [DAEMON_EXIT.detail] };", 'throw new Error("jarvis-setup: start-cause=" + cause + " has no words");'],
    ["a cause naming no step is taken", 'if (!Object.prototype.hasOwnProperty.call(REQUIRED, step)) throw new Error("jarvis-setup: cause=" + cause + " names no step");', ""],
    ["auto names no tier of its own", 'return wanted === "auto" ? pick : wanted;', "return wanted;"],
    ["a ready wanted tier downloads again", "if (wantedTier(wanted, pick) === ready) return null;\n    return wanted", "return wanted"],
    ["auto passes its own name to setup", 'return wanted === "auto" ? [] : [wanted];', "return [wanted];"],
    ["the setting ignores what a run left ready", "if (wantedTier(wanted, pick) === ready) return null;\n    return ready ===", "return null;\n    return ready ==="],
    ["the setting follows a ready wanted tier", "if (wantedTier(wanted, pick) === ready) return null;\n    return ready ===", "return ready ==="],
    ["the ready pick is written by name", 'return ready === pick ? "auto" : ready;', "return ready;"],
    ["a stopped session offers no Start", '{ tone: "info", text: "Starts at the next boot", hint: SESSION_BOOT, action: "start" }', '{ tone: "info", text: "Starts at the next boot", hint: SESSION_BOOT }', "the action the row offers"],
    ["a failure offers no Retry", '"failed launch-failed": { tone: "danger", text: "Not started", detail: true, action: "retry" }', '"failed launch-failed": { tone: "danger", text: "Not started", detail: true }', "the action the row offers"],
    ["a missing tmux offers a step", '"blocked tmux-missing": { tone:',
        '"blocked tmux-missing": { action: "retry", tone:', "the action the row offers"],
    ["the boot setting hides a running session", '    if (row.wanted) value = wanted ?', '    if (row.wanted || !wanted) value = wanted ?', "the boot setting changes no row"],
    ["an answer outside the contract reads as a state", "    if (row === undefined) return failure;", '    if (row === undefined) return { tone: "ok", text: "Running", hint: "Planted." };', "outside the contract"],
    ["the package's failure line is dropped", 'var hint = row.detail ? (result.detail !== "" ? result.detail : SESSION_FAILED)', "var hint = row.detail ? SESSION_FAILED", "the package's own line is shown"],
    ["the unapplied selection is not shown", "    if (result.unapplied !== undefined) value.lines = [SESSION_BLOCKS[result.unapplied]];", "", "a selection that failed its check"],
    ["names too long for a hint are published", "hint === \"\" || hint.length > SESSION_HINT_MAX ?", "hint === \"\" ?", "the manifest judge accepts the row"],
    ["a starting session is not live", 'var SESSION_LIVE = ["running", "starting", "handing-over"];', 'var SESSION_LIVE = ["running", "handing-over"];', "the states of a session that lives"],
    ["the session field draws while the setting is off", "return wanted ? SESSION_MODES : [];", "return SESSION_MODES;", "the session field while the setting is false"],
    ["the no-home hint names no Settings path", "choose one in [Settings > Jarvis > Home folder](page:vgs.jarvis/Settings)", "choose a Home folder", "no-home: the hint is one sentence that names its Settings path"],
    ["the no-home hint has more than one sentence", "without a home folder: choose one in", "without a home folder. Choose one in", "no-home: the hint is one sentence that names its Settings path"],
    ["a choice not made reads as a fault", 'var SESSION_CHOICES = ["no-account", "not-app", "no-home"];', "var SESSION_CHOICES = [];", "a block's tone"],
    ["a missing package reads optional", 'var SESSION_CHOICES = ["no-account", "not-app", "no-home"];', 'var SESSION_CHOICES = ["no-account", "not-app", "no-home", "package"];', "package: a block's tone"],
    ["a Ready summary ignores the session", "    if (setup.tone !== \"ok\" || !Object.prototype.hasOwnProperty.call(SESSION_FAULTS, session.tone)) return setup;",
        "    return setup;", "one judgement of the session"],
    ["the session drops the summary's caution", 'hint: setup.hint === undefined ? fault : joinedHint([setup.hint, fault])', "hint: fault",
        "keeps the summary and its caution"],
    ["the session's fault runs on from the summary's caution", 'hint: setup.hint === undefined ? fault : joinedHint([setup.hint, fault])', 'hint: setup.hint === undefined ? fault : setup.hint + " " + fault', "keeps the summary and its caution"],
    ["a summary that is not ready names the session", 'if (setup.tone !== "ok" || !', "if (!", "the summary is readiness's own"],
    ["a one-sentence hint ends with a full stop", 'hint: "A preview of the Realtime voice may cost money", action: true }', 'hint: "A preview of the Realtime voice may cost money.", action: true }',
        "ends as the copy rule says"],
    ["a longer hint leaves its last full stop off", 'Open Accounts to check them."', 'Open Accounts to check them"',
        "ends as the copy rule says"],
    ["the stopped notice takes the hint's one sentence as it is", "message: sentence(problem.action),", "message: problem.action,", "notice's message ends as a sentence"],
    ["joined hints run on with no full stop between them", "hints.map(sentence).join", "hints.join", "keeps the summary and its caution, a sentence of its own"]
];

const source = fs.readFileSync(file, "utf8");
const temp = fs.mkdtempSync(path.join(os.tmpdir(), "jarvis-setup-gate-control-"));
try {
    const microphoneAction = path.join(path.dirname(file), "tui/check-microphone.sh");
    verifyMicrophoneAction(microphoneAction, temp);
    const wrongAction = path.join(temp, "wrong-microphone-action.sh");
    fs.writeFileSync(wrongAction, fs.readFileSync(microphoneAction, "utf8").replace("invoke check-microphone", "invoke talk-down"));
    assert.throws(() => verifyMicrophoneAction(wrongAction, temp), assert.AssertionError);
    console.log("test-jarvis-setup-gate: control=microphone-action-target rejected=true");
    const previewAction = path.join(path.dirname(file), "tui/preview-voice.sh");
    const editAction = path.join(path.dirname(file), "tui/edit-personality.sh");
    verifyPreviewAction(previewAction, temp);
    verifyEditAction(editAction, temp);
    console.log("test-jarvis-setup-gate: case=preview-and-edit-screens passed=true");
    for (const [name, script, verify, needle, replacement] of [
        ["preview-cost-question", previewAction, verifyPreviewAction, '  cloud) vgs_tui_confirm "This preview uses your cloud voice key and may cost money. Play it?" || exit 0 ;;\n', "  cloud) ;;\n"],
        ["preview-muted-cause", previewAction, verifyPreviewAction, '    "refused: preview=muted") vgs_tui_error "Jarvis is muted. Unmute Jarvis, then try again." ;;\n', ""],
        ["edit-editor-status", editAction, verifyEditAction, 'vgs_tui_edit "$file"', 'vgs_tui_edit "$file" || true'],
        ["edit-close-prompt", editAction, verifyEditAction, "trap 'status=$?; [[ $status == 0 ]] || vgs_tui_close_prompt \"$status\"' EXIT\n", ""]
    ]) {
        const source = fs.readFileSync(script, "utf8");
        assert.equal(source.split(needle).length, 2, name + " mutation match");
        const copy = path.join(temp, name + ".sh");
        fs.writeFileSync(copy, source.replace(needle, replacement));
        assert.throws(() => verify(copy, temp), assert.AssertionError, name + " must turn red");
        console.log("test-jarvis-setup-gate: control=" + name + " rejected=true");
    }
    // The Voice field offers the voices Jarvis publishes, the first standing
    // for the unset voice, keeps the configured voice while none are
    // published, and draws nothing then.
    const voiceOffers = [{ label: "Alloy, American English, female", value: "af_alloy" }, { label: "Heart, American English, female", value: "af_heart" }];
    assert.deepEqual(JSON.parse(JSON.stringify(judge.settingChoices(manifest, { voices: voiceOffers }, { ...manifest.settings, voice: "af_heart" }).voice)),
        [{ label: "Alloy, American English, female", value: "" }, { label: "Heart, American English, female", value: "af_heart" }]);
    assert.deepEqual(JSON.parse(JSON.stringify(judge.settingChoices(manifest, { voices: [] }, { ...manifest.settings, voice: "af_heart" }).voice)), [],
        "no published voices draw no Voice field, and the setting is not written");
    console.log("test-jarvis-setup-gate: case=voice-field passed=true");
    const serviceSource = fs.readFileSync(serviceFile, "utf8");
    verifyDictationStart(serviceSource);
    console.log("test-jarvis-setup-gate: case=dictation-start passed=true");
    for (const [label, needle, replacement] of [
        ["dictation-start-unwaited", 'if (pending === null || !waited && shell.dictation.state.phase === "unread") return;', "if (pending === null) return;"],
        ["dictation-start-locked", 'lockObservation() ? "refused: locked" : ', ""]]) {
        assert.equal(serviceSource.split(needle).length, 2, label + ": the text to replace must occur once");
        assert.throws(() => verifyDictationStart(serviceSource.replace(needle, replacement)), assert.AssertionError, label + " must turn red");
        console.log("test-jarvis-setup-gate: control=" + label + " rejected=true");
    }
    {
        const accountsSource = fs.readFileSync(accountsFile, "utf8");
        const needle = '        values.setupVoice = Gate.dictationSetup(values.setupVoice, dictationState);\n';
        assert.equal(serviceSource.split(needle).length, 2, "the configured-part publication control text occurs once");
        const copy = path.join(temp, "dictation-setup-unpublished-Service.qml");
        fs.writeFileSync(copy, serviceSource.replace(needle, ""));
        assert.throws(() => verifyDictation(load(file), fs.readFileSync(copy, "utf8"), accountsSource), assert.AssertionError,
            "control: bypassing core setup publication must omit the configured names");
        console.log("test-jarvis-setup-gate: control=dictation-setup-unpublished rejected=true");
        for (const [name, needle] of [["voxtype-row-unpublished",
            '        if (shell.status.set("voxtype", Gate.voxtypeValue(voiceProvider, missing)) !== "ok")\n            throw new Error("jarvis-accounts: status=refused");\n']]) {
            assert.equal(accountsSource.split(needle).length, 2, name + ": the control's text occurs once");
            assert.throws(() => verifyDictation(load(file), serviceSource, accountsSource.replace(needle, "")), assert.AssertionError,
                name + " must turn red");
            console.log("test-jarvis-setup-gate: control=" + name + " rejected=true");
        }
    }
    // The service publishes each row from its own facts.
    for (const [label, needle, replacement, check] of [
        ["elevenlabs-row-offers-unread", "answer: setupAnswer, voices: voiceOffers }", "answer: setupAnswer, voices: 0 }", verifyElevenLabsRow],
        ["elevenlabs-row-key-unread", "keys: accountReader.voiceKeys, account: shell.settings.voiceAccount", "keys: [], account: shell.settings.voiceAccount", verifyElevenLabsRow],
        ["voice-route-fixed", 'Gate.voiceRoute(shell.settings.voiceProvider)', 'Gate.voiceRoute("local")', verifyVoiceRoute]]) {
        assert.equal(serviceSource.split(needle).length, 2, label + ": the text to replace must occur once");
        assert.throws(() => check(load(file), serviceSource.replace(needle, replacement)), assert.AssertionError, label + " must turn red");
        console.log("test-jarvis-setup-gate: control=" + label + " rejected=true");
    }
    verifyHomeSwitch(serviceSource);
    console.log("test-jarvis-setup-gate: case=home-switch passed=true");
    {
        const needle = 'notice({ title: "Jarvis home not changed",';
        assert.equal(serviceSource.split(needle).length, 2);
        const changed = serviceSource.replace(needle, 'false && ' + needle);
        const copy = path.join(temp, "home-switch-no-notice.qml");
        fs.writeFileSync(copy, changed);
        assert.throws(() => verifyHomeSwitch(fs.readFileSync(copy, "utf8")), assert.AssertionError);
        console.log("test-jarvis-setup-gate: control=home-switch-notice rejected=true");
    }
    const accountsSource = fs.readFileSync(accountsFile, "utf8");
    const localRuntimeSource = fs.readFileSync(localRuntimeFile, "utf8");
    {
        // A failed check read as an answer keeps the text the guard reads.
        const needle = '        if (code !== 0) return Gate.checkFailure("failed", entry);';
        assert.equal(localRuntimeSource.split(needle).length, 2);
        assert.throws(() => verifyCheckedReader(load(file), localRuntimeSource.replace(needle, "        if (code > 0) code = 0;\n" + needle)),
            error => error instanceof assert.AssertionError && error.message.startsWith("a check that exits non-zero: the reader's value"),
            "a reader that reads a failed check as an answer turns red");
        console.log("test-jarvis-setup-gate: control=LocalRuntime.qml check=failed-check-read rejected=true");
    }
    for (const [label, needle] of [["voice-step-republish-dropped", "            localRuntime.republish();\n"],
        ["voice-step-unstored", "            voiceStep = values.setupVoice;\n"],
        ["session-summary-unjudged", "        values.setup = Gate.sessionSummary(values.setup, Gate.sessionStart(shell.settings.startAtBoot, sessionStart.result));\n"],
        ["session-answer-unpublished", "; onResultChanged: root.publishShellSetup()"]]) {
        assert.equal(serviceSource.split(needle).length, 2, label + ": the text to remove must occur once");
        assert.throws(() => verifyVoiceStepRepublish(load(file), serviceSource.replace(needle, "")), assert.AssertionError, label + " must turn red");
        console.log("test-jarvis-setup-gate: control=" + label + " rejected=true");
    }
    for (const [target, original, needle, replacement] of [
        ["Service.qml", serviceSource, 'values.setupModel = Gate.modelStep(values.setupModel, shell.status.values["keys"], accountReader.modelAccess);', 'values.setupModel = values.setupModel;'],
        ["Accounts.qml", accountsSource, 'modelAccess = Gate.accountAccess(value.accounts);', 'modelAccess = { kind: "absent" };']
    ]) {
        assert.equal(original.split(needle).length, 2);
        const changed = original.replace(needle, replacement);
        assert.notEqual(changed, original);
        const copy = path.join(temp, target);
        fs.writeFileSync(copy, changed);
        let failure = null;
        try { verifyModelConsumers(load(file), target === "Service.qml" ? fs.readFileSync(copy, "utf8") : serviceSource,
            target === "Accounts.qml" ? fs.readFileSync(copy, "utf8") : accountsSource); }
        catch (error) { failure = error; }
        assert.ok(failure instanceof assert.AssertionError);
        assert.equal(failure.check, "setup-model-action");
        console.log("test-jarvis-setup-gate: control=" + target + " check=setup-model-action rejected=true");
    }
    const manifestFile = path.join(path.dirname(file), "manifest.json");
    for (const [target, original, needle, replacement] of [
        ["Service.qml", serviceSource, "voiceProvider: Gate.voiceProvider(shell.settings, accountReader.voiceKeys), dictation", "voiceProvider: shell.settings.voiceProvider, dictation"],
        ["Accounts.qml", accountsSource, "voiceKeys = value.voiceAccounts;", "voiceKeys = [];"],
        ["Accounts.qml", accountsSource, "voiceKeys = undefined;", "voiceKeys = [];"],
        ["Accounts.qml", accountsSource, "Gate.voiceKey(voiceChoices, shell.settings)", "Gate.voiceKey([], shell.settings)"],
        ["Accounts.qml", accountsSource, "Gate.voiceKey(null, shell.settings)", "Gate.voiceKey([], shell.settings)"],
        ["Accounts.qml", accountsSource, "const voiceChoices = Gate.voiceKeys(keys, shell.settings);", 'const voiceChoices = keys.filter(key => key.provider === "openai").map(key => ({ value: key.value, label: key.label }));'],
        ["Service.qml", serviceSource, "Gate.cloudSpeech(provider) ? Gate.previewCost(provider)", 'Gate.cloudSpeech(provider) ? Gate.previewCost("realtime")'],
        ["Accounts.qml", accountsSource, "providers = value.providers;", "providers = {};"],
        ["Accounts.qml", accountsSource, "providers = {};", "providers = providers;"],
    ]) {
        assert.equal(original.split(needle).length, 2);
        let failure = null;
        try { verifyVoice(load(file), target === "Service.qml" ? original.replace(needle, replacement) : serviceSource,
            target === "Accounts.qml" ? original.replace(needle, replacement) : accountsSource); }
        catch (error) { failure = error; }
        assert.ok(failure instanceof assert.AssertionError);
        assert.equal(failure.check, "voice-default");
        console.log("test-jarvis-setup-gate: control=" + target + " check=voice-default rejected=true");
    }
    const voiceManifestControls = [
        ["voice-default", raw => {
            assert.equal(raw.settings.voiceProvider, "local");
            raw.settings.voiceProvider = "auto";
        }],
        ["gemini-option", raw => { raw.schema.voiceProvider.options = withoutOption(raw.schema.voiceProvider.options, "gemini"); }],
        ["elevenlabs-option", raw => { raw.schema.voiceProvider.options = withoutOption(raw.schema.voiceProvider.options, "elevenlabs"); }],
        ["key-source-link", raw => {
            assert.equal(raw.schema.voiceAccount.link.url, "https://platform.openai.com/api-keys");
            raw.schema.voiceAccount.link.url = "https://aistudio.google.com/apikey";
        }],
        ["key-description-row-reference", raw => {
            assert.equal(raw.schema.voiceAccount.description.includes(raw.status.elevenLabs.label), false);
            raw.schema.voiceAccount.description += ", as " + raw.status.elevenLabs.label + " says";
        }],
        ["key-description-sentences", raw => { raw.schema.voiceAccount.description += ". Another sentence."; }],
        ["key-settings-path", raw => {
            const info = raw.schema.voiceAccount.info;
            const reference = "(page:vgs.jarvis/Details)";
            assert.equal(info.split(reference).length, 2);
            raw.schema.voiceAccount.info = info.replace(reference, "(page:vgs.jarvis/Setup)");
        }],
        ["key-help-omitted", raw => {
            assert.equal(typeof raw.schema.voiceAccount.info, "string");
            delete raw.schema.voiceAccount.info;
        }],
        ["elevenlabs-help-omitted", raw => {
            assert.equal(typeof raw.status.elevenLabs.info, "string");
            delete raw.status.elevenLabs.info;
        }]
    ];
    for (const [label, change] of voiceManifestControls) {
        const readFile = fs.readFileSync;
        const copy = path.join(temp, label + "-manifest.json");
        fs.writeFileSync(copy, changedManifest(readFile(manifestFile, "utf8"), change));
        let failure = null;
        fs.readFileSync = (name, ...rest) => readFile(name === manifestFile ? copy : name, ...rest);
        try { verifyVoice(load(file), serviceSource, accountsSource); }
        catch (error) { failure = error; }
        finally { fs.readFileSync = readFile; }
        assert.ok(failure instanceof assert.AssertionError, label + ": the manifest control must fail an assertion");
        assert.equal(failure.check, "voice-default", label + ": the intended voice check rejects the change");
        manifestControlCount++;
        console.log("test-jarvis-setup-gate: control=manifest.json case=" + label + " check=voice-default rejected=true");
    }
    // The model and effort choice and its list read: one rule at a time.
    const providersSource = fs.readFileSync(providersFile, "utf8");
    const CHOICE_CONTROLS = [
        ["AccountProviders.js", 'var PREFERRED_MODELS = ["claude-fable-5-1", "claude-opus-5-5"];', 'var PREFERRED_MODELS = ["claude-opus-5-5", "claude-fable-5-1"];'],
        ["AccountProviders.js", 'var PREFERRED_MODELS = ["claude-fable-5-1", "claude-opus-5-5"];', 'var PREFERRED_MODELS = ["claude-fable-5-1"];'],
        ["AccountProviders.js", 'var PREFERRED_EFFORT = "high";', 'var PREFERRED_EFFORT = "medium";'],
        ["AccountProviders.js", '.replace(/\\[[^\\]]*\\]$/, "")', ""],
        ["AccountProviders.js", '.replace(/\\./g, "-")', ""],
        ["AccountProviders.js", "var first = preferred && offer.efforts.indexOf(PREFERRED_EFFORT) !== -1 ? PREFERRED_EFFORT", "var first = preferred ? PREFERRED_EFFORT"],
        ["AccountProviders.js", ": offer.efforts.indexOf(offer.effort) !== -1 ? offer.effort : OWN_EFFORT;", ": OWN_EFFORT;"],
        ["AccountProviders.js", "var ordered = preferred === null ? offers\n        : [preferred].concat(offers.filter(function (offer) { return offer !== preferred; }));", "var ordered = offers;"],
        ["AccountProviders.js", 'var chosen = ordered.filter(function (offer) { return settings.model === "" || offer.value === settings.model; })[0];', "var chosen = ordered[0];"],
        ["AccountProviders.js", "if (chosen === undefined) return { model: settings.model, effort: settings.effort, models: models, efforts: one(settings.effort) };", "if (chosen === undefined) chosen = ordered[0];"],
        ["AccountProviders.js", "if (chosen === undefined) return { model: settings.model, effort: settings.effort, models: models, efforts: one(settings.effort) };",
            "if (chosen === undefined) return { model: settings.model, effort: settings.effort, models: models, efforts: [] };"],
        ["AccountProviders.js", "var effort = efforts.some(function (level) { return level.value === settings.effort; }) ? settings.effort", 'var effort = settings.effort !== "" ? settings.effort'],
        ["AccountProviders.js", 'effort: effort === OWN_EFFORT ? "" : effort,', "effort: effort,"],
        ["AccountProviders.js", "PREFERRED_MODELS.some(function (id) { return namesModel(chosen.value, id); })", "chosen === ordered[0]"],
        ["AccountProviders.js", 'return level === OWN_EFFORT ? "Model default"', 'return level === OWN_EFFORT ? "default"'],
        ["AccountProviders.js", "Object.prototype.hasOwnProperty.call(EFFORT_LABELS, level) ? EFFORT_LABELS[level]", "false ? EFFORT_LABELS[level]"],
        ["AccountProviders.js", 'var failed = listed.kind === "failed";', 'var failed = listed.kind !== "none";'],
        ["AccountProviders.js", 'var mark = failed ? " (list not read)" : "";', 'var mark = "";'],
        ["AccountProviders.js", ': failed && !local ? [{ label: "App default" + mark, value: OWN_MODEL }] : [],', ': true ? [{ label: "App default" + mark, value: OWN_MODEL }] : [],'],
        ["AccountProviders.js", ': failed && !local ? [{ label: "App default" + mark, value: OWN_MODEL }] : [],', ": [],"],
        ["AccountProviders.js", "var runs = failed ? unlistedChoice(settings, provider) : settings;", "var runs = settings;"],
        ["AccountProviders.js", "var runs = failed ? unlistedChoice(settings, provider) : settings;", "var runs = unlistedChoice(settings, provider);"],
        ["AccountProviders.js", 'return effort === "" ? [] : [{ label: effortLabel(effort), value: effort }];', "return [{ label: effort, value: effort }];"],
        ["AccountProviders.js", "if (offers.length === 0) return { model: settings.model, effort: settings.effort, models: [], efforts: [] };", ""],
        ["AccountProviders.js", "if (offers.length === 0) return { model: settings.model, effort: settings.effort, models: [], efforts: [] };", 'if (offers.length === 0) return { model: "", effort: "", models: [], efforts: [] };'],
        ["AccountProviders.js", 'var PREFERRED_PROGRAM = "claude";', 'var PREFERRED_PROGRAM = "codex";'],
        ["AccountProviders.js", 'var model = settings.model !== "" ? "" :', "var model ="],
        ["AccountProviders.js", ": listedKeyModel(provider);", ': "";'],
        ["AccountProviders.js", "effort: settings.effort || PREFERRED_EFFORT };", "effort: PREFERRED_EFFORT };"],
        ["AccountProviders.js", "effort: settings.effort || PREFERRED_EFFORT };", "effort: settings.effort };"],
        ["Service.qml", "Providers.unlistedChoice(shell.settings, accountReader.providers[shell.settings.brain])),", "{}),"],
        ["Service.qml", "        delete settings.localTier;\n", ""],
        ["Service.qml", "Providers.unlistedChoice(shell.settings, accountReader.providers[shell.settings.brain])),", 'Providers.unlistedChoice(shell.settings, "claude")),'],
        ["Accounts.qml", "shell.settings, list, providers[brain])", "shell.settings, list)"],
        ["Accounts.qml", 'readonly property string wanted: shell !== null && shell.status.viewed ? brain : ""', "readonly property string wanted: brain"],
        ["Accounts.qml", "const changed = seenBrain !== null && seenBrain !== brain && shell.status.viewed;", "const changed = seenBrain !== null && seenBrain !== brain;"],
        ["Accounts.qml", "const changed = seenBrain !== null && seenBrain !== brain && shell.status.viewed;", "const changed = seenBrain !== brain && shell.status.viewed;"],
        ["Accounts.qml", "const changed = seenBrain !== null && seenBrain !== brain && shell.status.viewed;", "const changed = false;"],
        ["Accounts.qml", "        seenBrain = brain;\n", ""],
        ["Accounts.qml", "        Qt.callLater(save);\n", ""],
        ["Accounts.qml", "        Qt.callLater(save);\n", "        save();\n"],
        ["Accounts.qml", 'readonly property var list: listed.brain === brain ? listed : ({ kind: "none" })', "readonly property var list: listed"],
        ["Accounts.qml", 'list.kind === "read" ? choice : shell.settings;', "shell.settings;"],
        ["Accounts.qml", "if (wanted[key] !== shell.settings[key] && shell.configure.set", "if (shell.configure.set"],
        ["Accounts.qml", "            lister.dropped = true;\n", ""],
        ["Accounts.qml", "            lister.dropped = true;\n", "            lister.dropped = true;\n            lister.running = false;\n"],
        ["Accounts.qml", "                dropped = false;\n                root.readList();", "                dropped = false;"],
        ["Accounts.qml", 'listed = { brain: wanted, kind: wanted === "" ? "none" : "reading" };\n        if (wanted === "") return;', 'listed = { brain: wanted, kind: "reading" };'],
        ["Accounts.qml", '        lister.output = "";\n', ""],
        ["Accounts.qml", 'catch (error) { answer = { kind: "failed", reason: "helper" }; }', 'catch (error) { answer = { kind: "none" }; }'],
        ["Accounts.qml", 'if (answer.kind === "failed") console.warn("jarvis-accounts: models=" + answer.reason);', ""],
        ["Accounts.qml", "listed = Object.assign({ brain: listed.brain }, answer);", "listed = answer;"],
        ["Accounts.qml", 'shell.status.set("efforts", choice.efforts) !== "ok"', 'shell.status.set("efforts", []) !== "ok"'],
    ];
    for (const [index, [target, needle, replacement]] of CHOICE_CONTROLS.entries()) {
        const original = { "AccountProviders.js": providersSource, "Accounts.qml": accountsSource, "Service.qml": serviceSource }[target];
        assert.equal(original.split(needle).length, 2, "the text to replace occurs once: " + needle);
        const changed = original.replace(needle, () => replacement);
        // One file a control: require caches a module by its path.
        const copy = path.join(temp, "choice-" + index + "-" + target);
        fs.writeFileSync(copy, changed);
        let failure = null;
        try {
            const providers = target === "AccountProviders.js" ? require(copy) : require(providersFile);
            verifyModelChoice(providers);
            verifyUnlisted(load(file), providers, target === "Service.qml" ? changed : serviceSource);
            verifyListRead(providers, target === "Accounts.qml" ? changed : accountsSource);
        } catch (error) { failure = error; }
        assert.ok(failure instanceof assert.AssertionError, "the suite passed, or failed on no assertion, without: " + needle + (failure === null ? "" : ": " + failure));
        assert.equal(failure.check, "model-choice");
        console.log("test-jarvis-setup-gate: control=" + target + " check=model-choice rejected=true");
    }
    for (const [label, change] of [
        ["empty-effort-field", raw => {
            assert.equal(raw.schema.effort.hideEmpty, true);
            delete raw.schema.effort.hideEmpty;
        }],
        ["model-placeholder", raw => {
            assert.equal(typeof raw.schema.model.placeholder, "string");
            delete raw.schema.model.placeholder;
        }]
    ]) {
        const readFile = fs.readFileSync;
        const copy = path.join(temp, label + "-manifest.json");
        fs.writeFileSync(copy, changedManifest(readFile(manifestFile, "utf8"), change));
        let failure = null;
        fs.readFileSync = (name, ...rest) => readFile(name === manifestFile ? copy : name, ...rest);
        try {
            const providers = require(providersFile);
            verifyModelChoice(providers);
            verifyUnlisted(load(file), providers, serviceSource);
            verifyListRead(providers, accountsSource);
        } catch (error) { failure = error; }
        finally { fs.readFileSync = readFile; }
        assert.ok(failure instanceof assert.AssertionError, label + ": the manifest control must fail an assertion");
        assert.equal(failure.check, "model-choice", label + ": the intended model check rejects the change");
        manifestControlCount++;
        console.log("test-jarvis-setup-gate: control=manifest.json case=" + label + " check=model-choice rejected=true");
    }
    // The Agent fleet row's read-only probes: no home, a home without
    // the canonical reader, then the same home with it. The control removes
    // tool discovery. Installer release is covered by the daemon suite.
    const backendDir = path.join(path.dirname(file), "backend");
    const fleetReader = helperFile => {
        const scratch = fs.mkdtempSync(path.join(temp, "fleet-home-"));
        const run = (verb, setting) => cp.spawnSync(process.execPath, [helperFile, "--tree", path.join(__dirname, ".."), verb, setting],
            { env: { PATH: process.env.PATH, HOME: scratch }, encoding: "utf8" });
        const status = setting => {
            const result = run("status", setting);
            assert.equal(result.status, 0, result.stderr);
            const value = JSON.parse(result.stdout);
            return value.hidden === true ? "hidden" : value.action === true ? "offered" : value.tone === "ok" && value.action === false ? "done" : "other";
        };
        const answer = (verb, setting) => {
            const result = run(verb, setting);
            return [result.status, result.status === 0 ? result.stdout : result.stderr];
        };
        const folder = path.join(scratch, "Jarvis");
        const tool = path.join(folder, ".agents/skills/mailbox/scripts/lane-mail");
        for (const setting of ["", "Jarvis"]) {
            assert.equal(status(setting), "hidden", JSON.stringify(setting) + ": no home, no row");
            assert.deepEqual(answer("folder", setting), [1, "jarvis: fleet-setup=home-unchosen\n"]);
        }
        assert.equal(status("~/Jarvis"), "offered", "a home without the mail tool offers its setup");
        assert.deepEqual(answer("folder", "~/Jarvis"), [0, folder + "\n"]);
        assert.deepEqual(answer("tool", "~/Jarvis"), [1, "jarvis: fleet-setup=tool-absent\n"]);
        fs.mkdirSync(path.dirname(tool), { recursive: true });
        fs.writeFileSync(tool, "#!/bin/sh\n", { mode: 0o755 });
        assert.equal(status("~/Jarvis"), "offered", "a home that is no repository of its own still needs its setup");
        fs.mkdirSync(path.join(folder, ".git"));
        assert.equal(status("~/Jarvis"), "done", "a home with the mail tool needs no setup");
        assert.deepEqual(answer("tool", "~/Jarvis"), [0, tool + "\n"]);
        for (const verb of ["bogus", "release"])
            assert.deepEqual(answer(verb, "~/Jarvis"), [2, "jarvis: fleet-setup=arguments\n"]);
        assert.equal(fs.existsSync(path.join(folder, ".vgs-mailbox-cutover.json")), false, "probes consume no automatic attempt");
    };
    fleetReader(path.join(backendDir, "fleet-setup.js"));
    {
        const plugin = path.join(temp, "fleet-plugin");
        fs.mkdirSync(path.join(plugin, "backend"), { recursive: true });
        for (const name of ["Core.js", "Home.js", "Tools.js"]) fs.copyFileSync(path.join(backendDir, name), path.join(plugin, "backend", name));
        fs.copyFileSync(file, path.join(plugin, "SetupGate.js"));
        const reader = fs.readFileSync(path.join(backendDir, "fleet-setup.js"), "utf8");
        const needle = "const tool = folder === null ? null : Home.mailTool(folder);";
        assert.equal(reader.split(needle).length, 2, "the fleet reader control's text occurs once");
        fs.writeFileSync(path.join(plugin, "backend/fleet-setup.js"), reader.replace(needle, "const tool = null;"));
        assert.throws(() => fleetReader(path.join(plugin, "backend/fleet-setup.js")), assert.AssertionError, "a reader that finds no tool turns red");
        console.log("test-jarvis-setup-gate: control=fleet-reader-tool rejected=true");
    }
    {
        // The no-home row as main shipped it before VGS-1520: Cannot start in
        // the warning tone beside a Ready summary that names no session.
        let shipped = source;
        for (const [needle, replacement] of [['var SESSION_CHOICES = ["no-account", "not-app", "no-home"];', "var SESSION_CHOICES = [];"],
            ['    if (setup.tone !== "ok" || !Object.prototype.hasOwnProperty.call(SESSION_FAULTS, session.tone)) return setup;', "    return setup;"]]) {
            assert.equal(shipped.split(needle).length, 2, "the no-home control's text occurs once");
            shipped = shipped.replace(needle, () => replacement);
        }
        const copy = path.join(temp, "SetupGate.js");
        fs.writeFileSync(copy, shipped);
        assert.throws(() => verifyOneSessionJudgement(load(copy), [{ kind: "blocked", block: "no-home" }]),
            error => error instanceof assert.AssertionError && error.message.includes('"no-home"') && error.message.includes("one judgement of the session"),
            "the shipped no-home row beside a Ready summary turns red");
        console.log("test-jarvis-setup-gate: control=session-no-home-shipped rejected=true");
    }
    for (const [label, needle, replacement, assertion] of CONTROLS) {
        assert.equal(source.split(needle).length, 2, `control "${label}": the text to replace must occur once`);
        const changed = source.replace(needle, () => replacement);
        assert.notEqual(changed, source, `control "${label}": the copy changed`);
        const copy = path.join(temp, "SetupGate.js");
        fs.writeFileSync(copy, changed);
        let failure = null;
        try {
            verify(load(copy));
        } catch (e) {
            failure = e;
        }
        assert.ok(failure instanceof assert.AssertionError, `control "${label}": the suite passed on a copy without that rule` +
            (failure === null ? "" : ", or failed on something other than an assertion: " + failure));
        if (assertion !== undefined) assert.equal(failure.message.includes(assertion), true,
            label + ": the intended assertion fails; expected=" + JSON.stringify(assertion) + " actual=" + JSON.stringify(failure.message));
    }
} finally {
    fs.rmSync(temp, { recursive: true, force: true });
}
console.log(`test-jarvis-setup-gate: ok cases=${SETUP.length + REQUIREMENT.length + READINESS.length + MODEL.length + VOICE.length + VOICE_KEY.length + START_CAUSES.length + CHOICE.length + UNLISTED.length + FLEET.length + DICTATION.length
    + LOCAL_VOICE_TASK.voice.length * LOCAL_VOICE_TASK.local.length * LOCAL_VOICE_TASK.providers.length} controls=${CONTROLS.length + 12 + 59 + manifestControlCount - 10 + 2}`);
// The fleet setup terminal opens from the Agent fleet row alone: in
// MANIFEST, a judged manifest, the launcher lists no fleet TUI and the
// Details tab draws none while the row is hidden, and the offered row
// draws its button, whose press the core turns into that terminal, kendex
// missing or not: the press asks for it first.
function verifySetupButtons(gate, manifest) {
    for (const [label, home, tool, shown, offered] of FLEET)
        for (const missing of [[], ["kendex"]]) {
            const tuis = judge.listedTuis(manifest);
            assert.equal(tuis.some(tui => tui.name === "setup-fleet"), false, label + ": the launcher lists no fleet setup");
            const value = plain(gate.fleetStep(home, tool));
            const status = judge.statusRows(manifest, { setupFleet: value });
            const steps = settingsRows(settings.setupSections(tuis, status));
            assert.equal(steps.some(item => item.key === "setupFleet"), false, label + ": optional fleet setup stays off Setup");
            const row = detailActionRows(status).find(item => item.key === "setupFleet");
            assert.equal(row !== undefined, shown, label + ": the fleet row stays visible");
            assert.equal(row !== undefined && row.button !== null, offered,
                label + ": only the shown Details fleet row draws its action, missing " + missing);
            if (offered)
                assert.deepEqual(plain(judge.statusActionRequest(manifest, "vgs.jarvis", true, { setupFleet: value }, "setupFleet")), { ok: true, kind: "tui", name: "setup-fleet" },
                    label + ": the row's press opens the fleet setup");
        }
}
// Local voice, browser and input screens offered by more than one page row.
function drawnTwice(rows) {
    const screens = ["setup-local", "setup-browser", "setup-input"];
    const names = rows.filter(item => item.button !== null && screens.includes(item.button.name)).map(item => String(item.button.name));
    return names.filter((name, at) => names.indexOf(name) !== at);
}
function verifyScreensOnce(gate) {
    const tuis = judge.listedTuis(manifest);
    for (const [label, provider, causes, local, browser, input, offering, localTone] of ONCE) {
        const values = plain(gate.readiness({ kind: "answered", causes }));
        values.setupVoice = gate.voiceCheck(values.setupVoice, null);
        values.setupModel = gate.modelStep(values.setupModel, [{ value: "absent" }], { kind: "absent" });
        Object.assign(values, plain({ localRuntime: gate.localVoiceStep(local, provider, values.setupVoice), browser: gate.optionalStep(browser), input: gate.optionalStep(input),
            keyStore: { tone: "ok", text: "1 key stored", action: true }, voiceKey: { tone: "info", text: "No key stored", action: true } }));
        const status = judge.statusRows(manifest, values);
        const sections = Array.from(settings.setupSections(tuis, status));
        const required = settingsRows(sections);
        const rows = required.concat(detailActionRows(status));
        assert.deepEqual(drawnTwice(rows), [], label + ": each screen once");
        assert.equal(required.some(item => ["localRuntime", "browser", "input"].includes(item.key)), false,
            label + ": optional features stay off Setup");
        assert.deepEqual(Object.fromEntries(Object.keys(offering).map(name => [name, rows.filter(item => item.button !== null && item.button.name === name).map(item => String(item.key))])),
            offering, label + ": the rows that offer the local voice, browser and input screens");
        const tones = Object.fromEntries(rows.filter(item => ["localRuntime", "browser", "input"].includes(item.key)).map(item => [item.key, item.entry.tone]));
        const open = causes.length > 0;
        assert.deepEqual(tones, { localRuntime: localTone, browser: open ? "info" : "success", input: open ? "info" : "success" },
            label + ": the browser and input read optional, Local voice required under Local while it holds its own setup");
    }
    // Its control: the Voice step's and the Local voice row's setup both
    // offered, as the two entries published before VGS-1486.
    const both = plain(gate.readiness({ kind: "answered", causes: ["speech=local-not-set-up"] }));
    both.setupVoice = gate.voiceCheck(both.setupVoice, null);
    both.localRuntime = LOCAL_ABSENT;
    const bothStatus = judge.statusRows(manifest, both);
    assert.deepEqual(drawnTwice(settingsRows(settings.setupSections(tuis, bothStatus)).concat(detailActionRows(bothStatus))), ["setup-local"],
        "two rows that offer Set up local voice turn the check red");
}
// Across required Voice setup and optional Local voice maintenance, the
// shared judge projects each offered setup action once. Failed checks
// retain their recovery guidance on the Settings state.
function verifyOneLocalVoiceTask(gate, step) {
    const tuis = judge.listedTuis(manifest);
    for (const [voiceLabel, answer] of LOCAL_VOICE_TASK.voice)
        for (const [localLabel, reading] of LOCAL_VOICE_TASK.local)
            for (const provider of LOCAL_VOICE_TASK.providers) {
                const label = voiceLabel + " / " + localLabel + " / " + provider;
                const values = plain(gate.readiness(answer));
                values.setupVoice = plain(gate.voiceCheck(values.setupVoice, null));
                const local = typeof reading === "string" ? gate.checkFailure(reading, manifest.status.localRuntime) : reading;
                values.localRuntime = plain(step(local, provider, values.setupVoice));
                assert.equal(judge.statusWrite(manifest, {}, "localRuntime", values.localRuntime).ok, true, label + ": the manifest judge accepts the Local voice row");
                const status = judge.statusRows(manifest, values);
                const required = settingsRows(settings.setupSections(tuis, status));
                const attached = detailActionRows(status);
                assert.equal(required.some(item => item.key === "localRuntime"), false, label + ": Local voice maintenance stays off Setup");
                const rows = required.concat(attached);
                const offering = rows.filter(item => item.button !== null && item.button.name === "setup-local").map(item => String(item.key));
                assert.equal(offering.length <= 1, true, label + ": one action for local voice setup, not " + JSON.stringify(offering));
                const expected = values.setupVoice.action === "setup" || values.localRuntime.action === true;
                assert.equal(offering.length, expected ? 1 : 0, label + ": the published action draws in its declared place");
                if (typeof reading === "string") assert.equal(typeof values.localRuntime.hint, "string", label + ": the failed check says why");
            }
}
// A failed, unreadable or timed-out check of each setup reader that shares
// LocalRuntime.qml: each published value fits its entry, and a failed or
// unreadable one names the action that sets it up again, read from the
// manifest by its own path: [status key, the path of its setup action's
// label, the reader's shape]. A timed-out one is no open step, offers no
// setup and draws no keyed cause, so the Ready summary a probe timeout
// keeps stands over no open step.
function verifyCheckFailures(gate) {
    const raw = JSON.parse(fs.readFileSync(path.join(path.dirname(file), "manifest.json"), "utf8"));
    const voiceDone = gate.voiceCheck(gate.DONE, null);
    for (const [key, labelPath, shape] of [
        ["localRuntime", ["action", "label"], value => gate.localVoiceStep(value, "local", voiceDone)],
        ["browser", ["action", "label"], value => gate.optionalStep(value)],
        ["setupFleet", ["action", "label"], value => value],
        ["clonedVoiceSetup", ["actions", "setup", "label"], value => gate.clonedVoiceStep(value, "local")]]) {
        const label = labelPath.reduce((at, name) => at[name], raw.status[key]);
        for (const kind of ["failed", "unreadable", "timeout"]) {
            const value = plain(shape(gate.setupValue(gate.checkFailure(kind, manifest.status[key]), [], [])));
            assert.equal(judge.statusWrite(manifest, {}, key, value).ok, true, key + " " + kind + ": the manifest judge accepts the value");
            assert.equal(typeof value.hint, "string", key + " " + kind + ": the row says why");
            if (kind !== "timeout") assert.equal(value.hint.includes(label), true, key + " " + kind + ": the hint names " + label);
            const row = judge.statusRows(manifest, { [key]: value }).find(entry => entry.key === key);
            assert.equal(row.action.offered, kind !== "timeout", key + " " + kind + ": the row offers its setup only while setup mends it");
            if (kind !== "timeout") continue;
            assert.equal(value.tone, "info", key + " timeout: the check remains informational");
            assert.equal(settings.declaresStep(row), false, key + " timeout: the optional state stays off Setup");
            const completed = { ...plain(gate.readiness({ kind: "answered", causes: [] })), [key]: value };
            assert.equal(settings.setupNeeds(judge.statusRows(manifest, completed), [], true).open, false,
                key + " timeout: a completed required setup keeps its warning clear");
            const unchecked = { ...plain(gate.readiness({ kind: "checking" })), [key]: value };
            assert.equal(settings.setupNeeds(judge.statusRows(manifest, unchecked), [], true).open, true,
                key + " timeout: required setup still warns before its checks answer");
            assert.deepEqual(keyedCauses(value, ["text", "hint", "lines"]), [], key + " timeout: the row draws no keyed cause");
        }
    }
    // Jarvis takes a request while its setup check has timed out, so the
    // summary is Ready, and neither its caution nor the Local voice row
    // asks for a restart beside it (VGS-1520's one judgement).
    const probeTimeout = plain(gate.readiness({ kind: "answered", causes: ["setup=probe-timeout"] })).setup;
    const timedOutRow = plain(gate.localVoiceStep(gate.checkFailure("timeout", manifest.status.localRuntime), "local", voiceDone));
    assert.deepEqual([probeTimeout.tone, probeTimeout.text], ["ok", "Ready"], "probe timeout: the summary is Ready");
    assert.equal(timedOutRow.hint.includes(gate.START_RESTART), false, "probe timeout: the Local voice row asks for no restart beside Ready");
    assert.equal(probeTimeout.hint.includes(gate.START_RESTART), false, "probe timeout: the caution asks for no restart beside Ready");
    assert.throws(() => gate.checkFailure("lost", manifest.status.localRuntime), /^Error: jarvis-setup: check-failure=lost unexpected/);
}
// Every cause the Setup table knows states one readiness on the bar and in
// the Setup status. Session's gate follows the daemon alone (jarvisd.js
// configured): up while its causes are none or only speech=local-loading,
// else down unconfigured. The shell's own cause, LocalRuntime.qml's
// setupCause, never reaches the daemon.
// Each DICTATION row through the shipped service's setup publication: the
// cause the daemon publishes is the summary's line, the Voice step names
// Set up dictation only where it is offered, and its press opens the core's
// dictation setup. The voxtype row offers its install while it is missing.
function verifyDictation(gate, serviceSource, accountsSource) {
    const publishSetup = serviceSource.match(/^    function publishSetup\(answer\) \{\n[\s\S]*?^    \}/m);
    const publishRequirements = accountsSource.match(/^    function publishRequirements\(\) \{\n[\s\S]*?^    \}/m);
    assert.ok(publishSetup && publishRequirements);
    for (const [label, voice, state, missing, cause, expect, offered, names] of DICTATION) {
        assert.equal(gate.dictationCause(voice, state), cause, label + ": the cause");
        const values = {};
        const shell = { settings: { voiceAccount: "" }, requirements: { missing }, status: { values, set: (key, value) => {
            assert.equal(judge.statusWrite(manifest, values, key, value).ok, true, label + ": accepted status " + key);
            values[key] = value;
            return "ok";
        } } };
        vm.runInNewContext("(" + publishSetup[0] + ")", { Gate: gate, shell, dictationState: state === null ? null : Object.assign({ setup: null }, state), accountReader: { modelAccess: { kind: "checking" } },
            localRuntime: { setupCause: "", republish: () => {} }, voiceStep: null, sessionState: null, sessionStart: { result: null }, setupAnswer: { kind: "checking" } })({ kind: "answered", causes: cause === "" ? [] : [cause] });
        const voice_ = plain(values.setupVoice);
        if (expect === "withheld")
            assert.deepEqual([voice_.tone, voice_.action, "hint" in voice_], ["warning", "dictation", false], label + ": the Voice step");
        else if (expect === "named") {
            assert.deepEqual([voice_.tone, voice_.action], ["warning", "dictation"], label + ": the Voice step retains setup");
            for (const name of ["moonshine", "base"])
                assert.equal(voice_.hint.includes(name), names.includes(name), label + ": the holder names " + name + " only when missing");
        }
        else assert.deepEqual(voice_, plain({ entry: gate.DICTATION[cause], loading: gate.noAction(gate.LOADING), done: gate.noAction(gate.DONE) }[expect]), label + ": the Voice step");
        assert.equal(values.setup.lines, undefined, label + ": the summary draws no cause line");
        const row = judge.statusRows(manifest, values).find(item => item.key === "setupVoice");
        assert.equal(row.action.offered && row.action.label === "Set up dictation", offered, label + ": Set up dictation");
        if (offered)
            assert.deepEqual(plain(judge.statusActionRequest(manifest, "vgs.jarvis", true, values, "setupVoice")),
                { ok: true, kind: "core", name: "dictation-setup" }, label + ": the press opens the core's setup");
        // The voxtype row, the account reader's, shows for the local voice,
        // with no step: the page's Requirements section installs it.
        vm.runInNewContext("(function() { with(root) { return (" + publishRequirements[0] + ").call(root); } })()",
            { root: { shell, missing, voiceProvider: voice }, Gate: gate });
        const voxtype = judge.statusRows(manifest, values).find(item => item.key === "voxtype");
        assert.deepEqual(voxtype === undefined ? "hidden" : [voxtype.action, voxtype.tone],
            !["local", "elevenlabs"].includes(voice) ? "hidden" : [null, missing.includes("voxtype") ? "warning" : "success"], label + ": the voxtype row");
        assert.equal(gate.dictationRefusal(state ?? { daemon: "absent", device: "" }), cause === "speech=dictation-device" ? "refused: dictation=device" : "",
            label + ": the start the service refuses itself");
    }
}

// The service's dictation start against a stand-in of the core that, as
// DictationModel.start does, refuses a start while its read after the last
// recording's command runs (phase `unread`): a start that follows a cancel
// at once waits for the read and is taken, a read that outlasts the wait's
// bound answers the core's refusal, a second start answers the first, and a
// lock answers a waiting start.
function verifyDictationStart(serviceSource) {
    const pick = name => {
        const found = serviceSource.match(new RegExp("^    function " + name + "\\([^)]*\\) \\{\\n[\\s\\S]*?^    \\}", "m"));
        assert.ok(found, name);
        return found[0];
    };
    const source = pick("queueStart") + "\n" + pick("startDictation");
    const world = () => {
        const core = { phase: "unread", starts: 0 };
        const replies = [];
        const root = { pendingStart: null, childSerial: 1, lifetime: { kind: "ready" }, child: { running: true }, locked: false,
            shell: { dictation: { get state() { return { daemon: "ready", phase: core.phase, holder: "", device: "default" }; },
                start: mode => { core.starts++; assert.equal(mode, "text"); return core.phase === "unread" ? "refused: dictation=engine-busy state=unread" : "ok"; } } },
            startWait: { running: false, restart() { this.running = true; }, stop() { this.running = false; } },
            lockObservation: () => root.locked,
            reply: (message, result) => replies.push([message.id, result.answer]) };
        vm.runInNewContext("(function() { with(root) { " + source + "\n root.queueStart = queueStart; root.startDictation = startDictation; } })()",
            { root, Gate: load(file) });
        return { core, replies, root };
    };
    // A cancel followed at once by a start: the start waits for the read.
    let w = world();
    w.root.queueStart({ id: 1 });
    assert.deepEqual([w.replies, w.core.starts, w.root.startWait.running], [[], 0, true], "the start waits for the core's read");
    w.core.phase = "idle";
    w.root.startDictation(false);
    assert.deepEqual([w.replies, w.core.starts, w.root.startWait.running], [[[1, "ok"]], 1, false], "the read's end takes the start");
    // The bound passes while the core still reads: its refusal is answered.
    w = world();
    w.root.queueStart({ id: 2 });
    w.root.startDictation(true);
    assert.deepEqual(w.replies, [[2, "refused: dictation=engine-busy state=unread"]], "a read past the bound answers the refusal");
    // A start with no read pending is taken at once; a second start answers the first.
    w = world();
    w.core.phase = "idle";
    w.root.queueStart({ id: 3 });
    assert.deepEqual(w.replies, [[3, "ok"]], "a start with no read pending is taken at once");
    w.core.phase = "unread";
    w.root.queueStart({ id: 4 });
    w.root.queueStart({ id: 5 });
    assert.deepEqual(w.replies.slice(1), [[4, "refused: dictation=engine-busy state=unread"]], "a second start answers the first");
    // A lock answers the waiting start and starts nothing.
    w.root.locked = true;
    w.root.startDictation(true);
    assert.deepEqual(w.replies.slice(2), [[5, "refused: locked"]], "a lock starts no recording");
}

function verifyOneReadiness(gate) {
    const shellCause = /setupCause: timedOut \? "([^"]+)"/.exec(fs.readFileSync(localRuntimeFile, "utf8"))[1];
    const daemonCauses = [...Object.keys(gate.TODO), ...Object.keys(gate.HOME_TODO), ...Object.keys(gate.MEMORY),
        ...Object.keys(gate.DICTATION), "speech=local-loading", "speech=dictation-starting", "speech=elevenlabs-voices-reading"];
    assert.equal(daemonCauses.includes(shellCause), false, "the shell's cause is no daemon cause");
    const sets = [[], [shellCause], ...daemonCauses.map(cause => [cause]), ...daemonCauses.map(cause => [shellCause, cause])];
    const keys = { talk: "Super+Right Alt", mute: "Super+Shift+Right Alt", stop: "Super+Alt+Period", confirm: "Super+Alt+Y" };
    for (const causes of sets) {
        const status = plain(gate.readiness({ kind: "answered", causes }));
        const configured = causes.every(cause => cause === shellCause || cause === "speech=local-loading");
        const state = Object.assign(plain(session.initial()), { gate: configured ? { kind: "up" } : { kind: "down", reason: "unconfigured" } });
        assert.equal(session.validate(state), true, causes.join(",") + ": a Session record");
        const bar = widget.view(Object.assign({ daemon: { tone: "info", text: "Ready" }, audio: { tone: "ok", text: "Devices" },
            detail: { phase: session.phaseOf(state), seq: 1, state } }, status), keys, "hold");
        assert.equal(bar.state === "ready", status.setup.tone === "ok", causes.join(",") + ": the bar and the Setup status state one readiness");
        if (causes.includes(shellCause) && bar.state === "ready")
            assert.equal(bar.tooltipDetails.includes(String(status.setup.hint).replace(/\.?$/, ".")), true, causes.join(",") + ": the bar shows the caution as a sentence");
    }
}

// The class check: every text a user reads after a READINESS case or a
// failed start (the bar tooltip, the desktop notices and the Setup values)
// words its state; the service log keeps the keyed cause.
function verifyWordedText(gate) {
    const keys = { talk: "Super+Right Alt", mute: "Super+Shift+Right Alt", stop: "Super+Alt+Period", confirm: "Super+Alt+Y" };
    const state = Object.assign(plain(session.initial()), { gate: { kind: "down", reason: "unconfigured" } });
    const up = { daemon: { tone: "info", text: "Jarvis is ready; microphone is off" }, audio: { tone: "ok", text: "Device list ready" },
        detail: { phase: session.phaseOf(state), seq: 1, state } };
    for (const [label, answer] of READINESS) {
        const status = plain(gate.readiness(answer));
        const bar = widget.view(Object.assign({}, up, status), keys, "hold");
        assert.deepEqual(keyedCauses(bar, ["tooltip", "tooltipDetails"]), [], label + ": the bar tooltip draws no keyed cause");
    }
    const causes = START_CAUSES.map(([label, cause]) => [label, cause]).concat([["keyed stderr", "node: heap=exhausted"]]);
    for (const [label, cause] of causes) {
        for (const retrying of [true, false]) {
            const daemon = plain(gate.startStatus(cause, retrying));
            assert.deepEqual(daemon.lines, [gate.startCause(cause).lines[0]], label + ": the Daemon row keeps the cause");
            assert.equal(judge.statusWrite(manifest, {}, "daemon", daemon).ok, true, label + ": the daemon value fits its entry");
            const setup = plain(gate.readiness(retrying ? { kind: "problem", cause, action: gate.RETRYING_START } : { kind: "problem", cause }));
            const bar = widget.view(Object.assign({ daemon, detail: null }, setup), keys, "hold");
            assert.equal(bar.state, "problem", label + ": the bar reads a problem");
            assert.deepEqual(keyedCauses(bar, ["tooltip", "tooltipDetails"]), [], label + " retrying=" + retrying + ": the bar tooltip draws no keyed cause");
        }
        for (const [name, notice] of [["stopped", gate.stoppedNotice(cause)], ["mute refused", gate.muteRefusedNotice(cause)]]) {
            assert.deepEqual(keyedCauses(notice, ["title", "message"]), [], label + ": the " + name + " notice draws no keyed cause");
            assert.equal(notice.message.endsWith("."), true, label + ": the " + name + " notice's message ends as a sentence");
        }
    }
}

// Every Settings path a gate text names has one form: the page, Jarvis's
// own or the Voice plugin's, then for Jarvis's the field or group. The
// voices hint names Jarvis's Voice field, never the Voice plugin's page.
function verifyPathForm(gate) {
    const texts = [];
    (function walk(value) {
        if (typeof value === "string") texts.push(value);
        else if (value !== null && typeof value === "object") Object.values(value).forEach(walk);
    })(plain(Object.fromEntries(Object.entries(gate).filter(([, value]) => typeof value !== "function"))));
    const paths = texts.flatMap(text => pageReference.plain(text).match(/Settings > [^.,:]*/g) ?? []);
    assert.equal(paths.length >= 10, true, "the gate's Settings paths are read");
    for (const found of paths)
        assert.match(found, /^Settings > (Voice$|Jarvis( > [A-Z][A-Za-z ]*)?)/, JSON.stringify(found) + ": the Settings path has the one form");
    // The voices line is drawn on Details: it names the Voice field and
    // links it on Settings.
    const voices = pageReference.parse(gate.ELEVENLABS_READY);
    assert.deepEqual([voices.words.includes(manifest.schema.voice.label), voices.page, voices.tab], [true, "vgs.jarvis", "Settings/voice"], "the voices hint links the Voice field");
    for (const text of texts)
        assert.ok((text.match(/\]\(page:/g) ?? []).length <= 1, JSON.stringify(text) + ": at most one reference per drawn text");
    for (const [cause, page, tab] of [
        ...["unselected", "model-required", "models-unavailable", "model-unavailable", "signed-out"]
            .map(name => ["brain=" + name, "vgs.jarvis", "Settings"]),
        ["brain=account-unavailable", "vgs.jarvis", "Details"],
        ["brain=pi-update", "vgs.jarvis", "Details"],
        ["speech=live-account-unselected", "vgs.jarvis", "Details"],
        ["speech=live-account-unreadable", "vgs.jarvis", "Details"],
        ["speech=live-key-required", "vgs.jarvis", "Settings"],
        ["speech=local-ready-timeout", "vgs.jarvis", "Setup"],
        ["speech=always-local-voice", "vgs.jarvis", "Settings"],
        ["speech=dictation-elsewhere", "vgs.voice", "Details"],
        ["speech=dictation-device", "vgs.voice", "Settings"],
        ["home=link", "vgs.jarvis", "Settings"],
        ["home=path", "vgs.jarvis", "Settings"]]) {
        const values = gate.readiness({ kind: "answered", causes: [cause] });
        const hint = Object.entries(values).find(([key, value]) => key !== "setup" && value.hint !== undefined)[1].hint;
        const reference = pageReference.parse(hint);
        assert.deepEqual([reference.page, reference.tab], [page, tab], cause + ": the converted hint links its tab");
        assert.ok(hint.length <= judge.STATUS_HINT_MAX && oneSentence(hint), cause + ": a converted hint fits as one sentence");
    }
    const hint = gate.readiness({ kind: "answered", causes: ["brain=unselected"] }).setupModel.hint;
    assert.equal(hint, "Choose an AI model in [Settings > Jarvis > AI model](page:vgs.jarvis/Settings)", "Setup AI model hint links the field's tab");
    const source = fs.readFileSync(path.join(path.dirname(file), "SessionStart.qml"), "utf8");
    const publish = source.match(/^    function publish\(\) \{\n[\s\S]*?^    \}/m);
    assert.ok(publish);
    for (const block of ["no-home", "no-account", "not-app"]) {
        const values = {};
        const result = { kind: "answer", state: "running", reason: "resumed", detail: "", names: null, unapplied: block };
        const shell = { settings: { startAtBoot: true }, status: { set: (key, value) => { values[key] = plain(value); return "ok"; } } };
        vm.runInNewContext("(" + publish[0] + ")", { shell, result, Gate: gate, PageReference: pageReference })();
        assert.deepEqual(values.sessionStart.lines, [pageReference.plain(gate.SESSION_BLOCKS[block])], block + ": unapplied badges draw the reference's words");
        assert.equal(pageReference.parse(gate.sessionStart(true, { kind: "blocked", block }).hint).page, "vgs.jarvis", block + ": the blocked hint keeps its link");
    }
}

function verifyChipTitles(gate) {
    const titles = gate.START_CAUSES.map(([, words]) => words.title).concat([gate.DAEMON_EXIT.title]);
    assert.equal(titles.length >= 6, true, "the start cause table is read");
    for (const title of titles)
        assert.equal(title.length <= CHIP_TITLE_MAX, true, JSON.stringify(title) + " fits the Setup status chip");
}

// LocalRuntime.qml's checked(), SOURCE's, run as the reader runs it: a
// check that exits non-zero, answers no JSON or passes its deadline gives
// SetupGate's failure for the reader's entry, and an answer gives its parse.
function verifyCheckedReader(gate, source) {
    const checked = source.match(/^    function checked\(\) \{\n[\s\S]*?^    \}/m);
    assert.ok(checked, "LocalRuntime.qml declares checked()");
    const entry = manifest.status.localRuntime;
    for (const [label, timedOut, code, output, want] of [
        ["a check that exits non-zero", false, 77, "", gate.checkFailure("failed", entry)],
        ["a check that answers no JSON", false, 0, "not JSON", gate.checkFailure("unreadable", entry)],
        ["a check past its deadline", true, -1, "", gate.checkFailure("timeout", entry)],
        ["a check that answers", false, 0, JSON.stringify(LOCAL_ABSENT), LOCAL_ABSENT]]) {
        const got = vm.runInNewContext("(" + checked[0] + ")", { Gate: gate, shell: { manifest }, statusKey: "localRuntime", timedOut, code, output })();
        assert.deepEqual(plain(got), plain(want), label + ": the reader's value");
    }
}
// Service.qml's publishSetup, SERVICESOURCE's: once the Voice step's value
// changes it stores the value as voiceStep and then has the Local voice
// reader publish its row again, and it does neither while the value stays:
// [label, the daemon's answer, whether the row is published again].
function verifyVoiceStepRepublish(gate, serviceSource) {
    const publishSetup = serviceSource.match(/^    function publishSetup\(answer\) \{\n[\s\S]*?^    \}/m);
    assert.ok(publishSetup, "Service.qml declares publishSetup");
    const values = {};
    const calls = [];
    const context = { Gate: gate, dictationState: null, accountReader: { modelAccess: { kind: "checking" } }, sessionState: null, setupAnswer: { kind: "checking" },
        voiceStep: gate.readiness({ kind: "checking" }).setupVoice, sessionStart: { result: null },
        shell: { settings: { voiceAccount: "", startAtBoot: false }, requirements: { missing: [] }, status: { values, set: (key, value) => { values[key] = value; return "ok"; } } } };
    context.localRuntime = { setupCause: "", republish: () => calls.push(plain(context.voiceStep)) };
    const publish = vm.runInNewContext("(" + publishSetup[0] + ")", context);
    for (const [label, answer, republished] of [
        ["checking", { kind: "checking" }, true],
        ["checking again", { kind: "checking" }, false],
        ["local voice to do", { kind: "answered", causes: ["speech=local-not-set-up"] }, true],
        ["local voice to do again", { kind: "answered", causes: ["speech=local-not-set-up"] }, false],
        ["done", { kind: "answered", causes: [] }, true]]) {
        const before = calls.length;
        publish(answer);
        assert.equal(calls.length - before, republished ? 1 : 0, label + ": the Local voice row is published again only for a changed Voice step");
        if (republished) assert.deepEqual(calls.at(-1), plain(values.setupVoice), label + ": the row is shaped beside the published Voice step");
    }
    // The summary publishSetup writes is judged beside the session row, and
    // each answer of the session publishes it again (the SessionStart
    // element's handler, read from the source: its shape, not its run).
    context.sessionStart.result = { kind: "answer", state: "blocked", reason: "tmux-missing", detail: "", names: null };
    publish({ kind: "answered", causes: [] });
    assert.deepEqual(plain(values.setup), plain(gate.sessionSummary(gate.readiness({ kind: "answered", causes: [] }).setup,
        gate.sessionStart(false, context.sessionStart.result))), "the published summary names a session that cannot start");
    assert.notDeepEqual(plain(values.setup), plain(gate.readiness({ kind: "answered", causes: [] }).setup), "the session changes the published summary");
    assert.match(serviceSource, /^ {4}Jarvis\.SessionStart \{[^\n]*onResultChanged: root\.publishShellSetup\(\)/m, "each session answer publishes the summary again");
}
