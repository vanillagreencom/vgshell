.pragma library
.import qs.Commons 1.0 as Commons

// The word of a required step still to do, which the bar widget tells from
// the step (WidgetView.unconfiguredText).
var TO_DO = "To do";

// Which setup step Jarvis offers while a command its setup needs is missing,
// pure so scripts/test-jarvis-setup-gate.js runs it under node. MISSING is
// the requirements capability's list: the plugin's declared commands the
// core's last scan did not find. A missing command is offered as Install on
// its own status row. A required step offers the core's tools action.

// The value a setup reader publishes: its probe's VALUE while every command
// of REQUIRES is found, else a warning naming the missing commands.
// Set up dictation stays
// offered: voxtype is the program the core's dictation setup gets ready.
function setupValue(value, requires, missing, required) {
    var lacking = requires.filter(function (command) { return missing.indexOf(command) !== -1; });
    if (lacking.length === 0) return value;
    var withheld = { tone: "warning", text: "Needs " + lacking.join(" and "),
        hint: "Review missing or outdated tools in [Setup](page:vgs.jarvis/Setup)" };
    if (value.action === "dictation") { withheld.action = "dictation"; delete withheld.hint; }
    else if (required === true) withheld.action = "tools";
    else if (typeof value.action !== "string") withheld.action = false;
    return withheld;
}

