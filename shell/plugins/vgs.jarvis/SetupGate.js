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
// What a required step still to do asks, by its cause; a cause not named
// here reads as its step's line.
var TODO = {
    "brain=unselected": "Choose an AI model below.",
    "brain=account-unavailable": "The chosen AI model cannot be used. Add a key or sign in, then choose it below.",
    "brain=model-required": "The chosen AI model cannot be used. Choose another AI model below.",
    "brain=accounts-unreadable": "Jarvis could not read your accounts. Open Accounts to check them.",
    "speech=local-not-set-up": "Set up local voice.",
    "speech=local-not-ready": "Local voice is not ready. Set up local voice again."
};
var STEP_TODO = { speech: "Set up local voice.", brain: "The chosen AI model cannot be used. Add a key or sign in, then choose it below." };
var DONE = { tone: "ok", text: "Done", action: false };
var CHECKING = { tone: "info", text: "Checking", action: false };
// A required step once the daemon stopped: no check runs, none is offered.
var UNCHECKED = { tone: "warning", text: "Not checked", action: false };

// The summary and required step values for ANSWER: { kind: "checking" }
// while the daemon has not answered, { kind: "stopped" } once it stopped
// for good, or { kind: "answered", causes } from its status, as { setup,
// setupVoice, setupModel }.
function readiness(answer) {
    switch (answer.kind) {
    case "checking":
        return { setup: CHECKING, setupVoice: CHECKING, setupModel: CHECKING };
    case "stopped":
        return { setup: { tone: "danger", text: "Not ready", lines: ["Jarvis stopped after a problem. Turn Jarvis off and on again."] },
            setupVoice: UNCHECKED, setupModel: UNCHECKED };
    case "answered":
        var out = { setup: answer.causes.length === 0 ? { tone: "ok", text: "Ready" } : { tone: "warning", text: "Not ready" },
            setupVoice: DONE, setupModel: DONE };
        answer.causes.forEach(function (cause) {
            var step = cause.slice(0, cause.indexOf("="));
            if (!Object.prototype.hasOwnProperty.call(REQUIRED, step)) throw new Error("jarvis-setup: cause=" + cause + " names no step");
            var line = Object.prototype.hasOwnProperty.call(TODO, cause) ? TODO[cause] : STEP_TODO[step];
            out[REQUIRED[step]] = { tone: "warning", text: "To do", lines: [line], action: true };
        });
        return out;
    }
    throw new Error("jarvis-setup: answer=" + JSON.stringify(answer.kind) + " unexpected");
}

// What an optional step not done yet offers, by its status key.
var OPTIONAL = {
    setupBrowser: "Set up the browser so Jarvis can use websites for you.",
    setupInput: "Check input so Jarvis can type and click for you."
};

// The value of optional step KEY from VALUE, its reader's state: done while
// that state is ok, else Optional with its line, offering the step while the
// reader offers its own action.
function optionalStep(key, value) {
    if (!Object.prototype.hasOwnProperty.call(OPTIONAL, key)) throw new Error("jarvis-setup: step=" + key + " is not optional");
    if (value.tone === "ok") return DONE;
    return { tone: "info", text: "Optional", lines: [OPTIONAL[key]], action: value.action === true };
}
