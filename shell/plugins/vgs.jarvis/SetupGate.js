.pragma library

// Which setup step Jarvis offers while a command its setup needs is missing,
// pure so scripts/test-jarvis-setup-gate.js runs it under node. MISSING is
// the requirements capability's list: the plugin's declared commands the
// core's last scan did not find. A missing command is offered as Install on
// its own status row, which raises the core's requirement notice, and the
// setup step that needs it is withheld until a scan finds it.

// The value a setup reader publishes: its probe's VALUE while every command
// of REQUIRES is found, else a warning naming the missing commands that
// offers no action: false for an entry's one action, and none for a named
// one, which the manifest judge takes only as a name. Set up dictation stays
// offered: voxtype is the program the core's dictation setup gets ready.
function setupValue(value, requires, missing) {
    var lacking = requires.filter(function (command) { return missing.indexOf(command) !== -1; });
    if (lacking.length === 0) return value;
    var withheld = { tone: "warning", text: "Needs " + lacking.join(" and ") };
    if (value.action === "dictation") withheld.action = "dictation";
    else if (typeof value.action !== "string") withheld.action = false;
    return withheld;
}

// The commands a named step action needs: the core's dictation setup
// gets voxtype ready, which it cannot run without.
var ACTION_REQUIRES = { dictation: ["voxtype"] };
function actionRequires(value) {
    return typeof value.action === "string" && Object.prototype.hasOwnProperty.call(ACTION_REQUIRES, value.action)
        ? ACTION_REQUIRES[value.action] : [];
}

// Whether the voice PROVIDER (voiceProvider) hears the user on this
// computer: the local voice, and ElevenLabs, which only speaks the reply.
function hearsLocally(provider) {
    return provider === "local" || provider === "elevenlabs";
}

// The local voice takes its final words from the core's dictation
// recording (D064), over the capability's lent STATE, null before the
// first read. PROVIDER is the voice the daemon runs (voiceProvider). The
// cause the daemon holds the local voice with while that recording cannot
// start, which the hello carries (ChainedEngine select), "" while it can
// or for a voice that hears the user elsewhere. voxtype records the device
// its config names, and the local voice's captions hear the default source
// (Audio.js selected).
function dictationCause(provider, state) {
    if (!hearsLocally(provider) || state === null) return "";
    if (["absent", "starting", "failed", "elsewhere"].indexOf(state.daemon) !== -1) return "speech=dictation-" + state.daemon;
    return otherDevice(state) ? "speech=dictation-device" : "";
}
function otherDevice(state) {
    return state.daemon === "ready" && state.device !== "default";
}

// The service's answer to the daemon's dictation start before the core's,
// for a hello the device changed after: a keyed refusal, else "".
function dictationRefusal(state) {
    return otherDevice(state) ? "refused: dictation=device" : "";
}

// The core owns setup readings and the daemon's start gate. A holder's
// existing setup step names the missing parts from that shared result.
function dictationSetup(value, state) {
    if (value.action !== "dictation" || state === null || state.setup === null) return value;
    var setup = state.setup, lines = [];
    if (!setup.compiled) lines.push("The active build cannot use the " + setup.engine + " speech engine.");
    if (!setup.installed) lines.push("The " + setup.model + " dictation speech model is not installed.");
    return lines.length === 0 ? value : Object.assign({}, value, { hint: lines.join(" ") });
}

// The value of the status row of COMMAND, one the manifest gives a floor:
// missing, below its floor or installed. OUTDATED is the requirements
// capability's list of the plugin's commands the core's last scan read
// below their floor. The row offers no action: the page's Requirements
// section installs or updates it.
function flooredValue(command, missing, outdated) {
    if (missing.indexOf(command) !== -1) return { tone: "warning", text: "Not installed" };
    if (outdated.indexOf(command) !== -1) return { tone: "warning", text: "Needs an update" };
    return { tone: "ok", text: "Installed" };
}

