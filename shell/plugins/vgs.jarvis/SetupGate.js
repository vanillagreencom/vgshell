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
var REQUIRED = { home: "setupHome", guidance: "setupHome", speech: "setupVoice", brain: "setupModel" };
// The hint a required step still to do shows in place of its declared one,
// by its cause: what the step's own action does not already say. A cause
// named nowhere here takes its step's hint below; a step with none there,
// such as local voice not set up, keeps the declared hint, which says what
// the step gives, since its action already says to set it up.
var TODO = {
    "brain=unselected": "Choose an AI model in Settings > AI model.",
    "brain=account-unavailable": "The chosen AI model cannot be used. Add a key or sign in, then choose it below.",
    "brain=model-required": "The chosen AI model cannot be used. Choose another AI model below.",
    "brain=signed-out": "The chosen AI model is not signed in. Sign in, then choose it below.",
    "brain=pi-update": "Jarvis needs Pi 1.1.0 or later. Update Pi, or choose another AI model below.",
    "brain=accounts-unreadable": "Jarvis could not read your accounts. Open Accounts to check them.",
    "speech=live-account-unselected": "Add an OpenAI key under Setup at the top of this page.",
    "speech=live-account-unreadable": "Jarvis could not read your OpenAI key. Use Accounts in Setup to check it.",
    "speech=live-key-required": "Add an OpenAI key under Setup at the top of this page.",
    "speech=local-not-ready": "Local voice did not start. Set it up again.",
    "speech=always-local-voice": "Always talk mode listens for Hey Jarvis on this computer. Choose Local in Settings > Voice, or Hold or Toggle in Settings > Listening."
};
// Causes whose step the voice setup action cannot complete: the user
// changes a setting or adds a key instead.
function setupActs(cause) {
    return cause.indexOf("speech=live-") !== 0 && cause !== "speech=always-local-voice";
}
var STEP_TODO = { brain: "The chosen AI model cannot be used. Add a key or sign in, then choose it below." };
// The home folder step shows only while the daemon refuses the folder the
// user chose, with what to change, by its cause; any other cause of the
// folder or its text takes HOME_STEP_TODO. Its entry declares no action:
// the user changes the folder or the setting. A changed setting reaches
// the daemon at once; a change inside the folder does at the next request
// (jarvisd.js judgeSetup), which HOME_AGAIN says.
var HOME_AGAIN = " Jarvis checks the folder again when you press Talk.";
var HOME_TODO = {
    "home=link": "The home folder has a link where Jarvis keeps a file or a folder. Remove the link, or choose another folder in Settings > Home." + HOME_AGAIN,
    "home=path": "Jarvis cannot use this folder. Choose a folder inside your own home directory in Settings > Home.",
    "guidance=home-too-large": "AGENTS.md in the home folder is too long. Make it shorter than 8 KB." + HOME_AGAIN,
    "guidance=home-skills-too-large": "The home folder has more skills than Jarvis can list. Remove the skills you do not use." + HOME_AGAIN,
    "guidance=home-memory-too-large": "memory/MEMORY.md in the home folder is too long. Make it shorter than 4 KB." + HOME_AGAIN
};
var HOME_STEP_TODO = "Jarvis cannot use the home folder. Check that you can open and change it, or choose another folder in Settings > Home." + HOME_AGAIN;
var HOME_READY = { hidden: true };
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
// The AI model step declares named actions, Add key ("key") and Sign in
// ("signIn"), so its value names the one that applies or carries no
// action: the manifest judge refuses a boolean on it.
function noAction(value) {
    var out = Object.assign({}, value);
    delete out.action;
    return out;
}
var SIGNED_OUT_HINT = "Your Claude Code or Codex account is not signed in. Sign in, then choose it below.";

// Account discovery supplies typed states even before it offers a model:
// present while an app is signed in, signed-out while an app Sign in serves
// is found signed out (the account list's signIn), else absent. A found CLI
// folder alone does not establish that its app is signed in.
function accountAccess(accounts) {
    if (accounts.some(function (account) {
        return account.source === "cli" && ["signed-in", "verified", "verifying"].indexOf(account.state) !== -1;
    })) return { kind: "present" };
    return { kind: accounts.some(function (account) { return account.signIn === true; }) ? "signed-out" : "absent" };
}