// Only required plugin tools divert a named step to Setup's tools action.
// An optional tool keeps the declared TUI action: its launcher opens the
// requirement notice for that script. Dictation gets voxtype ready itself.
var ACTION_REQUIRES = { dictation: ["voxtype"] };
function actionRequires(value, manifest) {
    if (typeof value.action !== "string") return [];
    if (Object.prototype.hasOwnProperty.call(ACTION_REQUIRES, value.action)) return ACTION_REQUIRES[value.action];
    var action = manifest.status.setupVoice.actions[value.action];
    return action === undefined || action.tui === undefined ? [] : manifest.tui[action.tui].requires.filter(function (command) {
        return manifest.requirements.some(function (requirement) { return requirement.name === command && !requirement.optional; });
    });
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
    "brain=unselected": "Choose an AI model in [AI model](page:vgs.jarvis/Settings/brain)",
    "brain=account-unavailable": "The chosen account or its key is unavailable: [add a key or sign in](page:vgs.jarvis/Setup/keyStore)",
    "brain=model-required": "Choose a model in [Model](page:vgs.jarvis/Settings/model)",
    "brain=models-reading": "Jarvis is reading the local server model list",
    "brain=models-unavailable": "Check the local server, then [choose a model](page:vgs.jarvis/Settings) under AI model and press Talk to try again",
    "brain=model-unavailable": "The local server does not offer this model: [choose another model](page:vgs.jarvis/Settings) under AI model",
    "brain=signed-out": "Sign in to the chosen AI app, then [choose it under AI model](page:vgs.jarvis/Settings)",
    "brain=pi-update": "Jarvis needs Pi 1.1.0 or later: [review all missing or outdated tools under Optional tools on the Setup tab](page:vgs.jarvis/Setup), or choose another app under AI model",
    "brain=accounts-unreadable": "Jarvis could not read your accounts. Add a key with Add key to use an AI model.",
    "speech=live-account-unselected": "[Add a provider key with API keys on the Setup tab](page:vgs.jarvis/Setup/keyStore): OpenAI for Realtime, Gemini for Gemini Live or ElevenLabs for ElevenLabs",
    "speech=live-account-unreadable": "Jarvis could not read your voice key: use [Accounts with Account search on the Setup tab](page:vgs.jarvis/Setup/accountSearch) to check it",
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
    "speech=dictation-absent": { tone: "warning", text: TO_DO, hint: "Set up dictation so the local voice can hear you", action: "dictation" },
    "speech=dictation-failed": { tone: "warning", text: TO_DO, hint: "Set up dictation again", action: "dictation" },
    "speech=dictation-elsewhere": { tone: "warning", text: "Another voxtype runs", hint: "Stop the other voxtype beside [Other dictation service in Voice Setup](page:vgs.voice/Setup)" },
    "speech=dictation-device": { tone: "warning", text: "Dictation uses another microphone", hint: "The local voice hears the system default microphone: choose it with [Configure in Settings > Voice](page:vgs.voice/Settings)" }
};
// Causes whose step the voice setup action cannot complete: the user
// changes a setting, adds a key or fixes the ElevenLabs key instead.
function setupActs(cause) {
    return cause.indexOf("speech=live-") !== 0 && cause.indexOf("speech=elevenlabs-") !== 0 && cause !== "speech=always-local-voice";
}
var STEP_TODO = { brain: "Add a key or sign in, then [choose an AI model](page:vgs.jarvis/Settings) under AI model" };
// The path reader resolves the selected folder even when its contents are
// refused. Never use a previously selected folder while that read runs.
function homeReference(name, home, suffix) {
    return home && home.kind === "ready" ? Commons.PageReference.fileReference(name, home.path + suffix)
        : "[Home folder](page:vgs.jarvis/Settings/home)";
}
// The daemon's home refusal names the change and, for editable user files,
// the core file action. The service supplies the selected folder's path.
var HOME_TODO = {
    "home=link": { hint: "A file in your Home folder is a shortcut to another place. Jarvis does not follow shortcuts. Replace it with the real file, or choose another [Home folder](page:vgs.jarvis/Settings/home)." },
    "home=path": { hint: "Jarvis cannot use this folder: choose a [Home folder](page:vgs.jarvis/Settings/home) inside your own home directory" },
    "home=text": { hint: "Your instructions are not plain text: save them as plain text", action: "agents" },
    "home=package": {},
    "guidance=home-skills-too-large": { text: "Too many skills", hint: "A skill set exceeds 256 entries: remove the skills you do not use", action: "skills",
        info: "Jarvis lists up to 256 entries in a skill folder. This limit stops an unexpectedly large folder from making Jarvis stop responding. Remove unused skills, then try again." }
};
var HOME_STEP_TODO = "Check that you can open and change the folder, or choose another [Home folder](page:vgs.jarvis/Settings/home)";
var HOME_FILES = { agents: "/AGENTS.md", skills: "/skills/", memory: "/memory/MEMORY.md", persona: "/.agents/skills/jarvis/persona.md", folder: "/", state: "/state/" };
function homeStep(cause, home, repair) {
    if (cause === "home=package") return homePackageStep(repair);
    var value = Object.assign({ tone: "warning", text: TO_DO },
        Object.prototype.hasOwnProperty.call(HOME_TODO, cause) ? HOME_TODO[cause] : { hint: HOME_STEP_TODO });
    if (value.action !== undefined) {
        if (home.kind !== "ready") return { tone: "warning", text: TO_DO, hint: home.kind === "reading"
            ? "Jarvis is finding the file in your [Home folder](page:vgs.jarvis/Settings/home)"
            : "Jarvis could not find the file. Check your [Home folder in Settings](page:vgs.jarvis/Settings/home)." };
        value.file = home.path + HOME_FILES[value.action];
    }
    if (home.kind === "ready") {
        if (cause === "home=text") value.hint = homeReference("AGENTS.md", home, "/AGENTS.md") + " is not plain text: save it as plain text";
        if (cause === "guidance=home-skills-too-large") value.info += " Check the " + homeReference("base skills", home, "/.agents/skills/")
            + " and " + homeReference("own skills", home, "/skills/own/") + ".";
        if (cause === "home=link") value.hint = "Replace the shortcut in your " + homeReference("Home folder", home, "/") + " with the real file";
        if (cause !== "home=text" && cause !== "home=link" && cause !== "guidance=home-skills-too-large")
            value.hint = "Check that you can open and change your " + homeReference("Home folder", home, "/");
    }
    return value;
}
// Home.js judges the writer. VGS restores its install, and Kendex restores
// the Home it already owns. Neither route transfers ownership.
function homePackageStep(home) {
    if (home === undefined || home.kind !== "ready") return { tone: "warning", text: TO_DO, hint: home !== undefined && home.kind === "reading"
        ? "Jarvis is checking how to repair your Home folder"
        : "Jarvis could not check the repair route. Choose another [Home folder in Settings](page:vgs.jarvis/Settings/home)." };
    return { tone: "warning", text: TO_DO, action: "repair", hint: home.repair.kind === "install"
        ? home.repair.installPlan !== undefined && home.repair.installPlan.kind === "by-hand"
            ? "The VGS install is missing Jarvis files. Repair shows the required steps. Or choose another [Home folder](page:vgs.jarvis/Settings/home)."
            : "The VGS install is missing Jarvis files. Repair restores VGS. Or choose another [Home folder](page:vgs.jarvis/Settings/home)."
        : "Repair restores missing Home files with Kendex. Or choose another [Home folder](page:vgs.jarvis/Settings/home)." };
}
// The normal Home check owns Done or To do. A failed repair adds its cause
// without replacing that check or removing the route to another folder.
function homeRepairResult(value, home) {
    if (home.kind !== "ready" || home.repair === undefined || home.repair.lastRepair === null || home.repair.lastRepair.kind !== "failed") return value;
    var failed = home.repair.lastRepair;
    // self repair exits 69 after showing a by-hand notice. It attempted no
    // reinstall, so the step keeps its required-steps hint without a failure.
    if (failed.cause === "install-failed" && failed.code === 69 && home.repair.installPlan !== undefined && home.repair.installPlan.kind === "by-hand") return value;
    var reason = failed.cause === "refresh-failed" ? "Kendex refresh failed."
        : failed.cause === "install-failed" ? "VGS install repair failed."
        : failed.cause === "timeout" ? "Repair timed out."
        : failed.cause === "cancelled" ? "Repair was cancelled."
        : "The repair did not finish.";
    return Object.assign({}, value, { hint: joinedHint((value.hint === undefined ? [] : [value.hint]).concat([reason + " Check the repair window."])) });
}
var HOME_READY = { tone: "ok", text: "Done" };
// The home texts over their size budget (JarvisProtocol SETUP_CAUTIONS),
// by the name the Home folder step gives each. Jarvis loads each whole and
// answers, so the summary stays Ready and the step Done, with an info that
// names the texts. The caution goes on the step, not the summary, whose hint
// a session fault and a shell caution already share.
// backend/Guidance.js owns the byte budgets; the suite checks these copies.
var OVER_BUDGET = {
    "guidance=persona-over-budget": { name: "persona.md", bytes: 3072, action: "persona" },
    "guidance=agents-over-budget": { name: "AGENTS.md", bytes: 8192, action: "agents" },
    "guidance=skills-over-budget": { name: "the skill list", bytes: 8192, action: "skills" },
    "guidance=memory-over-budget": { name: "memory/MEMORY.md", bytes: 4096, action: "memory" },
    "guidance=start-over-budget": { name: "the start text", bytes: 32768, action: "folder" }
};
function numberText(value) {
    return String(value).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}