// The Setup section of the Jarvis page (the manifest's `Setup` group): its
// summary and one entry per setup step. The required steps come only from
// the causes the daemon publishes, ChainedEngine's one readiness judge, by
// the step each cause names; the optional ones from their own readers.
var REQUIRED = { home: "setupHome", guidance: "setupHome", speech: "setupVoice", brain: "setupModel" };
var STEP_NAMES = { setupHome: "Home folder", setupVoice: "Voice", setupModel: "AI model" };
// What the Voice step and the ElevenLabs voices row say after a failed read
// of the key's voices (ChainedEngine voicesHeld).
var ELEVENLABS_UNREAD = "Jarvis could not read the voices of your ElevenLabs key: check under ElevenLabs API keys that it may read voices, then press Talk";
// The hint a required step still to do shows in place of its declared one,
// by its cause: what the step's own action does not already say. A cause
// named nowhere here takes its step's hint below; a step with none there,
// such as local voice not set up, keeps the declared hint, which says what
// the step gives, since its action already says to set it up.
var TODO = {
    "brain=unselected": "Choose an AI model in [Settings > Jarvis > AI model](page:vgs.jarvis/Settings)",
    "brain=account-unavailable": "The selected account or its key is unavailable: [add a provider key or sign in on the Details tab](page:vgs.jarvis/Details)",
    "brain=model-required": "Choose a model in [Settings > Jarvis > AI model](page:vgs.jarvis/Settings)",
    "brain=models-reading": "Jarvis is reading the local server model list",
    "brain=models-unavailable": "Check the local server, then [choose a model](page:vgs.jarvis/Settings) under AI model and press Talk to try again",
    "brain=model-unavailable": "The local server does not offer this model: [choose another model](page:vgs.jarvis/Settings) under AI model",
    "brain=signed-out": "Sign in to the chosen AI app, then [choose it under AI model](page:vgs.jarvis/Settings)",
    "brain=pi-update": "Jarvis needs Pi 1.1.0 or later: [review all missing or outdated tools under Tools on the Details tab](page:vgs.jarvis/Details), or choose another app under AI model",
    "brain=accounts-unreadable": "Jarvis could not read your accounts. Open Accounts to check them.",
    "speech=live-account-unselected": "[Add a provider key beside API keys on the Details tab](page:vgs.jarvis/Details): OpenAI for Realtime, Gemini for Gemini Live or ElevenLabs for ElevenLabs",
    "speech=live-account-unreadable": "Jarvis could not read your voice key: use [Accounts beside Account search on the Details tab](page:vgs.jarvis/Details) to check it",
    "speech=live-key-required": "[Choose a key under Voice key](page:vgs.jarvis/Settings): OpenAI for Realtime, Gemini for Gemini Live or ElevenLabs for ElevenLabs; Add key beside API keys stores a new key",
    "speech=elevenlabs-voice": ELEVENLABS_UNREAD,
    "speech=local-not-ready": "Set up the local voice again",
    "speech=local-ready-timeout": "Local voice timed out: [turn Jarvis off and on again, or set it up again](page:vgs.jarvis/Setup)",
    "speech=always-local-voice": "Always talk mode needs Local: [choose Local as Voice provider](page:vgs.jarvis/Settings), or Hold or Toggle as Talk mode"
};
// Local voice that did not get ready in time is set up: its step states
// that result in place of To do, and the bar shows the step's hint for it
// (WidgetView.unconfiguredText).
var TIMED_OUT = "Timed out";
// The shell's own causes (LocalRuntime.qml setupCause), by their hint. The
// daemon never reads one, and Session's gate follows the daemon alone
// (jarvisd.js configured), so Jarvis still takes a request: the summary
// stays ready with the cause as a caution, and no step turns to do. The
// hint says what the cause means beside Ready and asks for nothing: the
// check runs again after each setup run and requirement scan.
var CAUTION = {
    "setup=probe-timeout": "Jarvis answers, but its check of the local voice did not finish"
};
// The dictation causes (dictationCause), by the Voice step's value. The
// core's dictation setup copies voxtype's defaults and downloads its model;
// the user stops another voxtype, or chooses voxtype's microphone, in Voice.
var DICTATION = {
    "speech=dictation-absent": { tone: "warning", text: "To do", hint: "Set up dictation so the local voice can hear you", action: "dictation" },
    "speech=dictation-failed": { tone: "warning", text: "To do", hint: "Set up dictation again", action: "dictation" },
    "speech=dictation-elsewhere": { tone: "warning", text: "Another voxtype runs", hint: "Stop the other voxtype beside [Other dictation service in Voice Details](page:vgs.voice/Details)" },
    "speech=dictation-device": { tone: "warning", text: "Dictation uses another microphone", hint: "The local voice hears the system default microphone: choose it with [Configure in Settings > Voice](page:vgs.voice/Settings)" }
};
// Causes whose step the voice setup action cannot complete: the user
// changes a setting, adds a key or fixes the ElevenLabs key instead.
function setupActs(cause) {
    return cause.indexOf("speech=live-") !== 0 && cause.indexOf("speech=elevenlabs-") !== 0 && cause !== "speech=always-local-voice";
}
var STEP_TODO = { brain: "Add a key or sign in, then [choose an AI model](page:vgs.jarvis/Settings) under AI model" };
// The required home step stays visible. A daemon refusal states what to
// change, by its cause; any other cause of the
// folder or its text takes HOME_STEP_TODO. Its entry declares no action:
// the user changes the folder or the setting. A changed setting reaches
// the daemon at once; a change inside the folder does at the next request
// (jarvisd.js judgeSetup), which the row's info explains.
var HOME_TODO = {
    "home=link": "Remove the link from the home folder, or [choose another Home folder](page:vgs.jarvis/Settings): Jarvis checks again when you press Talk",
    "home=path": "Jarvis cannot use this folder: [choose a Home folder](page:vgs.jarvis/Settings) inside your own home directory",
    "guidance=home-skills-too-large": "Remove unused skills from the home folder so Jarvis can list them"
};
var HOME_STEP_TODO = "Check that you can open and change the folder, or [choose another Home folder](page:vgs.jarvis/Settings): Jarvis checks again when you press Talk";
var HOME_READY = { tone: "ok", text: "Done" };
// The home texts over their size budget (JarvisProtocol SETUP_CAUTIONS),
// by the name the Home folder step gives each. Jarvis loads each whole and
// answers, so the summary stays Ready and the step Done, with a hint that
// names the texts. The hint goes on the step, not the summary, whose hint
// a session fault and a shell caution already share.
var OVER_BUDGET = {
    "guidance=persona-over-budget": "persona.md",
    "guidance=agents-over-budget": "AGENTS.md",
    "guidance=skills-over-budget": "the skill list",
    "guidance=memory-over-budget": "memory/MEMORY.md",
    "guidance=start-over-budget": "the start text"
};
// The Personality row from SHOWN, the daemon's personality message, and
// CAUSES, its last answer's: the section as the row's hint, which Settings
// draws as text where a state's text and lines draw as badges; or what keeps
// it from showing. The hint holds at most PluginLogic's STATUS_HINT_MAX of
// 200 characters, so a longer or cut section ends in "…". An AGENTS.md over
// its budget adds a line in the info tone: Jarvis still reads it whole.
var AGENTS_OVER = "AGENTS.md is over its budget";
function personalityRow(shown, causes) {
    var joined = shown.kind === "section" ? shown.lines.join(" ") : "";
    var cut = joined.length > 200 || shown.more === true;
    var value = shown.kind === "section" ? { tone: "ok", text: "Set", hint: cut ? joined.slice(0, 199).trimEnd() + "…" : joined, action: true }
        : shown.kind === "none" ? { tone: "info", text: "No home folder",
            hint: "Jarvis reads its personality from AGENTS.md in the folder that [Home folder](page:vgs.jarvis/Settings/home) sets" }
        : shown.kind === "missing" ? { tone: "info", text: "No Personality section", action: true,
            hint: "Edit opens AGENTS.md. Add the heading ## Personality on its own line and say how Jarvis talks under it." }
        : { tone: "warning", text: "AGENTS.md cannot be read", hint: "AGENTS.md is in the folder that [Home folder](page:vgs.jarvis/Settings/home) sets" };
    if ((shown.kind === "section" || shown.kind === "missing") && causes.indexOf("guidance=agents-over-budget") !== -1)
        return Object.assign({}, value, { tone: "info", lines: [AGENTS_OVER] });
    return value;
}

