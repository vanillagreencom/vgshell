// The action and release judges. Routing, approvals, audit and confinement
// belong to their separate owners.
"use strict";
const Tools = require("./Tools.js");

/** @typedef {{kind: "clean"}|{kind: "tainted"}} Taint */
/** @typedef {import("./Tools.js").Effect} Effect */
/** @typedef {{kind: "allow", effect: Effect, grant?: string}|{kind: "confirm", effect: Effect, physical: boolean, scope?: string, grant?: string, line?: string}|{kind: "refuse", reason: string}} Decision */

const PROFILES = {
    cautious: { read: "allow", reversible: "allow", input: "confirm", persistent: "confirm", exec: "confirm", external: "confirm", destructive: "physical" },
    standard: { read: "allow", reversible: "allow", input: "application", persistent: "allow", exec: "confirm", external: "confirm", destructive: "physical" },
    trusted: { read: "allow", reversible: "allow", input: "allow", persistent: "allow", exec: "allow", external: "confirm", destructive: "physical" }
};
// "home" is the text of the user's Jarvis home folder, which only the user
// and VGS write (Denied.js refuses a model's write to it): it taints no turn
// and needs no grant (D105).
const SOURCES = Object.freeze(["speech", "desktop", "home", "clipboard", "file", "screen", "web", "command", "agent"]);
const TAINT_SOURCES = ["file", "screen", "web", "agent"];
const recipientSets = new WeakSet();

// A settings row id: the status rows judge takes one only as one TUI
// argument (PluginLogic.statusRowFits).
function grantKey(key) {
    return typeof key === "string" && require("./Core.js").tuiArguments().valid([key]);
}

// A saved key's line on its card and in Settings: the status rows judge
// takes a label of one printable line of at most STATUS_LABEL_MAX UTF-16
// units (PluginLogic.isPrintableLine), so the cut counts units and keeps
// each character whole.
const LINE_MAX = 60;
function grantLine(text) {
    const line = text.replace(new RegExp(require("./Core.js").settingValues().CONTROL_OR_SEPARATOR.source, "g"), " ");
    if (line.length <= LINE_MAX) return line;
    let cut = "";
    for (const char of line) {
        if (cut.length + char.length > LINE_MAX - 1) break;
        cut += char;
    }
    return cut + "…";
}

/** The saved Always allow keys of a context or a release, [] for none. */
function allowedKeys(value) {
    if (value === undefined) return [];
    if (!Array.isArray(value) || !value.every(grantKey)) throw new Error("jarvis: policy=allowed");
    return value;
}

/**
 * The standing grant key of a release of LABEL to SELECTED: the label and
 * the brain and speech recipients outside this computer, by provider,
 * account and origin. Another provider, account or origin asks again.
 */
function releaseKey(selected, label) {
    assertRecipients(selected);
    const remote = [selected.brain, ...selected.speech]
        .filter(value => value.kind === "network" && !require("./net.js").endpoint(value.origin).loopback)
        .map(value => "recipient=" + [value.provider, value.account, value.origin].map(escaped).join("|"));
    return ["release", label, ...[...new Set(remote)].sort()].join(":");
}

function labels(value) {
    if (!Array.isArray(value) || value.length === 0 || !value.every(source => SOURCES.includes(source)))
        throw new Error("jarvis: release=labels");
    return Object.freeze(SOURCES.filter(source => value.includes(source)));
}

/** Copy a producer's labelled text or bytes. Tool sources come from Tools.refine. */
function item(content, sources) {
    if (typeof content !== "string" && !(content instanceof Uint8Array))
        throw new Error("jarvis: release=content");
    return Object.freeze({ content: typeof content === "string" ? content : Buffer.from(content), labels: labels(sources) });
}

/** The session's summarizer retains every contributing source for the conversation. */
function summary(content, items) {
    if (!Array.isArray(items) || items.length === 0)
        throw new Error("jarvis: release=summary");
    return item(content, items.flatMap(value => labels(value.labels)));
}

/**
 * Freeze one whole conversation recipient set, never one transfer's destination.
 * The session creates a new set when provider, account or policy changes and
 * closes its old net owner. Grants reference this exact set, not its text ids.
 * brain and each speech entry: {kind:"local"|"network", provider, account, origin?}.
 * A harness with cloud inference is network, even though its vendor owns sockets.
 */
