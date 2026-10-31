.pragma library
// The package owner's shared agent, verdict and install-script decisions.
function hasOwn(object, key) { return Object.prototype.hasOwnProperty.call(object, key); }
function isPlainObject(value) { return value !== null && typeof value === "object" && !Array.isArray(value); }
function sameJson(a, b) { return JSON.stringify(a) === JSON.stringify(b); }

var REVIEW_AGENTS = [
    { id: "claude", label: "Claude Code", command: ["claude", "--model", "opus", "--effort", "medium", "--permission-mode", "default"] },
    { id: "codex", label: "Codex", command: ["codex", "-m", "gpt-6.1-sol", "-c", "model_reasoning_effort=medium", "--sandbox", "workspace-write", "--ask-for-approval", "on-request"] }
];

// The distribution's own pacman repositories on Arch and CachyOS. A
// package pending from any other repository is reviewed.
var OFFICIAL_REPOSITORY = /^(core|extra|multilib|cachyos.*)$/;

function officialRepository(name) {
    return OFFICIAL_REPOSITORY.test(String(name));
}

function reviewAgentRow(id) {
    for (var i = 0; i < REVIEW_AGENTS.length; i++)
        if (REVIEW_AGENTS[i].id === id) return REVIEW_AGENTS[i];
    return null;
}

// The words of a command setting, split as bash's `read -a` splits them
// with the default IFS, so the service and the pipeline read one list.
function commandWords(text) {
    return String(text).split(/[ \t\n]+/).filter(function (word) { return word !== ""; });
}

// The `reviewAgent` Select's offers: one { label, value } per agent FOUND,
// the ids of REVIEW_AGENTS on PATH, names, in the table's order.
function reviewChoices(found) {
    var out = [];
    for (var i = 0; i < REVIEW_AGENTS.length; i++)
        if (found.indexOf(REVIEW_AGENTS[i].id) >= 0) out.push({ label: REVIEW_AGENTS[i].label, value: REVIEW_AGENTS[i].id });
    return out;
}

// Agent configuration and availability are independent of the optional saved
// preference. A missing configured agent never selects another command.
function reviewPlan(settings, found) {
    var s = isPlainObject(settings) ? settings : {};
    var words = commandWords(typeof s.command === "string" ? s.command : "");
    if (words.length > 0) {
        var named = reviewAgentRow(words[0]);
        return { state: found.indexOf(words[0]) < 0 ? "missing" : "command", agent: named === null ? null : named.id,
            label: named === null ? words[0] : named.label, command: words };
    }
    var chosen = typeof s.agent === "string" ? s.agent : "";
    if (chosen === "") {
        var offers = reviewChoices(found);
        if (offers.length === 0) return { state: "none", agent: null, label: "", command: null };
        chosen = offers[0].value;
    }
    var row = reviewAgentRow(chosen);
    return { state: row === null || found.indexOf(chosen) < 0 ? "missing" : "agent", agent: chosen,
        label: row === null ? chosen : row.label, command: row === null ? null : row.command.slice() };
}

// Only a submitted offer grants consent. Presence, including explicit false,
// selects the initial row; an availability probe cannot change saved policy.
function initialChoice(settings, found) {
    var s = isPlainObject(settings) ? settings : {};
    var configured = (typeof s.agent === "string" && s.agent !== "") || commandWords(s.command || "").length > 0;
    var plan = reviewPlan(s, found);
    return { action: hasOwn(s, "enabled") ? (s.enabled ? "review" : "decline") : (configured || plan.state === "agent" ? "review" : "decline"),
        preference: hasOwn(s, "enabled") ? (s.enabled ? "on" : "off") : "absent", configured: configured,
        availability: plan.state === "missing" || plan.state === "none" ? "unavailable" : "available" };
}