function messageLimit(maximum) {
    return { maximum: maximum,
        info: "A message can hold up to " + numberText(maximum) + " characters. This keeps each message within the size Jarvis can send to the AI model. Send a longer request as separate messages. Control characters, such as line breaks and tabs, are not supported." };
}
var START_REASON = "Each answering AI model gets this text at the start of every conversation. Longer text costs more and leaves less room for your conversation. Jarvis still loads it whole.";
function budgetInfo(causes, home) {
    var facts = causes.map(function (cause) {
        var budget = OVER_BUDGET[cause];
        return homeReference(budget.name, home, HOME_FILES[budget.action]) + ": "
            + numberText(budget.bytes) + " bytes.";
    });
    return "Budgets: " + facts.join(" ") + " " + START_REASON;
}
var START_FILES = {
    "home/persona": { name: "Persona", action: "persona" },
    "home/AGENTS.md": { name: "Instructions", action: "agents" },
    "home/skills": { name: "Skills", action: "skills" },
    "home/MEMORY.md": { name: "Memory index", action: "memory" },
    "home/state": { name: "Working folder", action: "state" }
};
function startTextInfo(layers, causes, home) {
    var over = causes.filter(function (cause) { return Object.prototype.hasOwnProperty.call(OVER_BUDGET, cause); });
    var reason = over.length > 0 ? budgetInfo(over, home)
        : "Tokens are small pieces of words. These counts are estimates. " + START_REASON;
    return reason + " Open: " + layers.map(function (layer) {
        var file = START_FILES[layer.layer];
        return homeReference(file.name, home, HOME_FILES[file.action]);
    }).join(", ") + ".";
}
// The Personality row from SHOWN, the daemon's personality message, and
// CAUSES, its last answer's, an optional Setup step: the section as the
// row's hint, Done with Edit; or what keeps it from showing, Not available
// (`available: false`) where Edit cannot help, its hint saying what does.
// The hint holds at most PluginLogic's STATUS_HINT_MAX of 200 characters, so
// a longer or cut section ends in "…". An AGENTS.md over its budget adds a
// line and keeps the row's reading: Jarvis still reads it whole.
function personalityRow(shown, causes, home) {
    var joined = shown.kind === "section" ? shown.lines.join(" ") : "";
    var cut = joined.length > 200 || shown.more === true;
    var value = shown.kind === "section" ? { tone: "ok", text: "Set", hint: cut ? joined.slice(0, 199).trimEnd() + "…" : joined, action: true }
        : shown.kind === "none" ? { tone: "info", text: "No home folder", available: false,
            hint: "Choose where to keep your instructions with [Home folder](page:vgs.jarvis/Settings/home)" }
        : shown.kind === "missing" ? { tone: "info", text: "No Personality section", action: true,
            hint: "Add a Personality section to " + homeReference("AGENTS.md", home, "/AGENTS.md") + " with Edit",
            info: "Press Edit. Add the heading ## Personality on its own line. Write how Jarvis should talk below it." }
        : { tone: "warning", text: "Instructions cannot be read", available: false, hint: "Check " + homeReference("AGENTS.md", home, "/AGENTS.md") };
    if ((shown.kind === "section" || shown.kind === "missing") && causes.indexOf("guidance=agents-over-budget") !== -1)
        return Object.assign({}, value, { lines: ["Over the " + numberText(OVER_BUDGET["guidance=agents-over-budget"].bytes) + "-byte budget"],
            info: (value.info === undefined ? "" : value.info + " ") + budgetInfo(["guidance=agents-over-budget"], home) });
    return value;
}

// The Home folder step over CAUSES, the over-budget causes of an answer
// whose home step is done: Done, with each budget in its info and an open
// action on the chosen file, or the folder when several exceed a budget.
function homeDone(causes, home) {
    var over = causes.filter(function (cause) { return Object.prototype.hasOwnProperty.call(OVER_BUDGET, cause); });
    if (over.length === 0) return home && home.kind === "ready" ? Object.assign({}, HOME_READY, { hint: homeReference("Home folder", home, "/") }) : HOME_READY;
    var value = { tone: "ok", text: "Done", hint: "Text exceeds its size budget; Jarvis still loads it whole", info: budgetInfo(over, home) };
    if (home && home.kind === "ready") {
        value.action = over.length === 1 ? OVER_BUDGET[over[0]].action : "folder";
        value.file = home.path + HOME_FILES[value.action];
    }
    return value;
}
var HOME_UNCHECKED = { tone: "warning", text: "Not checked" };
var DONE = { tone: "ok", text: "Done", action: false };
// Voice setup uses Session's check result, which only the local wake detector
// supplies; a cloud voice keeps a check that ended (`kept`), so a provider
// change on the same microphone keeps its result. A step that names its own
// action, such as Set up dictation, keeps it. TALK is the sentence that says
// how to talk now (talkHint).
function voiceCheck(value, check, talk) {
    if (value.tone !== "ok" || check === null || check.kind === "unavailable" || check.kind === "kept") return value.action === true
        ? Object.assign({}, value, { action: "setup" }) : typeof value.action === "string" ? value : noAction(value);
    if (check.kind === "waiting" || check.kind === "recording")
        return { tone: "info", text: "Say Hey Jarvis", hint: "The microphone is open for three seconds",
            info: "This short test checks whether Jarvis can hear Hey Jarvis. The microphone closes after three seconds. Press Check microphone to try again." };
    if (check.kind === "finishing") return { tone: "info", text: "Checking" };
    if (check.kind === "failed") return { tone: "danger", text: "Check failed",
        hint: "Jarvis could not check the microphone: press Check microphone to try again", action: "check" };
    if (check.kind === "done") {
        if (check.result === "ready") return { tone: "ok", text: "Microphone check passed", hint: talk, action: "check" };
        // Only the local voice checks, and it hears the system default.
        if (check.result === "silent") return { tone: "warning", text: "Muted or silent", hint: "The default microphone is muted or sends silence: [check it in System > Sound](page:vgs.sound)", action: "check" };
        return { tone: "warning", text: "Not heard", hint: "Jarvis did not hear Hey Jarvis: try again closer or in a quieter room", action: "check" };
    }
    // A changed device asks for the check again, and says why.
    if (check.kind === "again") return { tone: "info", text: "Check again",
        hint: "Jarvis now hears another microphone: press Check microphone, then say Hey Jarvis", action: "check" };
    return { tone: "info", text: "Not checked", hint: "Press Check microphone, then say Hey Jarvis", action: "check" };
}

