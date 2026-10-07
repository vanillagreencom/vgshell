.pragma library

// Which setup step Jarvis offers while a command its setup needs is missing,
// pure so scripts/test-jarvis-setup-gate.js runs it under node. MISSING is
// the requirements capability's list: the plugin's declared commands the
// core's last scan did not find. A missing command is offered as Install on
// its own status row, which raises the core's requirement notice, and the
// setup step that needs it is withheld until a scan finds it.

// The value a setup reader publishes: its probe's VALUE while every command
// of REQUIRES is found, else a warning naming the missing commands that
// offers no action.
function setupValue(value, requires, missing) {
    var lacking = requires.filter(function (command) { return missing.indexOf(command) !== -1; });
    if (lacking.length === 0) return value;
    return { tone: "warning", text: "Needs " + lacking.join(" and "), action: false };
}

// The value of COMMAND's own status row, whose action is its install: offered
// while the last scan did not find it.
function requirementValue(command, missing) {
    if (missing.indexOf(command) === -1) return { tone: "ok", text: "Installed", action: false };
    return { tone: "warning", text: "Not installed", action: true };
}

// The Setup section of the Jarvis page (the manifest's `Setup` group): its
// summary and one entry per setup step. The required steps come only from
// the causes the daemon publishes, ChainedEngine's one readiness judge, by
// the step each cause names; the optional ones from their own readers.
var REQUIRED = { speech: "setupVoice", brain: "setupModel" };
// The hint a required step still to do shows in place of its declared one,
// by its cause: what the step's own action does not already say. A cause
// named nowhere here takes its step's hint below; a step with none there,
// such as local voice not set up, keeps the declared hint, which says what
// the step gives, since its action already says to set it up.
var TODO = {
    "brain=unselected": "Choose an AI model below.",
    "brain=account-unavailable": "The chosen AI model cannot be used. Add a key or sign in, then choose it below.",
    "brain=model-required": "The chosen AI model cannot be used. Choose another AI model below.",
    "brain=accounts-unreadable": "Jarvis could not read your accounts. Open Accounts to check them.",
    "speech=live-account-unselected": "Choose a GPT-Live key in Voice below. Open Details and use Add key under AI model.",
    "speech=live-account-unreadable": "Jarvis could not read your GPT-Live key. Use Accounts in Setup to check it.",
    "speech=live-key-required": "GPT-Live needs a saved OpenAI key. Open Details and use Add key under AI model, then choose the key in Voice.",
    "speech=local-not-ready": "Local voice did not start. Set it up again."
};
var STEP_TODO = { brain: "The chosen AI model cannot be used. Add a key or sign in, then choose it below." };
var DONE = { tone: "ok", text: "Done", action: false };
var CHECKING = { tone: "info", text: "Checking", action: false };
var LOADING = { tone: "info", text: "Loading", action: false };
// The summary declares no action, so its value carries none: the manifest
// judge refuses an action key on an entry without one.
var CHECKING_SUMMARY = { tone: "info", text: "Checking" };
var LOADING_SUMMARY = { tone: "info", text: "Loading" };
// The installed voice stays verified. Reinstalling it cannot free memory.
var MEMORY = {
    "speech=local-memory-insufficient": { tone: "warning", text: "Not enough memory",
        hint: "Close other apps, then turn Jarvis off and on.", action: false },
    "speech=local-memory-unavailable": { tone: "warning", text: "Memory check failed",
        hint: "Turn Jarvis off and on.", action: false }
};
// A required step once the daemon stopped: no check runs, none is offered.
var UNCHECKED = { tone: "warning", text: "Not checked", action: false };

// The summary and required step values for ANSWER: { kind: "checking" }
// while the daemon has not answered, { kind: "stopped" } once it stopped
// for good, or { kind: "answered", causes } from its status, as { setup,
// setupVoice, setupModel }.
function readiness(answer) {
    switch (answer.kind) {
    case "checking":
        return { setup: CHECKING_SUMMARY, setupVoice: CHECKING, setupModel: CHECKING };
    case "stopped":
        return { setup: { tone: "danger", text: "Not ready", hint: "Jarvis stopped after a problem. Turn Jarvis off and on again." },
            setupVoice: UNCHECKED, setupModel: UNCHECKED };
    case "answered":
        var out = { setup: answer.causes.length === 0 ? { tone: "ok", text: "Ready" } : { tone: "warning", text: "Not ready" },
            setupVoice: DONE, setupModel: DONE };
        answer.causes.forEach(function (cause) {
            var step = cause.slice(0, cause.indexOf("="));
            if (!Object.prototype.hasOwnProperty.call(REQUIRED, step)) throw new Error("jarvis-setup: cause=" + cause + " names no step");
            if (cause === "speech=local-loading") {
                out.setupVoice = LOADING;
                if (answer.causes.length === 1) out.setup = LOADING_SUMMARY;
                return;
            }
            if (Object.prototype.hasOwnProperty.call(MEMORY, cause)) {
                out.setupVoice = MEMORY[cause];
                return;
            }
            var hint = Object.prototype.hasOwnProperty.call(TODO, cause) ? TODO[cause] : STEP_TODO[step];
            out[REQUIRED[step]] = hint === undefined ? { tone: "warning", text: "To do", action: true }
                : { tone: "warning", text: "To do", hint: hint, action: cause.indexOf("speech=live-") !== 0 };
        });
        return out;
    }
    throw new Error("jarvis-setup: answer=" + JSON.stringify(answer.kind) + " unexpected");
}

// The optional steps, by their status key. Their guidance is declared by
// the manifest and does not change with their state.
var OPTIONAL = {
    setupBrowser: true,
    setupInput: true
};

// The value of optional step KEY from VALUE, its reader's state: done while
// that state is ok, else Optional, offering the step while the
// reader offers its own action.
function optionalStep(key, value) {
    if (!Object.prototype.hasOwnProperty.call(OPTIONAL, key)) throw new Error("jarvis-setup: step=" + key + " is not optional");
    if (value.tone === "ok") return DONE;
    return { tone: "info", text: "Optional", action: value.action === true };
}