// The Home folder step over CAUSES, the over-budget causes of an answer
// whose home step is done: Done, with a hint naming each text over its
// budget while one is.
function homeDone(causes) {
    var names = causes.filter(function (cause) { return Object.prototype.hasOwnProperty.call(OVER_BUDGET, cause); })
        .map(function (cause) { return OVER_BUDGET[cause]; });
    if (names.length === 0) return HOME_READY;
    var listed = names.length === 1 ? names[0] : names.slice(0, -1).join(", ") + " and " + names[names.length - 1];
    return { tone: "ok", text: "Done", hint: "Jarvis reads " + listed + " whole, but " + (names.length === 1 ? "it is over its budget" : "they are over their budgets") };
}
var HOME_UNCHECKED = { tone: "warning", text: "Not checked" };
var DONE = { tone: "ok", text: "Done", action: false };
// Voice setup uses Session's check result, which only the local wake detector
// supplies. A step that names its own action, such as Set up dictation, keeps it.
function voiceCheck(value, check) {
    if (value.tone !== "ok" || check === null || check.kind === "unavailable") return value.action === true
        ? Object.assign({}, value, { action: "setup" }) : typeof value.action === "string" ? value : noAction(value);
    if (check.kind === "waiting" || check.kind === "recording")
        return { tone: "info", text: "Say Hey Jarvis", hint: "The microphone is open for three seconds" };
    if (check.kind === "finishing") return { tone: "info", text: "Checking" };
    if (check.kind === "failed") return { tone: "danger", text: "Check failed",
        hint: "Jarvis could not check the microphone: press Check microphone to try again", action: "check" };
    if (check.kind === "done") {
        if (check.result === "ready") return { tone: "ok", text: "Ready", action: "check" };
        // Only the local voice checks, and it hears the system default.
        if (check.result === "silent") return { tone: "warning", text: "Muted or silent", hint: "The default microphone is muted or sends silence: [check it in System > Sound](page:vgs.sound)", action: "check" };
        return { tone: "warning", text: "Not heard", hint: "Jarvis did not hear Hey Jarvis: try again closer or in a quieter room", action: "check" };
    }
    return { tone: "info", text: "Not checked", hint: "Press Check microphone, then say Hey Jarvis", action: "check" };
}
var CHECKING = { tone: "info", text: "Checking", action: false };
var LOADING = { tone: "info", text: "Loading", action: false };
// The summary declares no action, so its value carries none: the manifest
// judge refuses an action key on an entry without one.
var CHECKING_SUMMARY = { tone: "info", text: "Checking" };
var LOADING_SUMMARY = { tone: "info", text: "Loading" };
// A hint of one sentence ends with no full stop, and each sentence of a
// longer one ends with one (docs/architecture/design-system.md § Copy). TEXT, such a hint,
// as one sentence of a longer text or of a notice: ending with a full stop.
function sentence(text) {
    return /\.$/.test(text) ? text : text + ".";
}
// HINTS, each a hint of its own, as one hint: one as it is, several with a
// full stop after each sentence.
function joinedHint(hints) {
    return hints.length === 1 ? hints[0] : hints.map(sentence).join(" ");
}
var START_RESTART = "Turn Jarvis off and on again in [Settings > Jarvis](page:vgs.jarvis/Settings)";
var START_CAUSES = [
    [/^jarvis: hello=timeout$/, { kind: "hello-timeout", title: "Jarvis did not answer in time", detail: "Jarvis could not finish starting.", action: START_RESTART }],
    [/^jarvis: node=[^ ]+ need=22$/, { kind: "node-too-old", title: "Jarvis needs Node 22 or later", detail: "The installed Node version cannot run Jarvis.", action: "Update Node to version 22 or later, then turn Jarvis off and on again in [Settings > Jarvis](page:vgs.jarvis/Settings)" }],
    [/^jarvis: daemon=exit code=78 status=/, { kind: "node-too-old", title: "Jarvis needs Node 22 or later", detail: "The installed Node version cannot run Jarvis.", action: "Update Node to version 22 or later, then turn Jarvis off and on again in [Settings > Jarvis](page:vgs.jarvis/Settings)" }],
    [/^jarvis: daemon=(exit|ended)/, { kind: "daemon-exit", title: "Jarvis daemon stopped", detail: "Jarvis stopped after a problem.", action: START_RESTART }],
    [/^jarvis: protocol=/, { kind: "wire-defect", title: "Jarvis message error", detail: "Jarvis could not read a message from its service.", action: START_RESTART }]
];
var DAEMON_EXIT = { kind: "daemon-exit", title: "Jarvis daemon stopped", detail: "Jarvis stopped after a problem.", action: START_RESTART };
var RETRYING_START = "Jarvis is trying again by itself";

function startCause(cause) {
    for (var i = 0; i < START_CAUSES.length; i++) {
        if (START_CAUSES[i][0].test(cause)) {
            var words = START_CAUSES[i][1];
            return { kind: words.kind, title: words.title, action: words.action, lines: [words.detail] };
        }
    }
    return { kind: DAEMON_EXIT.kind, title: DAEMON_EXIT.title, action: DAEMON_EXIT.action, lines: [DAEMON_EXIT.detail] };
}

// The `daemon` value after a failed start, RETRYING or stopped for good:
// the bar words it from its title and hint. Its detail line uses plain
// words; the service keeps the keyed cause in the log.
function startStatus(cause, retrying) {
    var problem = startCause(cause);
    return { tone: retrying ? "warning" : "danger", text: problem.title,
        hint: retrying ? RETRYING_START : problem.action, lines: problem.lines };
}