function recipients({ conversation, profile, cloudVision, brain, speech }) {
    if (typeof conversation !== "string" || conversation === "" || !Object.hasOwn(PROFILES, profile)
            || !["ask", "allow", "never"].includes(cloudVision))
        throw new Error("jarvis: release=context");
    if (!Array.isArray(speech) || speech.length === 0)
        throw new Error("jarvis: release=speech-recipients");
    function recipient(value) {
        if (!value || !["local", "network"].includes(value.kind)
                || typeof value.provider !== "string" || value.provider === "" || typeof value.account !== "string")
            throw new Error("jarvis: release=recipient");
        if (value.kind === "local") {
            if (value.origin !== undefined) throw new Error("jarvis: release=local-origin");
            return Object.freeze({ kind: "local", provider: value.provider, account: value.account });
        }
        const target = require("./net.js").endpoint(value.origin);
        if (value.origin !== target.origin) throw new Error("jarvis: release=recipient-origin");
        return Object.freeze({ kind: "network", provider: value.provider, account: value.account, origin: target.origin });
    }
    const selectedBrain = recipient(brain);
    const selectedSpeech = Object.freeze(speech.map(recipient));
    const offline = [selectedBrain, ...selectedSpeech].every(value =>
        value.kind === "local" || require("./net.js").endpoint(value.origin).loopback);
    const result = Object.freeze({ conversation, profile, cloudVision,
        brain: selectedBrain, speech: selectedSpeech, offline });
    recipientSets.add(result);
    return result;
}

/** Check the session-owned set without reimplementing its shape in transports. */
function assertRecipients(value) {
    if (!recipientSets.has(value)) throw new Error("jarvis: release=recipient-set");
}

/**
 * Judge a transfer against brain AND speech. Conversation-local grants are
 * {recipients, labels}, issued only by the user approval owner, from a Yes
 * or a saved Always allow key (releaseGrants). A new immutable
 * set invalidates old grants, including an identical selection in a new session.
 * Non-send answers contain a marker, never the withheld original bytes.
 * @returns {{kind:"send"|"withhold", content:string|Buffer, labels:readonly string[]}|{kind:"ask", content:string, labels:readonly string[], needed:readonly string[]}}
 */
function release(value, selected, grants = []) {
    assertRecipients(selected);
    const current = item(value.content, value.labels);
    if (!Array.isArray(grants)) throw new Error("jarvis: release=grants");
    for (const grant of grants) {
        if (!grant || !recipientSets.has(grant.recipients)) throw new Error("jarvis: release=grant-context");
        labels(grant.labels);
    }
    if (selected.offline) return { kind: "send", ...current };
    const marker = "[withheld: " + current.labels.map(source => source === "file" ? "file text" : source + " content").join(", ") + "]";
    if (current.labels.includes("screen") && selected.cloudVision === "never")
        return { kind: "withhold", content: marker, labels: current.labels };
    const missing = current.labels.filter(source => {
        if (source === "speech" || source === "desktop" || source === "home") return false;
        if (source === "screen" && selected.cloudVision === "allow") return false;
        if (source !== "screen" && selected.profile === "trusted") return false;
        return !grants.some(grant => grant.recipients === selected && grant.labels.includes(source));
    });
    if (missing.length !== 0) return { kind: "ask", content: marker, labels: current.labels, needed: Object.freeze(missing) };
    return { kind: "send", ...current };
}

/**
 * The standing grants of a release ask's NEEDED labels to SELECTED: `keys`
 * names each label's key, a label whose key is no settings row id having
 * none, and `standing` the labels whose key ALLOWED, the saved Always allow
 * keys, holds. The approval owner records those as the user's Yes and asks
 * for the rest.
 */
function releaseGrants(selected, needed, allowed) {
    const saved = allowedKeys(allowed);
    const keys = Object.freeze(Object.fromEntries(labels(needed).map(label => [label, releaseKey(selected, label)])
        .filter(([, key]) => grantKey(key))));
    return { keys, standing: Object.freeze(needed.filter(label => saved.includes(keys[label]))) };
}

/** Session owns the turn. The router observes only content reaching that turn. */
function observe(taint, source) {
    if (!taint || !["clean", "tainted"].includes(taint.kind) || !SOURCES.includes(source))
        throw new Error("jarvis: taint=invalid");
    return { kind: taint.kind === "tainted" || TAINT_SOURCES.includes(source) ? "tainted" : "clean" };
}