// The model row keeps Sign in for a signed-out cause. Otherwise it offers
// a step only after both readers find no key or signed-in app: Sign in
// while an app is found signed out, else Add key. Missing reader output
// stays checking, without an action.
function modelStep(value, keys, access) {
    if (value.action !== "key") return value;
    var absent = keys !== undefined && keys.every(function (key) { return key.value === "absent"; });
    if (absent && access.kind === "absent") return value;
    if (absent && access.kind === "signed-out") return Object.assign({}, value, { hint: SIGNED_OUT_HINT, action: "signIn" });
    return noAction(value);
}

// The summary and required step values for ANSWER: { kind: "checking" }
// while the daemon has not answered, { kind: "stopped" } once it stopped
// for good, or { kind: "answered", causes } from its status, as { setup,
// setupHome, setupVoice, setupModel }.
function readiness(answer) {
    switch (answer.kind) {
    case "checking":
        return { setup: CHECKING_SUMMARY, setupHome: HOME_READY, setupVoice: CHECKING, setupModel: noAction(CHECKING) };
    case "stopped":
        return { setup: { tone: "danger", text: "Not ready", hint: "Jarvis stopped after a problem. Turn Jarvis off and on again." },
            setupHome: HOME_READY, setupVoice: UNCHECKED, setupModel: noAction(UNCHECKED) };
    case "answered":
        var out = { setup: answer.causes.length === 0 ? { tone: "ok", text: "Ready" } : { tone: "warning", text: "Not ready" },
            setupHome: HOME_READY, setupVoice: DONE, setupModel: noAction(DONE) };
        answer.causes.forEach(function (cause) {
            var step = cause.slice(0, cause.indexOf("="));
            if (!Object.prototype.hasOwnProperty.call(REQUIRED, step)) throw new Error("jarvis-setup: cause=" + cause + " names no step");
            if (REQUIRED[step] === "setupHome") {
                out.setupHome = { tone: "warning", text: "To do",
                    hint: Object.prototype.hasOwnProperty.call(HOME_TODO, cause) ? HOME_TODO[cause] : HOME_STEP_TODO };
                return;
            }
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
            var action = step === "brain" ? (cause === "brain=signed-out" ? "signIn" : "key") : setupActs(cause);
            out[REQUIRED[step]] = hint === undefined ? { tone: "warning", text: "To do", action: action }
                : { tone: "warning", text: "To do", hint: hint, action: action };
        });
        return out;
    }
    throw new Error("jarvis-setup: answer=" + JSON.stringify(answer.kind) + " unexpected");
}

// The Copilot Memory row for ACCOUNTS, the account list's items: shown
// while a GitHub Copilot account is found signed in or unchecked. GitHub
// keeps Copilot Memory in the account, where only the user can turn it off;
// its entry's hint and link say where (D075).
function copilotMemory(accounts) {
    return accounts.some(function (account) { return account.provider === "copilot" && account.value === "present"; })
        ? { tone: "info", text: "Your step" } : { hidden: true };
}

// The voice the daemon runs for SETTINGS, the plugin's: the provider the
// user chose, or for "auto" Realtime while the Realtime key setting names
// a stored OpenAI key, else Local. Always talk mode listens on this
// computer, so "auto" stays Local in it. OFFERED is the account reader's
// stored OpenAI keys, undefined while it has no answer, before its first
// read and after a failed one: the named key then counts as stored, so a
// start loads no local voice the first answer would replace, and the
// daemon judges a key it cannot read. Jarvis names a sole stored key
// itself (Accounts.qml).
function voiceProvider(settings, offered) {
    if (settings.voiceProvider !== "auto") return settings.voiceProvider;
    if (settings.mode === "always" || settings.voiceAccount === "") return "local";
    var stored = offered === undefined || offered.some(function (key) { return key.value === settings.voiceAccount; });
    return stored ? "realtime" : "local";
}

// The Voice group's key row for OFFERED, the stored OpenAI keys, or null
// while the account reader could not read them: Add key is offered until
// one is stored. The entry's hint says what the key unlocks (D075).
function voiceKey(offered) {
    if (offered === null) return { tone: "warning", text: "Could not check", action: true };
    return offered.length === 0 ? { tone: "info", text: "No key stored", action: true } : { tone: "ok", text: "Key stored", action: false };
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
