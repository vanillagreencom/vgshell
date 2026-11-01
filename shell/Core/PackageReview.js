.pragma library
.import "PackageManagers.js" as PackageManagers
// The package owner's shared agent, verdict, install-script and build
// failure decisions, and the one judge of its typed package outcome.
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

// The build tools whose output classifyInstallFailure reads, each with the
// versions whose messages it was checked against: makepkg 7.1.0 and paru
// 2.1.0 in the owned reproduction under scripts/fixtures/pkg/check-failure/.
// yay stays unsupported, its failures ordinary, because no real yay check()
// interval has been retained. Revisit when a user reports a yay install
// that fails only in check() and it reproduces on a machine with yay.
var SUPPORTED_BUILDERS = { makepkg: /^7\.1\.[0-9]+$/, paru: /^2\.1\.[0-9]+$/ };
// The most bytes of one attempt's output the classifier reads; a longer
// interval is incomplete evidence, never a cut one. A ceiling, not a
// measurement: the reproduction's longest interval is under 4 KiB.
var FAILURE_INTERVAL_MAX = 16 * 1024 * 1024;

// TEXT, a terminal transcript's bytes as UTF-8, as lines a reader saw:
// escape sequences and shift characters dropped, each line's text after its
// last carriage return, as a redrawn progress line leaves it, and any other
// control character dropped.
function transcriptLines(text) {
    var plain = String(text)
        .replace(/\u001b\][^\u0007\u001b]*(?:\u0007|\u001b\\)/g, "")
        .replace(/\u001b\[[0-?]*[ -\/]*[@-~]/g, "")
        .replace(/\u001b[ -\/]*[0-~]/g, "");
    return plain.split("\n").map(function (line) {
        line = line.replace(/\r+$/, "");
        var cut = line.lastIndexOf("\r");
        return (cut === -1 ? line : line.slice(cut + 1)).replace(/[\u0000-\u0008\u000b-\u001f\u007f]/g, "");
    });
}

// Whether makepkg's gettext messages are English under ENV's locale
// variables. LANGUAGE takes precedence once the message locale is not C.
function englishMessages(env) {
    var e = isPlainObject(env) ? env : {};
    var word = function (name) { return typeof e[name] === "string" ? e[name] : ""; };
    var messages = word("LC_ALL") || word("LC_MESSAGES") || word("LANG");
    if (messages === "" || /^(C|POSIX)(\..*)?$/.test(messages)) return true;
    if (!/^en_[A-Z]{2}(\.[^@]*)?(@.*)?$/.test(messages)) return false;
    return word("LANGUAGE").split(":").every(function (tag) { return tag === "" || /^en(_[A-Z]{2})?$/.test(tag); });
}