function chord(value) {
    return value && Array.isArray(value.modifiers)
        && value.modifiers.every(mod => typeof mod === "string" && mod !== "")
        && new Set(value.modifiers).size === value.modifiers.length
        && Number.isSafeInteger(value.keycode) && value.keycode > 0;
}

function sameChord(left, right) {
    return left.keycode === right.keycode
        // Hyprland ORs modifiers from physical and virtual keyboards. The
        // public read-only interfaces expose no held physical mask.
        && left.modifiers.every(mod => right.modifiers.includes(mod));
}

function textChord(bound, symbols) {
    // wtype assigns raw XKB codes from 9 in distinct-character order. Its
    // symbol map remaps newline to Return, tab to Tab and escape to Escape.
    return bound.modifiers.length === 0
        || bound.keycode >= 9 && bound.keycode < 9 + symbols.length
        || bound.codepoint !== 0 && symbols.some(symbol =>
            symbol.toLowerCase() === String.fromCodePoint(bound.codepoint).toLowerCase());
}

/**
 * Decide one model call using executor-owned facts.
 *
 * context: {profile, locked, taint, denied, input?, grants?, forwardGranted?}.
 * forwardGranted is the router's exact live-session sending grant. Missing or
 * unknown lock refuses. denied is Denied.create's current snapshot; it is
 * read only when the call carries a path, so a producer may build it lazily.
 * J47/J51 supply input {target:{kind,id,password?}, key?} at send time.
 * For a key, key is {request, chord, effective, emitted, emittedEffective}.
 * Each identity is a layout-resolved {modifiers, keycode} record. J47 uses the core key
 * judge, then resolves symbols against the live keymap. A literal comparison
 * cannot distinguish keycode/symbol aliases. A missing resolution refuses.
 * grants are J19-owned application/site ids for this conversation only.
 * allowed are the saved Always allow keys (D139). A confirm a key can cover
 * names it in `grant`, and in `line` what it covers (standing); a call whose
 * key is saved is allowed with it: a physical step, a tainted turn's request
 * and an external one alike. A key that is no settings row id is not named.
 *
 * Allow is not an execution permit: J19 must also enforce held-action
 * serialization, approval and J21's pre-action audit. Rejudge fresh targets
 * and paths before execution. No digest, timer or approval matching lives here.
 * @param {unknown} call
 * @returns {Decision}
 */