// The verdict file an agent wrote, judged against REVIEWED, the names the
// review listed: { ok: true, verdict: "clean" | "flagged", flags } with one
// { name, concern } per flagged package, or { ok: false, error }. Line 1 is
// `verdict clean` or `verdict flagged`; each later line is `flag <package>
// <concern>`, a listed package flagged once. A clean verdict holds no flag
// and a flagged one at least one. Any other text is no verdict.
function parseVerdict(text, reviewed) {
    var lines = String(text).split("\n");
    if (lines.length > 1 && lines[lines.length - 1] === "") lines.pop();
    if (/[\u0000-\u0009\u000b-\u001f\u007f]/.test(String(text))) return { ok: false, error: "control-character" };
    var head = /^verdict (clean|flagged)$/.exec(lines[0]);
    if (head === null) return { ok: false, error: "line=1" };
    var flags = [];
    var seen = {};
    for (var i = 1; i < lines.length; i++) {
        var m = /^flag (\S+) (\S.*)$/.exec(lines[i]);
        if (m === null || reviewed.indexOf(m[1]) < 0 || hasOwn(seen, m[1])) return { ok: false, error: "line=" + (i + 1) };
        seen[m[1]] = true;
        flags.push({ name: m[1], concern: m[2] });
    }
    if ((head[1] === "clean") !== (flags.length === 0)) return { ok: false, error: "verdict=" + head[1] + " flags=" + flags.length };
    return { ok: true, verdict: head[1], flags: flags };
}

// The install script lines the review flags when an update adds or alters
// them, each a pattern over one line with its whitespace runs one space.
var INSTALL_SCRIPT_RISKS = [
    // a setuid or setgid mode: chmod u+s, g=rxs, 2755, 4755, 06755
    /\bchmod (?:[^;|&]* )?(?:[ugoa]*[+=][rwxXt]*s|0?[234567][01234567]{3}\b)/,
    // file capabilities
    /\bsetcap\b/,
    // a new or changed user or group
    /\b(?:groupadd|useradd|usermod|gpasswd)\b/,
    // a download
    /\b(?:curl|wget)\b/,
    // an encoded payload
    /\bbase64\b/,
    // text piped into a shell
    /\| ?(?:sudo )?(?:ba|da|z)?sh\b/,
    // a removal of the root or of a home directory, which no package owns
    /\brm (?:-\S+ )*(?:\/\*?|~\S*|"?\$HOME\S*|\/home\S*|\/root\S*)(?: |$)/
];

// One line as installScriptChange compares it: trimmed, its whitespace
// and control characters each run one space.
function scriptLine(line) {
    return line.replace(/[\s\u0000-\u001f\u007f]+/g, " ").replace(/^ | $/g, "");
}

// A script's lines, each without trailing whitespace, a CRLF line end's CR
// included, and no blank line at the end.
function scriptLines(text) {
    var lines = String(text).split("\n").map(function (line) { return line.replace(/\s+$/, ""); });
    while (lines.length > 0 && lines[lines.length - 1] === "") lines.pop();
    return lines;
}

function riskyScriptLine(line) {
    for (var i = 0; i < INSTALL_SCRIPT_RISKS.length; i++)
        if (INSTALL_SCRIPT_RISKS[i].test(line)) return true;
    return false;
}

// What an update changes in a package's install script, from the text of
// the INSTALLED package's script and the NEW one's, each null when absent:
// { state, risks }.
//   none       the update has no install script
//   new        the installed package has none
//   unchanged  both hold the same lines once line ends and trailing
//              whitespace are set aside
//   changed    otherwise
// `risks` are the new script's lines, as scriptLine gives them, that the
// installed one does not hold and an INSTALL_SCRIPT_RISKS pattern matches,
// each once; a comment line is none. So a risk the installed package
// already carried is not flagged again.
function installScriptChange(installedText, newText) {
    if (newText === null) return { state: "none", risks: [] };
    var next = scriptLines(newText);
    var old = installedText === null ? null : scriptLines(installedText);
    var state = old === null ? "new" : sameJson(old, next) ? "unchanged" : "changed";
    var held = {};
    var i;
    for (i = 0; old !== null && i < old.length; i++) held[scriptLine(old[i])] = true;
    var risks = [];
    for (i = 0; i < next.length; i++) {
        var line = scriptLine(next[i]);
        if (line === "" || line.charAt(0) === "#" || hasOwn(held, line)) continue;
        held[line] = true;
        if (riskyScriptLine(line)) risks.push(line);
    }
    return { state: state, risks: risks };
}