// The sentence that says how to talk to Jarvis now, for MODE, the Talk mode
// setting, and TALK, its key as people read it, or null while no key is set:
// the one sentence the Voice step, the bar and the console say it with.
function talkHint(mode, talk) {
    if (talk === null) return (mode === "always" ? "Say Hey Jarvis, or set" : "Set") + " the [Talk key](page:vgs.jarvis/Settings) in the Keys section";
    if (mode === "hold") return "Tap or hold " + talk + ", then speak";
    if (mode === "toggle") return "Press " + talk + ", then speak";
    return "Say Hey Jarvis, or press " + talk;
}

// Each cause a failed local voice setup records (setup-local
// local-setup-failed.json), by what the user does next: the Voice step's
// hint, which links the log that holds the cause.
var LOCAL_FAILURES = {
    busy: "The local voice was in use, so the new model did not install",
    download: "The download stopped: check your network, then try again",
    disk: "The disk is full: free some space, then try again",
    probe: "The voice did not pass its test on this computer: choose a model that runs on any computer",
    unavailable: "This model needs an NVIDIA graphics card: choose a model that runs on any computer",
    refused: "This model is no longer offered: choose another model",
    cancelled: "The setup was cancelled: set it up again when you are ready",
    other: "The setup stopped before it finished: try again"
};
var LOCAL_SETUP_INFO = "The download holds the speech models that run on this computer, so your speech stays here.";

// The Voice step as the page shows it, from VALUE, the step readiness,
// voiceCheck and setupValue made, and FACTS: `provider` (voiceProvider),
// `voice`, that provider as AccountProviders.cloudVoice gives it, null for
// Local, `causes`, the daemon's last setup causes, `talk` (talkHint), `keys`, how
// many keys of the provider are stored, `size`, the download size of the
// local voice setup-local picks or "", and `failure`, the last failed local
// setup of the tier the user wants (localFailure) or null. A done step names
// the voice and how to talk; a cloud voice without its key names the key and
// offers Add a key; a voice that hears on this computer whose wanted tier's
// setup failed names that tier and why, and offers Set up local voice, also
// while the tier before it still serves; local voice not set up names the
// download and offers the same, with a cloud voice as the other path.
function voiceStep(value, facts) {
    var voice = facts.voice;
    var failed = facts.failure !== null && hearsLocally(facts.provider);
    if (value.tone === "ok" && value.text === "Done" && !failed) return { tone: "ok", text: voice === null ? "Local voice" : voice.product, hint: facts.talk };
    var has = function (cause) { return facts.causes.indexOf(cause) !== -1; };
    // Only a cloud voice takes a key, so only its key causes name one.
    if (voice !== null && has("speech=live-key-refused"))
        return { tone: "warning", text: KEY_REFUSED, hint: voice.product + " refused your " + voice.company + " key: add a new one", action: "key" };
    if (voice !== null && (has("speech=live-key-required") || has("speech=live-account-unselected")))
        return facts.keys > 0 ? { tone: "warning", text: "No key chosen", hint: "Choose your " + voice.company + " key in [Voice key](page:vgs.jarvis/Settings/voiceAccount), or add one", action: "key" }
            : { tone: "warning", text: "No " + voice.company + " key", hint: voice.product + " needs your " + voice.company + " key", action: "key" };
    // A step another action mends, such as a missing tool, keeps it.
    if (failed && (value.action === "setup" || value.tone === "ok")) {
        var reason = Object.prototype.hasOwnProperty.call(LOCAL_FAILURES, facts.failure.cause) ? LOCAL_FAILURES[facts.failure.cause] : LOCAL_FAILURES.other;
        return { tone: "warning", text: facts.failure.text, action: "setup", info: LOCAL_SETUP_INFO,
            hint: reason + ". " + Commons.PageReference.fileReference("Open the setup log", facts.failure.log) + "." };
    }
    if (value.action !== "setup" || value.tone === "ok") return value;
    if (has("speech=local-not-set-up"))
        return { tone: "warning", text: "Not set up", action: "setup", info: LOCAL_SETUP_INFO,
            hint: "Downloads the local voice" + (facts.size === "" ? "" : ", about " + facts.size) + ". Or [use a cloud voice](page:vgs.jarvis/Settings/voiceProvider)." };
    return value;
}

// The last failed local voice setup in READING, setup-local's status
// answer, as { cause, log, text }, while it set up WANTED, the tier the
// Local voice model setting asks for, and READY, the tier ready (null for
// none), is another; else null. A setup of a tier the user has since left,
// or one a later run set up, is no step.
function localFailure(reading, wanted, ready) {
    if (reading === null || typeof reading !== "object" || typeof reading.failure !== "object" || reading.failure === null) return null;
    var failure = reading.failure;
    if (typeof failure.cause !== "string" || typeof failure.log !== "string" || typeof failure.text !== "string") return null;
    if (failure.tier !== wanted || ready === wanted) return null;
    return { cause: failure.cause, log: failure.log, text: failure.text };
}