// The desktop notices after CAUSE stopped Jarvis for good, and after it
// refused a mute press: the cause's title and action, never its key.
function stoppedNotice(cause) {
    var problem = startCause(cause);
    return { title: problem.title, message: sentence(problem.action), tone: "danger", icon: "mic" };
}
function muteRefusedNotice(cause) {
    return { title: "Jarvis mute not saved", message: "Mute request could not be saved: " + startCause(cause).title + ".",
        tone: "danger", icon: "mic" };
}
// The installed voice stays verified. Reinstalling it cannot free memory.
var MEMORY = {
    "speech=local-memory-insufficient": { tone: "warning", text: "Not enough memory",
        hint: "Close other apps, then turn Jarvis off and on", action: false },
    "speech=local-memory-unavailable": { tone: "warning", text: "Memory check failed",
        hint: "Turn Jarvis off and on", action: false }
};
// A required step once the daemon stopped: no check runs, none is offered.
var UNCHECKED = { tone: "warning", text: "Not checked", action: false };
// The AI model step declares named actions, Add key ("key") and Sign in
// ("signIn"), so its value names the one that applies or carries no
// action: the manifest judge refuses a boolean on it. A Pi below its floor
// offers neither: the page's Requirements section updates it.
function noAction(value) {
    var out = Object.assign({}, value);
    delete out.action;
    return out;
}
var SIGNED_OUT_HINT = "Sign in to your Claude Code or Codex account, then [choose it under AI model](page:vgs.jarvis/Settings)";

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
// for good, { kind: "problem", cause } after a failed start, or
// { kind: "answered", causes } from its status, as { setup, setupHome,
// setupVoice, setupModel }. No value holds a keyed cause: the service
// log keeps it.
function readiness(answer) {
    switch (answer.kind) {
    case "checking":
        return { setup: CHECKING_SUMMARY, setupHome: HOME_UNCHECKED, setupVoice: CHECKING, setupModel: noAction(CHECKING) };
    case "stopped":
        return { setup: { tone: "danger", text: "Not ready", hint: "Turn Jarvis off and on again" },
            setupHome: HOME_UNCHECKED, setupVoice: UNCHECKED, setupModel: noAction(UNCHECKED) };
    case "problem":
        var problem = startCause(answer.cause);
        return { setup: { tone: "danger", text: problem.title, hint: answer.action || problem.action },
            setupHome: HOME_UNCHECKED, setupVoice: UNCHECKED, setupModel: noAction(UNCHECKED) };
    case "answered":
        // The summary says only its state and hint: each step words its own
        // causes, and a caution's hint is its words.
        // A home text over its budget is a caution of the Home folder step
        // alone (homeDone).
        var causes = answer.causes.filter(function (cause) { return !Object.prototype.hasOwnProperty.call(OVER_BUDGET, cause); });
        var blocking = causes.filter(function (cause) { return !Object.prototype.hasOwnProperty.call(CAUTION, cause); });
        var out = { setup: causes.length === 0 ? { tone: "ok", text: "Ready" }
                : blocking.length === 0 ? { tone: "ok", text: "Ready", hint: joinedHint(causes.map(function (cause) { return CAUTION[cause]; })) }
                    : { tone: "warning", text: "Not ready" },
            setupHome: homeDone(answer.causes), setupVoice: DONE, setupModel: noAction(DONE) };
        var open = [];
        blocking.forEach(function (cause) {
            var step = cause.slice(0, cause.indexOf("="));
            if (!Object.prototype.hasOwnProperty.call(REQUIRED, step)) throw new Error("jarvis-setup: cause=" + cause + " names no step");
            var name = STEP_NAMES[REQUIRED[step]];
            if (open.indexOf(name) === -1) open.push(name);
            if (REQUIRED[step] === "setupHome") {
                out.setupHome = { tone: "warning", text: "To do",
                    hint: Object.prototype.hasOwnProperty.call(HOME_TODO, cause) ? HOME_TODO[cause] : HOME_STEP_TODO };
                return;
            }
            // ElevenLabs's voices are being read: the voice is chosen once
            // they answer.
            if (cause === "speech=local-loading" || cause === "speech=dictation-starting" || cause === "speech=elevenlabs-voices-reading") {
                out.setupVoice = LOADING;
                if (blocking.length === 1) out.setup = LOADING_SUMMARY;
                return;
            }
            if (Object.prototype.hasOwnProperty.call(MEMORY, cause)) {
                out.setupVoice = MEMORY[cause];
                return;
            }
            if (Object.prototype.hasOwnProperty.call(DICTATION, cause)) {
                out.setupVoice = DICTATION[cause];
                return;
            }
            var hint = Object.prototype.hasOwnProperty.call(TODO, cause) ? TODO[cause] : STEP_TODO[step];
            var action = step === "brain" ? (cause === "brain=signed-out" ? "signIn" : "key") : setupActs(cause);
            var text = cause === "speech=local-ready-timeout" ? TIMED_OUT : "To do";
            out[REQUIRED[step]] = hint === undefined ? { tone: "warning", text: text, action: action }
                : { tone: "warning", text: text, hint: hint, action: action };
            if (cause === "brain=pi-update") out[REQUIRED[step]] = noAction(out[REQUIRED[step]]);
        });
        if (out.setup.tone === "warning") out.setup.hint = "Complete " + open.join(" and ");
        return out;
    }
    throw new Error("jarvis-setup: answer=" + JSON.stringify(answer.kind) + " unexpected");
}

// The Copilot Memory row for ACCOUNTS, the account list's items: shown
// while a GitHub Copilot account is found signed in or unchecked. GitHub
// keeps Copilot Memory in the account, where only the user can turn it off
// and Jarvis cannot read it, so the row states where it is kept; its
// entry's hint and link say where to turn it off (D075).
function copilotMemory(accounts) {
    return accounts.some(function (account) { return account.provider === "copilot" && account.value === "present"; })
        ? { tone: "info", text: "Kept by GitHub" } : { hidden: true };
}