function decide(call, context) {
    if (!context || context.locked !== false) return { kind: "refuse", reason: "session-locked" };
    if (!Object.hasOwn(PROFILES, context.profile)) return { kind: "refuse", reason: "policy-profile" };
    let allowed;
    try { allowed = allowedKeys(context.allowed); }
    catch { return { kind: "refuse", reason: "allowed-grants" }; }
    if (!context.taint || !["clean", "tainted"].includes(context.taint.kind))
        return { kind: "refuse", reason: "turn-taint" };
    const refined = Tools.refine(call);
    if (refined.kind === "refuse") return refined;
    let effect = refined.effect;
    // The snapshot is read only for a call that carries a path; the daemon
    // builds it on that read.
    if (refined.paths.length > 0) {
        const denied = context.denied;
        if (!denied || typeof denied.inspectPaths !== "function")
            return { kind: "refuse", reason: "path-context" };
        // A field holds one path, or a list a harness program proposes at once.
        // An optional path field left out names no path to judge.
        const pairs = refined.paths.filter(([field]) => Object.hasOwn(refined.call.args, field))
            .flatMap(([field, role]) => [refined.call.args[field]].flat().map(file => [file, role]));
        const judged = denied.inspectPaths(pairs);
        if (judged.kind === "refuse") {
            const { file: _file, ...refusal } = judged;
            return refusal;
        }
        const destructive = pairs.some(([, role], index) => {
            const target = judged.paths[index];
            return target.execution || role === "remove" || (role === "write" && target.exists);
        });
        if (destructive) effect = "destructive";
    }
    // A program's own command escapes Sandbox.js, as text typed at a terminal does.
    if (refined.unconfined) {
        if (context.profile === "trusted") effect = "destructive";
        else return { kind: "refuse", reason: "unconfined-command" };
    }
    let scope = null;
    let target = null;
    if (refined.input !== null) {
        const input = context.input;
        if (input && typeof input.refusal === "string") return { kind: "refuse", reason: input.refusal };
        if (!input || !input.target || !["application", "terminal", "site", "vgs", "lock", "polkit"].includes(input.target.kind))
            return { kind: "refuse", reason: "input-target" };
        if (["vgs", "lock", "polkit"].includes(input.target.kind))
            return { kind: "refuse", reason: "protected-target" };
        if (typeof input.target.id !== "string" || input.target.id === "")
            return { kind: "refuse", reason: "input-identity" };
        if (refined.input === "browser") {
            if (input.target.kind !== "site") return { kind: "refuse", reason: "browser-target" };
            if (input.target.password !== false) return { kind: "refuse", reason: "password-target" };
            if (input.target.submit === true) effect = "external";
        } else if (input.target.kind === "site") return { kind: "refuse", reason: "desktop-target" };
        // J47 keys and pointer calls can enter or paste commands without
        // showing their text. Only the explicit text tool can hold that text.
        if (input.target.kind === "terminal" && refined.input !== "text")
            return { kind: "refuse", reason: "terminal-input" };
        if (refined.input === "key") {
            const key = input.key;
            if (!key || key.request !== call.args.chord || !chord(key.chord)
                    || !Array.isArray(key.effective) || !key.effective.every(chord)
                    || !chord(key.emitted) || !Array.isArray(key.emittedEffective) || !key.emittedEffective.every(chord))
                return { kind: "refuse", reason: "key-context" };
            if (key.effective.some(bound => sameChord(key.chord, bound)))
                return { kind: "refuse", reason: "jarvis-chord" };
            if (key.emittedEffective.some(bound => sameChord(key.emitted, bound)))
                return { kind: "refuse", reason: "jarvis-chord" };
        }
        if (refined.input === "text" && input.target.kind === "terminal") {
            if (context.profile !== "trusted") return { kind: "refuse", reason: "terminal-text" };
            effect = "destructive";
        }
        if (refined.input === "text") {
            if (!input.text || !Array.isArray(input.text.effective) || !input.text.effective.every(bound => chord(bound)
                    && Number.isSafeInteger(bound.codepoint) && bound.codepoint >= 0 && bound.codepoint <= 0x10ffff
                    && !(bound.codepoint >= 0xd800 && bound.codepoint <= 0xdfff)))
                return { kind: "refuse", reason: "text-context" };
            // Model text travels through Node's UTF-8 encoder; an unpaired
            // surrogate becomes U+FFFD before wtype reads it.
            const symbols = [...new Set(Buffer.from(call.args.text).toString("utf8"))]
                .map(symbol => symbol === "\n" ? "\r" : symbol);
            if (input.text.effective.some(bound => textChord(bound, symbols)))
                return { kind: "refuse", reason: "own-shortcut" };
        }
        target = { kind: input.target.kind, id: input.target.id };
        if (input.target.kind !== "terminal") scope = input.target.kind + ":" + input.target.id;
    }
    const rule = PROFILES[context.profile][effect];
    const { key, line } = standing(refined, effect, target, rule === "application" && scope !== null);
    const grant = line !== null && grantKey(key) ? key : undefined;
    // A confirm, unless its key is saved.
    const asked = (physical, extra = {}) => grant !== undefined && allowed.includes(grant) ? { kind: "allow", effect, grant }
        : { kind: "confirm", effect, physical, ...extra, ...(grant === undefined ? {} : { grant, line: grantLine(line) }) };
    if (rule === "physical") return asked(true);
    if (context.taint.kind === "tainted" && refined.executor === "memory-write")
        return { kind: "allow", effect };
    if (context.taint.kind === "tainted" && ["persistent", "exec", "input", "external"].includes(effect))
        return asked(false);
    // REVISIT(D134): only the router's exact live-session sending grant
    // can cover another forward; taint above still asks for this request.
    if (refined.call.id === "fleet.forward" && context.forwardGranted === true) return { kind: "allow", effect };
    if (rule === "confirm") return asked(false);
    if (rule === "application") {
        if (!Array.isArray(context.grants) || !context.grants.every(grant => typeof grant === "string"))
            return { kind: "refuse", reason: "input-grants" };
        if (!context.grants.includes(scope)) return asked(false, { scope });
        return { kind: "allow", effect };
    }
    if (rule === "allow") return { kind: "allow", effect };
    throw new Error("jarvis: policy=unhandled-effect");
}