// Whether the user's choice on the Jarvis page of AFTER as the Voice
// provider, in place of BEFORE, starts the local voice's download: a voice
// that hears on this computer in place of one that does not, while
// READING, LocalTier's last read, has no tier ready.
function localVoiceChosen(before, after, reading) {
    return reading !== null && reading.ready === null && hearsLocally(after) && !hearsLocally(before);
}

// The one window the user's choice on the Jarvis page of AFTER as the
// Voice provider, in place of BEFORE, opens: "add-voice-key" for a cloud
// voice with none of its keys among KEYS (the account reader's voice keys,
// undefined before its first read, which opens nothing), VOICE being AFTER
// as AccountProviders.cloudVoice gives it, null for Local, else
// "setup-local" when localVoiceChosen holds over READING, else null. One
// choice opens one window: ElevenLabs with no tier ready and no key opens
// Add a key, and the local download then stands as the Voice step's action.
function providerWindow(before, after, reading, keys, voice) {
    if (voice !== null && keys !== undefined && voiceKeys(keys, voice).length === 0) return "add-voice-key";
    return localVoiceChosen(before, after, reading) ? "setup-local" : null;
}
var CHECKING = { tone: "info", text: "Checking", action: false };
var LOADING = { tone: "info", text: "Loading", action: false };
// The local voice while a setup replaces its model: the daemon closed the
// sidecar for it (ChainedEngine.localSetup) and starts it once the setup
// window closes.
var SETTING_UP = { tone: "info", text: "Setting up", action: false };
// The Voice step's word while the cloud voice's provider refused its key,
// which the bar widget tells from the step (WidgetView.unconfiguredText).
var KEY_REFUSED = "Key refused";
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
    return { title: problem.title, message: sentence(problem.action), tone: "danger", icon: "vgs-letter-j" };
}
function muteRefusedNotice(cause) {
    return { title: "Jarvis mute not saved", message: "Mute request could not be saved: " + startCause(cause).title + ".",
        tone: "danger", icon: "vgs-letter-j" };
}
// The installed voice stays verified. Reinstalling it cannot free memory.
var MEMORY = {
    "speech=local-memory-insufficient": { tone: "warning", text: "Not enough memory",
        hint: "Close other apps, then turn Jarvis off and on in [Settings](page:vgs.jarvis/Settings)", action: false },
    "speech=local-memory-unavailable": { tone: "warning", text: "Memory check failed",
        hint: "Turn Jarvis off and on in [Settings](page:vgs.jarvis/Settings)", action: false }
};
// A required step once the daemon stopped: no check runs, none is offered.
var UNCHECKED = { tone: "warning", text: "Not checked", action: false,
    hint: "Jarvis stopped, so it could not check this. Turn Jarvis off and on in [Settings](page:vgs.jarvis/Settings)." };
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

// The AI model step once done, VALUE, names the account Jarvis asks, its
// label among CHOICES, the `brains` offers, for BRAIN, the setting; a step
// not done, or an account no offer names, is VALUE as it is.
function modelDone(value, choices, brain) {
    if (value.tone !== "ok" || !Array.isArray(choices)) return value;
    var chosen = choices.find(function (choice) { return choice.value === brain; });
    return chosen === undefined ? value : Object.assign({}, value, { text: chosen.label });
}