// The voice the daemon runs for SETTINGS, the plugin's: the provider the
// user chose, or for "auto" Realtime while the Voice key setting names a
// stored OpenAI key, else Local. Always talk mode listens on this
// computer, so "auto" stays Local in it. OFFERED is the account reader's
// stored cloud voice keys, each {value, label, provider}, undefined while
// it has no answer, before its first read and after a failed one. A key's
// id does not tell its provider, so with no answer "auto" is Local: the
// named key may be a Gemini key, which Realtime cannot use, and the first
// answer moves "auto" to Realtime when it names an OpenAI key. Jarvis
// names a sole stored key itself (voiceChoice).
function voiceProvider(settings, offered) {
    if (settings.voiceProvider !== "auto") return settings.voiceProvider;
    if (settings.mode === "always" || offered === undefined) return "local";
    return offered.some(function (key) { return key.provider === "openai" && key.value === settings.voiceAccount; }) ? "realtime" : "local";
}

// The account provider whose keys the Voice key setting offers for
// SETTINGS: Gemini for Gemini Live, ElevenLabs for ElevenLabs, else OpenAI,
// which Realtime and Auto use.
function voiceKeyProvider(settings) {
    return settings.voiceProvider === "gemini" || settings.voiceProvider === "elevenlabs" ? settings.voiceProvider : "openai";
}

// Whether the voice PROVIDER (voiceProvider) speaks through a provider's
// network service with the user's key, which a preview may be charged for.
function cloudSpeech(provider) {
    return provider === "realtime" || provider === "gemini" || provider === "elevenlabs";
}

// The Voice key choices for SETTINGS from KEYS, the account reader's stored
// cloud voice keys: the keys of the selected cloud voice's provider.
function voiceKeys(keys, settings) {
    var provider = voiceKeyProvider(settings);
    return keys.filter(function (key) { return key.provider === provider; })
        .map(function (key) { return { value: key.value, label: key.label }; });
}

// The key Jarvis selects for the user from KEYS, or null: the sole stored
// key of the selected cloud voice, while the Voice key setting names none,
// or, while a cloud voice is chosen, a stored key of another cloud voice,
// as after a change of Voice provider. Under Local or Auto a named key
// stays, so a Gemini key chosen before survives a visit to Local; a named
// key that is not stored, such as a locked one, stays too.
function voiceChoice(keys, settings) {
    var offered = voiceKeys(keys, settings);
    if (offered.length !== 1) return null;
    var named = settings.voiceAccount;
    if (named === "") return offered[0].value;
    var cloud = cloudSpeech(settings.voiceProvider);
    var other = cloud && keys.some(function (key) { return key.value === named && key.provider !== voiceKeyProvider(settings); });
    return other ? offered[0].value : null;
}

// The Cloned voice setup row (the manifest's clonedVoiceSetup) for VALUE,
// `setup-local clone status`'s answer, or the reader's own failure value
// with `action: true`. PROVIDER is the voice the daemon runs
// (voiceProvider). The cloned voice speaks only through the local voice,
// beside its graphics card tier (VGS-1384), never through a cloud voice,
// ElevenLabs included: while either is missing, Set up
// is withheld with the reason. Remove recording stays offered whatever the
// voice. `recording` and `tierReady` are setup-local's, for this row only;
// a failed read has neither, and its setup judges the tier itself. The row
// words its state: a failed read's keyed line stays off it. It is an
// optional step of the Setup tab, as Browser and Input are: any state but
// ready reads info, so it never makes Jarvis read Setup needed nor takes the
// page's primary action from a required step (Steps.js stepOpen).
var CLONE_WITHHELD = {
    provider: { text: "Needs the Local voice", hint: "The cloned voice speaks only through Local in [Voice provider](page:vgs.jarvis/Settings/voiceProvider)" },
    tier: { text: "Needs the Large model", hint: "The cloned voice needs the Large model in [Local voice model](page:vgs.jarvis/Settings/localTier), and the Large model runs only on an NVIDIA graphics card" }
};
// The hint of a ready row: what the recording gives now. The declared hint
// says how to set the step up, which a done step no longer asks.
var CLONE_READY_HINT = "Jarvis speaks in this voice while Cloned voice is on";
function clonedVoiceStep(value, provider) {
    var action = value.action === true ? "setup" : value.action;
    var reason = provider !== "local" ? CLONE_WITHHELD.provider : value.tierReady === false ? CLONE_WITHHELD.tier : null;
    // A row of named actions offers none by leaving `action` out.
    if (reason !== null && action !== "remove") return { tone: "info", text: reason.text, hint: reason.hint };
    var row = { tone: value.tone === "ok" ? "ok" : "info", text: value.text };
    if (typeof action === "string") row.action = action;
    if (reason !== null) row.hint = reason.hint;
    else if (value.hint !== undefined) row.hint = value.hint;
    else if (row.tone === "ok") row.hint = CLONE_READY_HINT;
    return row;
}