// A key part's value, with each character that joins parts, names a part
// or joins a recipient's fields escaped, so two requests share a key only
// when every part is equal.
function escaped(value) {
    return String(value).replace(/[%:=,|]/g, char => "%" + char.charCodeAt(0).toString(16).toUpperCase());
}

/**
 * The Always allow key of a refined call and the line that names what it
 * covers, built from the same parts so the line never claims less than the
 * key allows; line null for a call no key covers. Every role and wildcard
 * word comes before the first path, so grantLine's cut shortens path text
 * alone. An application's or
 * site's input scope covers every input tool there. Otherwise the key is the
 * tool, its effect, its input target and each judged path by its field; a
 * coding task's also names its agent and account as the call gives them.
 * TaskRunner resolves an omitted one at launch and releases the goal to it
 * through the release gate, whose key names the provider and account, so a
 * changed default asks there. fleet.forward takes none: its consent record
 * must cite one accepted confirmation (D134).
 */
function standing(refined, effect, target, scoped) {
    const id = refined.call.id;
    const args = refined.call.args;
    const where = target === null ? "" : (target.kind === "site" ? " on " : " in ") + target.id;
    if (scoped) return { key: target.kind + ":" + escaped(target.id),
        line: target.kind === "site" ? "Click and type anything on " + target.id : "Any input anywhere in " + target.id };
    const named = (field, value) => field + "=" + escaped(value);
    const key = [id, effect, ...(target === null ? [] : [named(target.kind, target.id)]),
        ...refined.paths.filter(([field]) => args[field] !== undefined).flatMap(([field]) => [args[field]].flat().map(value => named(field, value))),
        ...(id === "task.start" ? ["agent", "account"].filter(field => args[field] !== undefined).map(field => named(field, args[field])) : [])].join(":");
    const folder = args.cwd === undefined ? "a new empty folder" : args.cwd;
    const roles = [["remove", args.remove], ["move", args.move], ["write any text to", args.write]]
        .filter(([, list]) => Array.isArray(list) && list.length > 0);
    const verbs = roles.map(([verb]) => verb);
    const files = roles.length === 0 ? "" : (verbs.length === 1 ? verbs[0] : verbs.slice(0, -1).join(", ") + " and " + verbs.at(-1))
        + " files: " + roles.map(([, list]) => list.join(", ")).join("; ");
    const lines = {
        "input.text": () => "Type any text" + where,
        "input.key": () => "Press any keys" + where,
        "input.click": () => "Click anywhere" + where,
        "input.scroll": () => "Scroll anywhere" + where,
        "browser": () => (effect === "external" ? "Submit anything" : "Click and type anything") + where,
        "memory.replace": () => "Replace any memory note",
        "fleet.request": () => "Put any request in your Jarvis session mailbox",
        "windows.close": () => "Close any window",
        "files.write": () => "Write any text to " + args.path,
        "files.move": () => "Move a file, from and to: " + args.from + " → " + args.to,
        "files.delete": () => "Delete " + args.path,
        "shell.argv": () => "Run any " + (effect === "external" ? "online " : "") + "command in " + folder,
        "shell.line": () => "Run any " + (effect === "external" ? "online " : "") + "command in " + folder,
        "task.start": () => "Start any " + (args.agent === undefined ? "" : args.agent + " ") + "task"
            + (args.account === undefined ? "" : " with account " + args.account) + " in " + folder,
        "harness.command": () => "Run any command outside the sandbox in " + folder,
        "harness.files": () => files === "" ? null : files.charAt(0).toUpperCase() + files.slice(1)
    };
    return { key, line: Object.hasOwn(lines, id) ? lines[id]() : null };
}

/**
 * What an audit row records of a saved key: its kind with no request value,
 * the tool and effect, the input kind, or the released label.
 */
function grantKind(key) {
    const [head, second] = key.split(":");
    return head === "application" || head === "site" ? head : head + ":" + second;
}

module.exports = { grantKind, grantLine, decide, observe, item, summary, recipients, assertRecipients, release, releaseGrants, labels, SOURCES, TAINT_SOURCES };