// The summary and required step values for ANSWER: { kind: "checking" }
// while the daemon has not answered, { kind: "stopped" } once it stopped
// for good, { kind: "problem", cause } after a failed start, or
// { kind: "answered", causes } from its status, as { setup, setupHome,
// setupVoice, setupModel }. No value holds a keyed cause: the service
// log keeps it.
function readiness(answer, home, repair) {
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
            setupHome: homeDone(answer.causes, home), setupVoice: DONE, setupModel: noAction(DONE) };
        var open = [];
        blocking.forEach(function (cause) {
            var step = cause.slice(0, cause.indexOf("="));
            if (!Object.prototype.hasOwnProperty.call(REQUIRED, step)) throw new Error("jarvis-setup: cause=" + cause + " names no step");
            var name = STEP_NAMES[REQUIRED[step]];
            if (open.indexOf(name) === -1) open.push(name);
            if (REQUIRED[step] === "setupHome") {
                out.setupHome = homeStep(cause, home, repair);
                return;
            }
            // ElevenLabs's voices are being read: the voice is chosen once
            // they answer.
            if (cause === "speech=local-loading" || cause === "speech=dictation-starting" || cause === "speech=elevenlabs-voices-reading"
                    || cause === "speech=local-setting-up") {
                out.setupVoice = cause === "speech=local-setting-up" ? SETTING_UP : LOADING;
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
            var text = cause === "speech=local-ready-timeout" ? TIMED_OUT : TO_DO;
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

// The provider a Voice provider stored as "auto" before VGS-1953 becomes,
// the migration the service runs on its first read of SETTINGS (D107):
// Realtime while the Voice key setting names a key and Talk mode is not
// Always, which listens on this computer, else Local. Auto promised
// Realtime once an OpenAI key was stored. The rewrite reads only the
// settings file, so it never waits on the account probe: a key's id does
// not tell its provider, and a Gemini or ElevenLabs key named under Auto
// leaves Realtime asking for an OpenAI key, which the daemon never sends
// another provider's key to (ChainedEngine voiceKey).
function autoVoiceProvider(settings) {
    return settings.mode !== "always" && settings.voiceAccount !== "" ? "realtime" : "local";
}

// The Voice key choices from KEYS, the account reader's stored cloud voice
// keys, for VOICE, the selected voice as AccountProviders.cloudVoice gives
// it: the keys of its provider, none for Local, which takes no key.
function voiceKeys(keys, voice) {
    return keys.filter(function (key) { return voice !== null && key.provider === voice.provider; })
        .map(function (key) { return { value: key.value, label: key.label }; });
}

// The key Jarvis writes for the user from KEYS, or null to write none, for
// VOICE (voiceKeys) and NAMED, the key the Voice key setting names:
// while a cloud voice is chosen, its sole stored key, while the Voice key
// setting names none or a stored key of another cloud voice, as after a
// change of Voice provider; and "" for such a key of another voice while
// the chosen voice has no sole key, so the field reads Choose a key, never
// an unavailable key. Under Local, which shows no Voice key, nothing is
// written, so a Gemini key chosen before survives a visit to Local; a
// named key that is not stored, such as a locked one, stays too.
function voiceChoice(keys, voice, named) {
    if (voice === null) return null;
    var offered = voiceKeys(keys, voice);
    var other = named !== "" && keys.some(function (key) { return key.value === named && key.provider !== voice.provider; });
    if (offered.length === 1 && (named === "" || other)) return offered[0].value;
    return other ? "" : null;
}

// The key a finished Add a key stored, which Jarvis then selects: a key of
// the selected cloud voice VOICE (voiceKeys) in KEYS that BEFORE, the keys
// read before that run, did not hold; null for none.
function voiceAdded(before, keys, voice) {
    var held = before === undefined ? [] : before.map(function (key) { return key.value; });
    var added = voiceKeys(keys, voice).filter(function (key) { return held.indexOf(key.value) === -1; });
    return added.length === 1 ? added[0].value : null;
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
// user chose, and VOICE, that provider as AccountProviders.cloudVoice gives
// it, null for Local: the voice's name, then what leaves the computer, to
// whom, and with which key.
var VOICE_ROUTES = {
    local: "Local keeps your voice and the replies on this computer, and answers fastest",
    realtime: "OpenAI Realtime sends your voice and the replies Jarvis lets out to OpenAI, with your OpenAI key",
    gemini: "Gemini Live sends your voice and the replies Jarvis lets out to Google, with your Gemini key",
    elevenlabs: "ElevenLabs keeps your voice on this computer and sends the replies Jarvis lets out to ElevenLabs, with your ElevenLabs key"
};
function voiceRoute(setting, voice) {
    if (!Object.prototype.hasOwnProperty.call(VOICE_ROUTES, setting)) throw new Error("jarvis-setup: voice-provider=" + setting);
    return { tone: "info", text: voice === null ? "Local" : voice.product, hint: VOICE_ROUTES[setting] };
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
// the owner's (VGS-1439, 2026-10-12; the no-home one, which links the Home
// folder field as the Personality row does and leaves that row's badge the
// one place the Home group says no folder is chosen, VGS-1785).
var SESSION_BOOT = "When VGS starts after you sign in, a tmux session starts Jarvis in your selected home folder";
// Each block of session-control.js, by its row: { text, hint, action },
// `action` the row's action, absent where the hint's link is the way on.
// A home Kendex installed lacks its session program until Repair restores
// it; one VGS laid out ships none (Home.layout), so the row says so and
// that the voice works without it, and links the Home folder for a Kendex
// home. A command that ran outside its contract reads again on Retry. A
// way to the program Jarvis cannot follow is the Home folder's to fix.
var SESSION_BLOCKS = {
    "no-account": { text: "Optional", hint: "No session can start without an account: [choose an app as the Account under AI model](page:vgs.jarvis/Settings/brain)" },
    "not-app": { text: "Optional", hint: "No session can start with an API key or a local model: [choose an app as the Account under AI model](page:vgs.jarvis/Settings/brain)" },
    "no-home": { text: "Optional", hint: "No session can start until [Home folder](page:vgs.jarvis/Settings/home) sets a folder" },
    "package": { text: "Cannot start", hint: "This home folder's Jarvis package has no session program. Repair restores it with Kendex.", action: "repair" },
    "vgs-package": { text: "Not offered in this home folder", hint: "VGS made this Home folder without the Jarvis session program. Voice Jarvis works without it. [Choose a Kendex Jarvis home](page:vgs.jarvis/Settings/home)." },
    "unread": { text: "Cannot start", hint: "The Jarvis session program did not answer as expected. Try again.", action: "retry" },
    "home-link": { text: "Cannot start", hint: HOME_TODO["home=link"].hint },
    "home-kind": { text: "Cannot start", hint: HOME_STEP_TODO },
    "home-unreadable": { text: "Cannot start", hint: HOME_STEP_TODO }
};
// The blocks that wait only on a choice the user has not made yet, or that
// the home cannot offer: the session is optional (Start Jarvis at boot is
// off at first), so these read in the info tone; the other blocks are
// faults to fix, which the bar names (sessionSummary).
var SESSION_CHOICES = ["no-account", "not-app", "no-home", "vgs-package"];
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
    "starting resuming": { tone: "info", text: "Resuming", hint: "Jarvis is resuming its work from before the restart" },
    "running new-no-record": { tone: "ok", text: "Running", hint: "Jarvis started a new session because none was saved" },
    "running new-history-gone": { tone: "ok", text: "Running", hint: "A new session continued your saved work because the saved conversation is unavailable" },
    "running new-selection-changed": { tone: "ok", text: "Running", hint: "A new session continued your saved work on the selected account" },
    "running resumed": { tone: "ok", text: "Running", names: true },
    "running restart-resumed": { tone: "ok", text: "Running", names: true },
    "running new-requested": { tone: "ok", text: "Running", names: true },
    "running existing": { tone: "ok", text: "Running", names: true },
    "handing-over succession": { tone: "info", text: "Handing over", hint: "Jarvis is moving its saved work to a new session" },
    "stopping stop-requested": { tone: "info", text: "Stopping", hint: "Jarvis is saving its state and stopping" },
    "blocked name-conflict": { tone: "warning", text: "Cannot start", hint: "Close the other session in the Jarvis terminal or choose its home folder" },
    "blocked record-unreadable": { tone: "warning", text: "Cannot start", hint: "Jarvis cannot read its saved session record" },
    "blocked sign-in-required": { tone: "warning", text: "Cannot start", detail: true },
    "blocked selection-conflict": { tone: "warning", text: "Cannot start", hint: "Changing the home or account restarts Jarvis after the new selection is checked" },
    "blocked tmux-missing": { tone: "warning", text: "Cannot start", hint: "No session can start without tmux: [review all missing or outdated tools under Optional tools on the Setup tab](page:vgs.jarvis/Setup)" },
    "blocked app-missing": { tone: "warning", text: "Cannot start", hint: "No session can start, because the app of the selected account is not installed" },
    "blocked trust-required": { tone: "warning", text: "Cannot start", detail: true, action: "retry" },
    "failed launch-failed": { tone: "danger", text: "Not started", detail: true, action: "retry" },
    "failed handover-failed": { tone: "danger", text: "Not started", detail: true, action: "retry" }
};
// The setting's two session choices; the first is what the unset value means.
var SESSION_MODES = [{ label: "Resume the last session", value: "resume" }, { label: "Start a new session", value: "new" }];
// The row while the package holds a session saved before a machine restart
// that the user can resume by hand (sessionOffer).
var SESSION_RESUME = { tone: "info", text: "Saved before the restart", hint: "Resume Jarvis from before the restart", action: "resume" };
// The row's line while the offer stands after the package did not answer
// Do not resume (`dismiss`): the record and the offer stay. A line draws as
// a badge, which cuts a long one, so it names the fact alone.
var SESSION_NOT_DISMISSED = "Do not resume was not saved";
// The states in which the Resume offer stands: no session runs, and none
// is turned off, stopping or blocked.
var SESSION_OFFERED = ["stopped", "failed"];

// "HH:MM", the local time of ISO, an ISO 8601 time session-control.js
// accepted, as the lock screen's clock writes it.
function sessionClock(iso) {
    var at = new Date(iso);
    var two = function (n) { return (n < 10 ? "0" : "") + n; };
    return two(at.getHours()) + ":" + two(at.getMinutes());
}

// The reasons of a live session that is the resume of the record saved
// before a machine restart, which only the package's resume worker writes:
// `resuming` until the delegate step's outcome is written, then
// `restart-resumed`. A session `start` started beside the record carries
// neither: `resumed` is a start in mode resume that found its saved
// conversation, and says nothing of the record.
var SESSION_RESUME_REASONS = ["resuming", "restart-resumed"];

// Whether RESULT reads a live session that is its record's resume.
function sessionResumeLive(result) {
    return result !== null && result.kind === "answer" && result.restart !== undefined
        && sessionLive(result.state) && SESSION_RESUME_REASONS.indexOf(result.reason) !== -1;
}

// Whether the resume of RESULT's record saved before a machine restart
// started: the live session is that resume (sessionResumeLive), or no
// session lives and a step is past pending, a resume that ended. A session
// that lives beside the record is not its resume, whatever its steps read,
// and a resume the package refused or that ended before its first step
// leaves every step pending. The one answer the offer, the steps the
// widget shows and the reads of a resume's steps take.
function sessionResumeStarted(result) {
    if (result === null || result.kind !== "answer" || result.restart === undefined) return false;
    if (sessionLive(result.state)) return sessionResumeLive(result);
    return result.restart.steps.some(function (step) { return step.outcome !== "pending"; });
}

// Whether RESULT, session-control.js's answer, offers the Resume of the
// session saved before a machine restart. WANTED is Start Jarvis at boot,
// whose boot build resumes it by itself; ASKED is true while a Resume or a
// Do not resume asked for has no answer yet. Do not resume drops the
// record in the package, so no later answer carries it. The offer ends once the record's resume started, a resume
// that failed among them: its steps then show in its place. A resume that
// never started offers again.
function sessionOffer(wanted, result, asked) {
    return !wanted && !asked && result !== null && result.kind === "answer" && result.restart !== undefined
        && SESSION_OFFERED.indexOf(result.state) !== -1 && !sessionResumeStarted(result);
}

// The words of a running session the row and the bar's tooltip show:
// { model, since } of RESULT, each null where the package gives none or no
// session lives, `since` as sessionClock writes it.
function sessionRunning(result) {
    var live = result !== null && result.kind === "answer" && sessionLive(result.state);
    return { model: live && result.model !== undefined ? result.model : null,
        since: live && result.since !== undefined ? sessionClock(result.since) : null };
}

// The bar widget's reading of the session (status `jarvisSession`), null
// before the first answer: { model, since } as sessionRunning gives them,
// `offer` null or { unlock } while sessionOffer holds, `steps`, the
// record's steps while the live session is its resume (sessionResumeLive)
// or once a resume ended (sessionResumeStarted), else none, and
// `checkedAt`. A resume that ended reaches no step still pending: such a
// step reads failed with no cause, not resumed. CHECKED
// is null while the service reads pending steps, else the ISO time of its
// last read: the pending steps then drop, since nothing reads them any
// more, and `checkedAt` is that read's "HH:MM"; else it is null.
function sessionRecord(wanted, result, asked, checked) {
    if (result === null || result.kind !== "answer") return null;
    var running = sessionRunning(result);
    var offer = sessionOffer(wanted, result, asked);
    var steps = sessionResumeLive(result) ? result.restart.steps : !sessionResumeStarted(result) ? []
        : result.restart.steps.map(function (step) {
            return step.outcome === "pending" ? { kind: step.kind, name: step.name, outcome: "failed", cause: null } : step;
        });
    var stale = checked !== null && sessionStepsPending(result);
    if (stale) steps = steps.filter(function (step) { return step.outcome !== "pending"; });
    return { model: running.model, since: running.since, offer: offer ? { unlock: result.restart.unlock } : null,
        steps: steps, checkedAt: stale ? sessionClock(checked) : null };
}

// Whether the live session is RESULT's record's resume
// (sessionResumeLive) with a step it has not reached: the steps the
// service reads again. A resume that ended reaches no further step.
function sessionStepsPending(result) {
    return sessionResumeLive(result)
        && result.restart.steps.some(function (step) { return step.outcome === "pending"; });
}

// The row for RESULT, backend/session-control.js's answer, null before the
// first one and { kind: "failed" } where the helper gave none. WANTED is
// the Start Jarvis at boot setting, which words only a session that does
// not run: a live session reads as it is, whatever the setting. OFFERED
// is sessionOffer's answer: the row then offers the Resume. NOT_DISMISSED
// is true once the package did not answer the last Do not resume: while
// the offer stands, the row says so in a line.
function sessionStart(wanted, result, offered, notDismissed) {
    if (result === null) return { hidden: true };
    if (result.kind === "blocked") {
        if (!Object.prototype.hasOwnProperty.call(SESSION_BLOCKS, result.block)) throw new Error("jarvis-setup: session=" + result.block);
        var block = SESSION_BLOCKS[result.block];
        var blocked = { tone: SESSION_CHOICES.indexOf(result.block) !== -1 ? "info" : "warning", text: block.text, hint: block.hint };
        if (block.action !== undefined) blocked.action = block.action;
        return blocked;
    }
    var failure = { tone: "danger", text: "Not started", hint: SESSION_FAILED, action: "retry" };
    if (result.kind !== "answer") return failure;
    var row = SESSION_ROWS[result.state + " " + result.reason];
    if (row === undefined) return failure;
    var value;
    if (offered === true) value = Object.assign({}, SESSION_RESUME);
    else if (row.wanted) value = wanted ? { tone: "info", text: "Starts at the next boot", hint: SESSION_BOOT, action: "start" }
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
    var running = sessionRunning(result);
    var lines = [];
    if (running.model !== null) lines.push("Model: " + running.model);
    if (running.since !== null) lines.push("Running since " + running.since);
    // The selection that failed its check, beside the session that stays.
    if (result.unapplied !== undefined) lines.push(SESSION_BLOCKS[result.unapplied].hint);
    if (offered === true && notDismissed === true) lines.push(SESSION_NOT_DISMISSED);
    if (lines.length > 0) value.lines = lines;
    return value;
}

// The Setup summary SETUP beside SESSION, the Jarvis session row
// (sessionStart). The session is optional, so it never makes Jarvis not
// ready, but a Ready summary names a session the user must fix, as one
// link to the row on Setup that holds the fix: the page gives one
// judgement.
var SESSION_FAULT = "[Jarvis session cannot start](page:vgs.jarvis/Setup/sessionStart)";
var SESSION_FAULTS = { warning: SESSION_FAULT, danger: SESSION_FAULT };
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

// The Local voice reading VALUE under a voice that hears the user
// elsewhere (localVoiceStep): that state, in the info tone while it is not
// ok, since that voice needs no local voice. The Setup tab's optional steps
// take their chip from the page (Steps.stepView), so they need no tone.
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
// voice that hears the user elsewhere it is optional, and its hint says the
// voice is not used: the declared hint links Local voice model, a field the
// page withholds under such a voice.
var LOCAL_VOICE_NEEDED = "The selected voice provider needs the local voice";
var LOCAL_VOICE_UNUSED = "Not used with the voice you chose in [Voice provider](page:vgs.jarvis/Settings/voiceProvider)";
function localVoiceStep(value, provider, voice) {
    var reading = noAction(value);
    delete reading.failure;
    if (voice.action === "setup") {
        if (value.tone === "ok") return reading;
        var row = { tone: "info", text: value.text };
        var lines = (value.lines || []).concat(value.action === true && value.hint === undefined ? [LOCAL_VOICE_NEEDED] : []);
        if (lines.length > 0) row.lines = lines;
        if (value.hint !== undefined) row.hint = value.hint;
        return row;
    }
    return hearsLocally(provider) ? reading : Object.assign(optionalStep(reading), { hint: LOCAL_VOICE_UNUSED });
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

// The setting after a setup run ended with CODE, null to keep it: once a
// cancelled run (130) or one that finished left another tier than the
// wanted one ready, the setting names that tier, "auto" for the pick, so
// the page shows what is installed. A run that failed keeps the model the
// user chose, which the Setup step's retry installs; a run that left none
// keeps it too. CODE null is a run whose end gave no code.
function tierAfterRun(wanted, pick, ready, code) {
    if (wantedTier(wanted, pick) === ready) return null;
    if (code !== undefined && code !== null && code !== 0 && code !== 130) return null;
    return ready === pick ? "auto" : ready;
}