// Where to get a key and what it unlocks (D075), by the Voice provider
// setting: the chosen cloud voice's key, or under Local and Auto the keys
// of the two voices that hear you. The row's one link, Google AI Studio,
// draws where the hint names it; another page is named in words alone.
// `other` is the declared hint.
var VOICE_KEY_HINTS = {
    realtime: "Get an OpenAI key from OpenAI API keys to use the Realtime voice",
    gemini: "Get a Gemini key from Google AI Studio to use the Gemini Live voice",
    elevenlabs: "Get an ElevenLabs key from ElevenLabs API keys to speak in your ElevenLabs voices",
    other: "Get an OpenAI key from OpenAI API keys for the Realtime voice, or a Gemini key from Google AI Studio for Gemini Live"
};
// The hint of a row with a key stored, by the provider of the offered keys
// (voiceKeyProvider): what the key gives, and how to use another. Jarvis
// stores its keys itself, several for one provider, each under a name, so
// the row is no line of a key the core stores and takes no Replace or
// Remove: a new key goes in through Add key on the API keys line under
// AI model on Details, where this row is drawn too, and the Voice key field
// on Settings chooses it. A link to that field would take the ElevenLabs
// hint past the status hint ceiling.
var VOICE_KEY_CHANGE = "; Add key on the API keys line under AI model stores another key for the Voice key setting";
var VOICE_KEY_STORED = {
    openai: "Jarvis can use the Realtime voice with your OpenAI key" + VOICE_KEY_CHANGE,
    gemini: "Jarvis can use the Gemini Live voice with your Gemini key" + VOICE_KEY_CHANGE,
    elevenlabs: "Jarvis can speak in your ElevenLabs voices with your ElevenLabs key" + VOICE_KEY_CHANGE
};
// The Voice group's key row for OFFERED, the stored keys of the cloud voice
// SETTINGS select (voiceKeys), or null while the account reader could not
// read them: Add key is offered until one is stored.
function voiceKey(offered, settings) {
    var hint = VOICE_KEY_HINTS[cloudSpeech(settings.voiceProvider) ? settings.voiceProvider : "other"];
    if (offered === null) return { tone: "warning", text: "Could not check", hint: hint, action: true };
    return offered.length === 0 ? { tone: "info", text: "No key stored", hint: hint, action: true }
        : { tone: "ok", text: "Key stored", hint: VOICE_KEY_STORED[voiceKeyProvider(settings)], action: false };
}

// The ElevenLabs voices row (the manifest's elevenLabs) from FACTS:
// `provider`, the voice the daemon runs (voiceProvider); `keys`, the
// account reader's stored cloud voice keys, undefined before its answer;
// `account`, the Voice key setting; `answer`, the daemon's setup answer
// (readiness's ANSWER); `voices`, how many voices the daemon offers. No row
// under another voice. With no ElevenLabs key chosen, or a chosen key no
// longer stored, the row states that, and its declared hint says where to
// get, store and choose a key (D075). With one, it follows the
// key's voice list: offered, failed (the Voice step's cause), being read,
// or waiting while another cause holds the Voice step. Only the hints
// that send the user to ElevenLabs API keys name it, the declared one and
// the failed read's, so the row's link draws in those two states alone.
var ELEVENLABS_READY = "[Choose one in the Voice list](page:vgs.jarvis/Settings/voice)";
var ELEVENLABS_READING = "Jarvis is reading the voices of your ElevenLabs key";
var ELEVENLABS_WAITING = "Jarvis reads the voices of your ElevenLabs key once voice setup is done";
function elevenLabsStep(facts) {
    if (facts.provider !== "elevenlabs") return { hidden: true };
    var named = facts.account;
    var chosen = named !== "" && (facts.keys === undefined
        || facts.keys.some(function (key) { return key.provider === "elevenlabs" && key.value === named; }));
    if (!chosen) return { tone: "info", text: named === "" ? "No key chosen" : "Key not stored" };
    if (facts.voices > 0) return { tone: "ok", text: facts.voices === 1 ? "1 voice" : facts.voices + " voices", hint: ELEVENLABS_READY };
    var causes = facts.answer.kind === "answered" ? facts.answer.causes : [];
    if (causes.indexOf("speech=elevenlabs-voice") !== -1) return { tone: "warning", text: "Could not read voices", hint: ELEVENLABS_UNREAD };
    if (facts.answer.kind === "checking" || causes.indexOf("speech=elevenlabs-voices-reading") !== -1)
        return { tone: "info", text: "Reading voices", hint: ELEVENLABS_READING };
    return { tone: "info", text: "Waiting for setup", hint: ELEVENLABS_WAITING };
}

// The voiceRoute reading on Details for SETTING, the Voice provider the
// user chose: what leaves the computer, to whom, and with which key.
var VOICE_ROUTES = {
    auto: { text: "Auto", hint: "Auto chooses between Realtime and Local" },
    local: { text: "Local", hint: "Local keeps your voice and the replies on this computer, and answers fastest" },
    realtime: { text: "Realtime", hint: "Realtime sends your voice and the replies Jarvis lets out to OpenAI, with your OpenAI key" },
    gemini: { text: "Gemini Live", hint: "Gemini Live sends your voice and the replies Jarvis lets out to Google, with your Gemini key" },
    elevenlabs: { text: "ElevenLabs", hint: "ElevenLabs keeps your voice on this computer and sends the replies Jarvis lets out to ElevenLabs, with your ElevenLabs key" }
};
function voiceRoute(setting) {
    if (!Object.prototype.hasOwnProperty.call(VOICE_ROUTES, setting)) throw new Error("jarvis-setup: voice-provider=" + setting);
    var route = VOICE_ROUTES[setting];
    return { tone: "info", text: route.text, hint: route.hint };
}

// The Voice preview row's words for a cloud voice PROVIDER (voiceProvider):
// whose key the preview uses, and that it may cost money.
var PREVIEW_COSTS = {
    realtime: { tone: "info", text: "Uses your OpenAI key", hint: "A preview of the Realtime voice may cost money", action: true },
    gemini: { tone: "info", text: "Uses your Gemini key", hint: "A preview of the Gemini Live voice may cost money", action: true },
    elevenlabs: { tone: "info", text: "Uses your ElevenLabs key", hint: "A preview in an ElevenLabs voice uses credits of your ElevenLabs account", action: true }
};
function previewCost(provider) {
    if (!cloudSpeech(provider)) throw new Error("jarvis-setup: preview-provider=" + provider);
    return PREVIEW_COSTS[provider];
}