// Whether one failed package build is a failure of its own tests alone,
// from EVIDENCE: { builder, versions: { makepkg, paru }, env, status,
// signal, interval, targets }. builder is "paru", "yay" or "makepkg", the
// program the step ran; versions the version each tool reports, or null;
// env the locale variables the step ran with; status and signal the step's
// end; interval null when no output was captured, else { complete, text },
// complete when the capture's end mark arrived; targets the names the step
// asked for. Answers { kind: "check-only", base, version, target } or
// { kind: "ordinary", reason }.
//
// makepkg(8) exits 4 for a failure in any PKGBUILD function, so the
// status says nothing about which one. The answer is inferred from the
// messages makepkg and paru print, which package output can imitate, so
// only one complete, supported interval qualifies: one makepkg error line,
// "A failure occurred in check().", right after check() started and
// followed by makepkg's "Aborting...", in the base the last "Making
// package" names, which is one target; every other base built in the
// interval finished, and paru's summary after it names that base alone.
// Anything else, a signal included, is ordinary.
function classifyInstallFailure(evidence) {
    var ordinary = function (reason) { return { kind: "ordinary", reason: reason }; };
    var e = isPlainObject(evidence) ? evidence : {};
    if (e.interval === null || !isPlainObject(e.interval)) return ordinary("capture=failed");
    if (e.interval.complete !== true || typeof e.interval.text !== "string" || e.interval.text.length > FAILURE_INTERVAL_MAX) return ordinary("interval=incomplete");
    if (e.signal !== null || !Number.isInteger(e.status) || e.status >= 128) return ordinary("signal");
    if (e.status === 0) return ordinary("status=success");
    if (!hasOwn(SUPPORTED_BUILDERS, e.builder)) return ordinary("builder=unsupported");
    var versions = isPlainObject(e.versions) ? e.versions : {};
    if (!SUPPORTED_BUILDERS.makepkg.test(String(versions.makepkg)) || (e.builder !== "makepkg" && !SUPPORTED_BUILDERS[e.builder].test(String(versions[e.builder]))))
        return ordinary("version=unsupported");
    if (!englishMessages(e.env)) return ordinary("locale=unsupported");
    var lines = transcriptLines(e.interval.text);
    var errors = [];
    for (var i = 0; i < lines.length; i++)
        if (lines[i].indexOf("==> ERROR:") === 0) errors.push(i);
    if (errors.length !== 1) return ordinary("makepkg-errors=" + errors.length);
    var at = errors[0];
    if (lines[at] !== "==> ERROR: A failure occurred in check().") return ordinary("phase=other");
    var next = at + 1;
    while (next < lines.length && lines[next] === "") next++;
    if (next === lines.length || lines[next] !== "    Aborting...") return ordinary("marker=incomplete");
    var started = null, base = null, version = null, firstMaking = -1, made = {}, finished = {};
    for (i = 0; i < at; i++) {
        var phase = /^==> Starting ([a-z]+)\(\)\.\.\.$/.exec(lines[i]);
        if (phase !== null) started = phase[1];
        var making = /^==> Making package: (\S+) (\S+) \(/.exec(lines[i]);
        if (making !== null) {
            if (firstMaking === -1) firstMaking = i;
            base = making[1]; version = making[2]; made[base] = true;
        }
        var done = /^==> Finished making: (\S+) /.exec(lines[i]);
        if (done !== null) finished[done[1]] = true;
    }
    if (started !== "check") return ordinary("phase=out-of-order");
    if (base === null) return ordinary("base=missing");
    if (hasOwn(finished, base) || Object.keys(made).some(function (name) { return name !== base && !hasOwn(finished, name); }))
        return ordinary("bases=ambiguous");
    for (i = 0; i < firstMaking; i++)
        if (/^error:/.test(lines[i])) return ordinary("builder-errors");
    var after = lines.slice(next + 1).filter(function (line) { return line !== ""; });
    var built = base + "-" + version;
    var summary = e.builder === "paru" ? ["error: failed to build '" + built + "':", "error: packages failed to build: " + built] : [];
    if (!sameJson(after.map(function (line) { return line.replace(/ +$/, ""); }), summary)) return ordinary("summary=mismatch");
    var targets = Array.isArray(e.targets) ? e.targets : [];
    var matched = targets.filter(function (name) { return String(name).split("/").pop() === base; });
    if (matched.length !== 1) return ordinary("target=unmatched");
    return { kind: "check-only", base: base, version: version, target: matched[0] };
}

// The package owner's typed outcome kinds, each with the fields it carries
// beside kind and manager. package-check-failed carries retry, null when no
// retry remains for the run or { originRun, state }: available while the
// owner holds the one retry for originRun, consumed once it ran.
var PACKAGE_OUTCOMES = {
    "package-installed": ["helper", "package", "testsSkipped"],
    "package-skipped": [],
    "package-failed": ["helper", "status"],
    "package-cancelled": ["status"],
    "package-check-failed": ["helper", "package", "status", "retry"]
};
// The most bytes the presenter reads from the outcome channel.
var PACKAGE_OUTCOME_MAX = 4096;
var OUTCOME_WORD = /^[a-z0-9][a-z0-9-]{0,63}$/;

// VALUE, a package owner's outcome, judged against the run RUN that carried
// it and that run's exit CODE: { ok: true, outcome } with the fields in
// order, or { ok: false, error }. An installed or skipped outcome needs
// exit 0; a failed or check-failed one the status it names, not 0; a
// cancelled one its signal's status, 128 or more. An available retry
// belongs to RUN alone. testsSkipped, true, marks an install the one retry
// without tests made, and names its package.
function packageOutcome(value, run, code) {
    var fail = function (error) { return { ok: false, error: error }; };
    if (!isPlainObject(value) || !hasOwn(PACKAGE_OUTCOMES, value.kind)) return fail("kind");
    var fields = PACKAGE_OUTCOMES[value.kind];
    var keys = Object.keys(value);
    for (var i = 0; i < keys.length; i++)
        if (keys[i] !== "kind" && keys[i] !== "manager" && fields.indexOf(keys[i]) === -1) return fail("field=" + keys[i]);
    if (typeof value.manager !== "string" || PackageManagers.managerRow(value.manager) === null) return fail("manager");
    var out = { kind: value.kind, manager: value.manager };
    if (fields.indexOf("helper") !== -1) {
        if (value.helper !== null && (typeof value.helper !== "string" || !OUTCOME_WORD.test(value.helper))) return fail("helper");
        out.helper = value.helper;
    }
    if (value.kind === "package-installed") {
        if (hasOwn(value, "testsSkipped") !== hasOwn(value, "package")) return fail("tests-skipped");
        if (hasOwn(value, "testsSkipped")) {
            if (value.testsSkipped !== true || !PackageManagers.validName(value.package)) return fail("tests-skipped");
            out.package = value.package;
            out.testsSkipped = true;
        }
    } else if (value.kind === "package-check-failed") {
        if (!PackageManagers.validName(value.package)) return fail("package");
        out.package = value.package;
    }
    if (fields.indexOf("status") !== -1) {
        if (!Number.isInteger(value.status) || value.status !== code) return fail("status");
        if (value.kind === "package-cancelled" ? code < 128 : code === 0) return fail("status");
        out.status = value.status;
    } else if (code !== 0) return fail("status");
    if (value.kind === "package-check-failed") {
        var retry = value.retry;
        if (retry !== null) {
            if (!isPlainObject(retry) || Object.keys(retry).length !== 2 || typeof retry.originRun !== "string" || !OUTCOME_WORD.test(retry.originRun)
                || (retry.state !== "available" && retry.state !== "consumed")) return fail("retry");
            if (retry.state === "available" && retry.originRun !== run) return fail("retry-run");
            retry = { originRun: retry.originRun, state: retry.state };
        }
        out.retry = retry;
    }
    return { ok: true, outcome: out };
}