// The Agent fleet row (the manifest's setupFleet) for HOME, the home folder
// the setting names or null, and TOOL, the kendex mail tool Home.mailTool
// finds there or null: hidden while no home is chosen, which the home row
// covers, and done once the tool is found; else offering its setup, which the
// core withholds behind the requirement notice while kendex is missing.
function fleetStep(home, tool) {
    if (home === null) return { hidden: true };
    if (tool !== null) return DONE;
    return { tone: "info", text: "Optional", action: true };
}

// The Jarvis session row (the manifest's sessionStart): what the Jarvis
// package's session command answers, in the page's words. Each sentence is
// the owner's (VGS-1439, 2026-10-12; the no-home one, which names its
// Settings path, VGS-1511).
var SESSION_BOOT = "When VGS starts after you sign in, a tmux session starts Jarvis in your selected home folder";
var SESSION_BLOCKS = {
    "no-account": "No session can start without an account: [choose an app as the Account under AI model](page:vgs.jarvis/Settings)",
    "not-app": "No session can start with an API key or a local model: [choose an app as the Account under AI model](page:vgs.jarvis/Settings)",
    "no-home": "No session can start without a home folder: choose one in [Settings > Jarvis > Home folder](page:vgs.jarvis/Settings)",
    "package": "Install or update the Jarvis package in this home folder"
};
// The blocks that wait only on a choice the user has not made yet. The
// session is optional (Start Jarvis at boot is off at first), so these read
// as an optional step; the other blocks are faults to fix.
var SESSION_CHOICES = ["no-account", "not-app", "no-home"];
var SESSION_FAILED = "Jarvis did not start";
// PluginLogic STATUS_HINT_MAX, the longest hint a status row takes.
var SESSION_HINT_MAX = 200;
// The states of a session that lives, which a status read may find.
var SESSION_LIVE = ["running", "starting", "handing-over"];
function sessionLive(state) {
    return SESSION_LIVE.indexOf(state) !== -1;
}
// The package's state and reason, as "state reason", to the row. `detail`
// takes the package's own line, `names` the recorded session's home and
// account, `wanted` the row of the boot setting, and `action` names the
// manifest action the row offers.
var SESSION_ROWS = {
    "off app-off": { tone: "info", text: "Off", hint: "Jarvis is off" },
    "blocked app-off": { tone: "info", text: "Off", hint: "Jarvis is off" },
    "stopped never-started": { wanted: true },
    "stopped stopped": { wanted: true },
    "stopped ended": { wanted: true },
    "starting launching": { tone: "info", text: "Starting", hint: "Jarvis is starting in your selected home folder" },
    "running new-no-record": { tone: "ok", text: "Running", hint: "Jarvis started a new session because none was saved" },
    "running new-history-gone": { tone: "ok", text: "Running", hint: "A new session continued your saved work because the saved conversation is unavailable" },
    "running new-selection-changed": { tone: "ok", text: "Running", hint: "A new session continued your saved work on the selected account" },
    "running resumed": { tone: "ok", text: "Running", names: true },
    "running new-requested": { tone: "ok", text: "Running", names: true },
    "running existing": { tone: "ok", text: "Running", names: true },
    "handing-over succession": { tone: "info", text: "Handing over", hint: "Jarvis is moving its saved work to a new session" },
    "stopping stop-requested": { tone: "info", text: "Stopping", hint: "Jarvis is saving its state and stopping" },
    "blocked name-conflict": { tone: "warning", text: "Cannot start", hint: "Close the other session in the Jarvis terminal or choose its home folder" },
    "blocked record-unreadable": { tone: "warning", text: "Cannot start", hint: "Jarvis cannot read its saved session record" },
    "blocked sign-in-required": { tone: "warning", text: "Cannot start", detail: true },
    "blocked selection-conflict": { tone: "warning", text: "Cannot start", hint: "Changing the home or account restarts Jarvis after the new selection is checked" },
    "blocked tmux-missing": { tone: "warning", text: "Cannot start", hint: "No session can start without tmux: [review all missing or outdated tools under Tools](page:vgs.jarvis/Details)" },
    "blocked app-missing": { tone: "warning", text: "Cannot start", hint: "No session can start, because the app of the selected account is not installed" },
    "failed launch-failed": { tone: "danger", text: "Not started", detail: true, action: "retry" },
    "failed handover-failed": { tone: "danger", text: "Not started", detail: true, action: "retry" }
};
// The setting's two session choices; the first is what the unset value means.
var SESSION_MODES = [{ label: "Resume the last session", value: "resume" }, { label: "Start a new session", value: "new" }];

// The row for RESULT, backend/session-control.js's answer, null before the
// first one and { kind: "failed" } where the helper gave none. WANTED is
// the Start Jarvis at boot setting, which words only a session that does
// not run: a live session reads as it is, whatever the setting.
function sessionStart(wanted, result) {
    if (result === null) return { hidden: true };
    if (result.kind === "blocked") {
        if (!Object.prototype.hasOwnProperty.call(SESSION_BLOCKS, result.block)) throw new Error("jarvis-setup: session=" + result.block);
        return SESSION_CHOICES.indexOf(result.block) !== -1 ? { tone: "info", text: "Optional", hint: SESSION_BLOCKS[result.block] }
            : { tone: "warning", text: "Cannot start", hint: SESSION_BLOCKS[result.block] };
    }
    var failure = { tone: "danger", text: "Not started", hint: SESSION_FAILED, action: "retry" };
    if (result.kind !== "answer") return failure;
    var row = SESSION_ROWS[result.state + " " + result.reason];
    if (row === undefined) return failure;
    var value;
    if (row.wanted) value = wanted ? { tone: "info", text: "Starts at the next boot", hint: SESSION_BOOT, action: "start" }
        : { tone: "info", text: "Not started", hint: "Start Jarvis to continue your work", action: "start" };
    else {
        var hint = row.detail ? (result.detail !== "" ? result.detail : SESSION_FAILED)
            : row.names ? (result.names === null ? "" : "Jarvis runs in " + result.names.home + " with " + result.names.account) : row.hint;
        // The status judge takes a hint of 1 to SESSION_HINT_MAX
        // characters: a recorded session with no names, or with names too
        // long for one, reads by its row text alone.
        value = hint === "" || hint.length > SESSION_HINT_MAX ? { tone: row.tone, text: row.text } : { tone: row.tone, text: row.text, hint: hint };
        if (row.action !== undefined) value.action = row.action;
    }
    // The selection that failed its check, beside the session that stays.
    if (result.unapplied !== undefined) value.lines = [SESSION_BLOCKS[result.unapplied]];
    return value;
}

// The Setup summary SETUP beside SESSION, the Jarvis session row
// (sessionStart). The session is optional, so it never makes Jarvis not
// ready, but a Ready summary names a session the user must fix: the page
// gives one judgement.
var SESSION_FAULTS = {
    warning: "The Jarvis session cannot start: see [Jarvis session under Home on the Details tab](page:vgs.jarvis/Details)",
    danger: "The Jarvis session did not start: see [Jarvis session under Home on the Details tab](page:vgs.jarvis/Details)"
};
function sessionSummary(setup, session) {
    if (setup.tone !== "ok" || !Object.prototype.hasOwnProperty.call(SESSION_FAULTS, session.tone)) return setup;
    var fault = SESSION_FAULTS[session.tone];
    return Object.assign({}, setup, { hint: setup.hint === undefined ? fault : joinedHint([setup.hint, fault]) });
}

// The session choices the page offers: none while the setting is off, so
// the page draws no session field.
function sessionModes(wanted) {
    return wanted ? SESSION_MODES : [];
}

// An optional step's row from VALUE, its reader's state: that state, in
// the info tone that marks a step optional while it is not ok, so Jarvis
// reads ready without it. The browser and input are optional.
function optionalStep(value) {
    return value.tone === "ok" ? value : Object.assign({}, value, { tone: "info" });
}

// The Local voice row from VALUE, setup-local's reading, under PROVIDER,
// the voice the daemon runs (voiceProvider), beside VOICE, the Voice step's
// published value (voiceCheck). The row is a Details reading and offers no
// action: setting up the local voice is the Voice step's Set up local voice
// alone, or a change of the Local voice model setting (LocalTier.qml), so
// the reading's own offer, `action`, never reaches the row. While the Voice
// step offers that setup, whatever the voice, the row is a state of that
// step and never open; a reading that would offer setup, with no hint of
// its own, states why the step asks for it. Else, under a voice that hears
// the user on this computer, the row keeps its reading's tone, and under a
// voice that hears the user elsewhere it is optional.
var LOCAL_VOICE_NEEDED = "The selected voice provider needs the local voice";
function localVoiceStep(value, provider, voice) {
    var reading = noAction(value);
    if (voice.action === "setup") {
        if (value.tone === "ok") return reading;
        var row = { tone: "info", text: value.text };
        var lines = (value.lines || []).concat(value.action === true && value.hint === undefined ? [LOCAL_VOICE_NEEDED] : []);
        if (lines.length > 0) row.lines = lines;
        if (value.hint !== undefined) row.hint = value.hint;
        return row;
    }
    return hearsLocally(provider) ? reading : optionalStep(reading);
}

// The value a setup reader publishes when its check gives no answer, by
// KIND: "failed" for a check that ended in error, "unreadable" for an
// answer that is no status, "timeout" for a check past its deadline.
// ENTRY is the reader's manifest status entry. An entry with a setup
// action, its one action or its named setup action, offers it, and the
// hint names it; an entry without one, a reading such as Local voice,
// states the failure alone. A timeout is no step
// to do: the daemon judges setup without the check, so the row is not
// open under a Ready summary and offers no setup. It says what holds under
// any summary, while the Ready summary's caution (CAUTION) says Jarvis
// answers. It draws no keyed cause, which the reader logs (LocalRuntime.qml).
var CHECK_FAILURES = {
    failed: { text: "Setup check failed", reason: "Jarvis could not check this setup" },
    unreadable: { text: "Setup check returned invalid status", reason: "Jarvis could not read the answer of the setup check" }
};
function checkFailure(kind, entry) {
    var setup = entry.action !== undefined ? entry.action : entry.actions !== undefined ? entry.actions.setup : undefined;
    if (kind === "timeout") {
        var unfinished = { tone: "info", text: "Check did not finish", hint: "Jarvis does not need this check to answer and runs it again after the next setup" };
        return setup === undefined ? unfinished : Object.assign(unfinished, { action: false });
    }
    if (!Object.prototype.hasOwnProperty.call(CHECK_FAILURES, kind)) throw new Error("jarvis-setup: check-failure=" + kind + " unexpected");
    var failure = CHECK_FAILURES[kind];
    if (setup === undefined) return { tone: "warning", text: failure.text, hint: failure.reason };
    return { tone: "warning", text: failure.text,
        hint: sentence(failure.reason) + " Press " + setup.label + " to set it up and check it again.", action: true };
}

// The Local voice setting (`localTier`) and its downloads. WANTED is the
// setting: a tier, or "auto" for PICK, the tier setup-local reads as best
// for this computer. READY is the tier setup left ready, null for none.
function wantedTier(wanted, pick) {
    return wanted === "auto" ? pick : wanted;
}

// The arguments of the setup-local run that a change of the setting to
// WANTED starts, null for none: none while the wanted tier is ready, else
// the wanted tier, or none for the pick, which setup-local installs then.
function tierRun(wanted, pick, ready) {
    if (wantedTier(wanted, pick) === ready) return null;
    return wanted === "auto" ? [] : [wanted];
}

// The setting after a setup run ended, null to keep it: once the run left
// another tier than the wanted one ready, a cancelled pick or the Setup
// button's install of the pick, the setting names that tier, "auto" for the
// pick, so the page shows what is installed. A run that left none keeps it:
// READY null is then returned.
function tierAfterRun(wanted, pick, ready) {
    if (wantedTier(wanted, pick) === ready) return null;
    return ready === pick ? "auto" : ready;
}
