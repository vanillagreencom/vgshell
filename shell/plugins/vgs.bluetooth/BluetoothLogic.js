.pragma library

// Pure decisions for vgs.bluetooth: what rfkill reports, what the power
// switch and the bar icon show, the power operation, the discovery debt,
// the pairing steps, the pairing dialog's prompts and the device rows. QML
// owns the processes, the timers and the Quickshell Bluetooth objects, and
// runs each effect these return.
//
// Power is one operation in which the rfkill soft block is the state:
// BlueZ never keeps an
// adapter's Powered across a boot, and systemd-rfkill keeps the block.
// On unblocks, then waits POWER_WAIT_MS for any adapter to report powered,
// then sets each adapter's Powered itself and waits again, then fails. Off
// blocks every Bluetooth radio at once. A failure lasts until what was
// asked for is observed, or until the next press.
//
// Discovery keeps what the plugin wants apart from what BlueZ confirms.
// Quickshell 0.3.1 forwards a `discovering` write only when it differs from
// the state BlueZ last reported (BluetoothAdapter::startDiscovery and
// stopDiscovery, src/bluetooth/adapter.cpp), so a stop written while a
// start is unconfirmed is dropped. The debt (`owes`) records that this
// plugin started or adopted a session; after the last lease ends, a stop is
// written each DISCOVERY_TICK_MS while BlueZ still confirms discovering, at
// most DISCOVERY_STOP_ATTEMPTS times.

var POWER_WAIT_MS = 2000;
var DISCOVERY_TICK_MS = 1000;
var DISCOVERY_STOP_ATTEMPTS = 3;
// How long a Pair call that ended without the device reading paired, and
// with no agent prompt open, waits for the Paired change before it counts
// as failed. BlueZ answers Pair and emits the Paired change separately
// (g_dbus_emit_property_changed queues the change), so the two can arrive
// in either order.
var PAIR_SETTLE_MS = 2000;
// BlueZ's longest name, 248 bytes (Core Specification, Vol 3, Part C,
// 3.2.2).
var ALIAS_MAX_BYTES = 248;

// The Lucide icon of each BlueZ device Icon name, the freedesktop names
// BlueZ derives from the device class (src/eir.c, class_to_icon).
var DEVICE_ICONS = {
    "audio-card": "speaker",
    "audio-headphones": "headphones",
    "audio-headset": "headphones",
    "camera-photo": "camera",
    "camera-video": "camera",
    "computer": "laptop",
    "input-gaming": "gamepad-2",
    "input-keyboard": "keyboard",
    "input-mouse": "mouse",
    "input-tablet": "pen-tool",
    "modem": "radio",
    "multimedia-player": "music",
    "network-wireless": "wifi",
    "phone": "smartphone",
    "printer": "printer",
    "scanner": "printer",
    "video-display": "monitor"
};

// --- rfkill ---------------------------------------------------------------

// The Bluetooth radios of one `rfkill -J` run: util-linux prints
// {"rfkilldevices": [{ id, type, device, soft, hard }]} with "blocked" or
// "unblocked". Answers { state: "read", radios, soft, hard }, soft or hard
// true when any Bluetooth radio holds that block, or { state: "failed",
// reason } for a run that failed or printed something else.
function rfkillReading(code, stdout) {
    if (code !== 0) return { state: "failed", reason: "exit=" + code };
    var doc;
    try {
        doc = JSON.parse(stdout);
    } catch (e) {
        return { state: "failed", reason: "unparsable" };
    }
    var rows = doc !== null && typeof doc === "object" ? doc.rfkilldevices : undefined;
    if (!Array.isArray(rows)) return { state: "failed", reason: "shape" };
    var radios = 0, soft = false, hard = false;
    for (var i = 0; i < rows.length; i++) {
        var row = rows[i];
        if (row === null || typeof row !== "object" || row.type !== "bluetooth") continue;
        if (!isBlockValue(row.soft) || !isBlockValue(row.hard)) return { state: "failed", reason: "shape" };
        radios += 1;
        soft = soft || row.soft === "blocked";
        hard = hard || row.hard === "blocked";
    }
    return { state: "read", radios: radios, soft: soft, hard: hard };
}

function isBlockValue(value) { return value === "blocked" || value === "unblocked"; }

// --- the power view -------------------------------------------------------

// Each power view by key: where the switch stands (`on`), whether a press
// may start an operation (`canToggle`), the status state tone, the line,
// whether the service-bluetooth step applies (`action`), and whether the
// line draws as a hint, an error or not at all (`shows`). `failed` takes
// its text from FAILURE_TEXT; `failed` and `rfkill-failed` take `on` from
// the observed power.
var POWER_VIEWS = {
    "rfkill-missing": { on: false, canToggle: false, tone: "warning", text: "Install rfkill to turn Bluetooth on and off.", action: false, shows: "hint" },
    "hard-blocked": { on: false, canToggle: false, tone: "warning", text: "Turned off by a hardware switch", action: false, shows: "hint" },
    "service-needed": { on: false, canToggle: false, tone: "warning", text: "The Bluetooth service is off.", action: true, shows: "hint" },
    "no-adapter": { on: false, canToggle: false, tone: "info", text: "No Bluetooth adapter found", action: false, shows: "hint" },
    "turning-on": { on: true, canToggle: false, tone: "info", text: "Turning on", action: false, shows: "hint" },
    "turning-off": { on: false, canToggle: false, tone: "info", text: "Turning off", action: false, shows: "hint" },
    "failed": { on: false, canToggle: true, tone: "danger", text: "", action: false, shows: "error" },
    "rfkill-failed": { on: false, canToggle: true, tone: "danger", text: "VGS could not read the Bluetooth switch.", action: false, shows: "error" },
    "off": { on: false, canToggle: true, tone: "ok", text: "Off", action: false, shows: "none" },
    "on": { on: true, canToggle: true, tone: "ok", text: "On", action: false, shows: "none" }
};

// The user-facing line of each failure key the power operation leaves.
var FAILURE_TEXT = {
    "no-power": "Bluetooth did not turn on.",
    "rfkill-failed": "VGS could not change the Bluetooth switch."
};

// What every surface shows for power, from INPUT:
//   rfkillMissing  the requirement scan did not find rfkill
//   rfkill         { state: "unread" } or rfkillReading's answer
//   adapters       how many adapters Quickshell lists
//   powered        any adapter reports Powered
//   op             the power operation, powerIdle() and on
//   step           the service-bluetooth system step's state, or ""
// Answers { key, on, canToggle, tone, text, action, shows } from
// POWER_VIEWS. The keys, in the order they win: rfkill-missing,
// hard-blocked, service-needed (no adapter and the service is not
// running), no-adapter, turning-on, turning-off, failed, rfkill-failed,
// off (soft-blocked, or unblocked with no adapter powered) and on.
function powerView(input) {
    var rfkill = input.rfkill;
    var read = rfkill.state === "read";
    if (input.rfkillMissing) return view("rfkill-missing", {});
    if (read && rfkill.hard) return view("hard-blocked", {});
    if (input.adapters === 0)
        return view(input.step === "needed" || input.step === "nixos" ? "service-needed" : "no-adapter", {});
    switch (input.op.phase) {
    case "unblocking":
    case "waiting": return view("turning-on", {});
    case "blocking": return view("turning-off", {});
    case "failed": return view("failed", { on: input.powered, text: FAILURE_TEXT[input.op.reason] });
    case "idle": break;
    default:
        throw new Error("bluetooth: power phase " + JSON.stringify(input.op.phase) + " is not one of idle, unblocking, waiting, blocking, failed");
    }
    if (rfkill.state === "failed") return view("rfkill-failed", { on: input.powered });
    if (read && rfkill.soft) return view("off", {});
    return view(input.powered ? "on" : "off", {});
}

function view(key, changes) {
    var base = POWER_VIEWS[key];
    var out = { key: key, on: base.on, canToggle: base.canToggle, tone: base.tone, text: base.text, action: base.action, shows: base.shows };
    for (var name in changes) out[name] = changes[name];
    return out;
}

// The lines under a power switch for VIEW and PROBLEM, the refusal the last
// press was answered with or "": { hint, error }, each "" for none.
function powerLine(current, problem) {
    if (current === null) return { hint: "", error: problem };
    return {
        hint: current.shows === "hint" ? current.text : "",
        error: problem !== "" ? problem : current.shows === "error" ? current.text : ""
    };
}

// The power view the service published, or null before it published.
function publishedPower(values) {
    var published = values === null || values === undefined ? undefined : values.bluetooth;
    return published === undefined ? null : published.power;
}

// --- the power operation --------------------------------------------------

// The operation's state: { phase, want, fallback, reason }. `phase` is
// idle, unblocking (rfkill unblock runs), waiting (for an adapter to
// report powered; `fallback` once Powered was set directly), blocking
// (rfkill block runs) or failed (`reason` a FAILURE_TEXT key). `want` is
// the power asked for, "on" or "off", "" while idle.
//
// Every step answers { op, effects }, and a press also `reply`. Each effect
// is { type } with its payload, run in order:
//   { type: "run", verb }  start rfkill with VERB, block or unblock
//   { type: "arm", ms }    start the wait's one timer
//   { type: "disarm" }     stop it
//   { type: "enable" }     set Powered on every unpowered, unblocked adapter
//   { type: "read" }       read rfkill again
function powerIdle() { return { phase: "idle", want: "", fallback: false, reason: "" }; }

function opOf(phase, want, fallback, reason) { return { phase: phase, want: want, fallback: fallback, reason: reason }; }

// A press of the switch: WANT is "on" or "off", CURRENT powerView's answer.
// `reply` is `ok` or a refusal the caller logs.
function powerRequest(op, want, current) {
    if (want !== "on" && want !== "off") return { op: op, effects: [], reply: "refused: power=" + JSON.stringify(want) + " want=on|off" };
    if (!current.canToggle) return { op: op, effects: [], reply: "refused: power=" + want + " reason=" + current.key };
    if (current.key !== "failed" && current.on === (want === "on")) return { op: op, effects: [], reply: "ok" };
    if (want === "on") return { op: opOf("unblocking", "on", false, ""), effects: [{ type: "run", verb: "unblock" }], reply: "ok" };
    return { op: opOf("blocking", "off", false, ""), effects: [{ type: "run", verb: "block" }], reply: "ok" };
}

// Whether SEEN, { powered, rfkill }, is the power WANT asked for: on is any
// adapter powered, off is rfkill reading the soft block.
function reached(want, seen) {
    if (want === "on") return seen.powered;
    return seen.rfkill.state === "read" && seen.rfkill.soft;
}

// One event of the operation. EVENT is one of
//   { type: "rfkill-exit", code }  the rfkill block or unblock ended
//   { type: "observed" }           an adapter's power or rfkill's reading
//                                  changed
//   { type: "deadline" }           POWER_WAIT_MS passed while waiting
// and SEEN, { powered, rfkill }, what is observed now.
function powerEvent(op, event, seen) {
    switch (event.type) {
    case "rfkill-exit":
        if (op.phase === "blocking")
            return event.code === 0 ? { op: powerIdle(), effects: [{ type: "read" }] } : failed("off", "rfkill-failed");
        if (op.phase === "unblocking") {
            if (event.code !== 0) return failed("on", "rfkill-failed");
            if (seen.powered) return { op: powerIdle(), effects: [{ type: "read" }] };
            return { op: opOf("waiting", "on", false, ""), effects: [{ type: "read" }, { type: "arm", ms: POWER_WAIT_MS }] };
        }
        throw new Error("bluetooth: rfkill exit with no rfkill run, phase " + op.phase);
    case "observed":
        if (op.phase === "waiting" && seen.powered) return { op: powerIdle(), effects: [{ type: "disarm" }] };
        if (op.phase === "failed" && reached(op.want, seen)) return { op: powerIdle(), effects: [] };
        return { op: op, effects: [] };
    case "deadline":
        if (op.phase !== "waiting") return { op: op, effects: [] };
        if (seen.powered) return { op: powerIdle(), effects: [] };
        if (!op.fallback) return { op: opOf("waiting", "on", true, ""), effects: [{ type: "enable" }, { type: "arm", ms: POWER_WAIT_MS }] };
        return failed("on", "no-power");
    default:
        throw new Error("bluetooth: power event " + JSON.stringify(event.type) + " is not one of rfkill-exit, observed, deadline");
    }
}

function failed(want, reason) {
    return { op: opOf("failed", want, false, reason), effects: [{ type: "read" }] };
}

// --- discovery ------------------------------------------------------------

// The discovery state: { leases, next, owes, attempts }. `leases` are the
// open lease ids, `next` the id the next lease takes, `owes` whether this
// plugin started or adopted the session BlueZ may still run, and
// `attempts` the stops written since the last lease ended. CTX is
// { powered, confirmed }: the default adapter reports Powered, and BlueZ
// confirms Discovering. Every step answers { state, effects }, effects
// each "start" or "stop": write `discovering` true or false.
function discoveryIdle() { return { leases: [], next: 1, owes: false, attempts: 0 }; }

function withState(state, changes) {
    var out = { leases: state.leases.slice(), next: state.next, owes: state.owes, attempts: state.attempts };
    for (var key in changes) out[key] = changes[key];
    return out;
}

// A new lease; also answers its `id`. A session BlueZ already runs is
// adopted, so the stop after the last lease settles it either way.
function discoveryBegin(state, ctx) {
    var next = withState(state, { leases: state.leases.concat([state.next]), next: state.next + 1 });
    if (ctx.confirmed) next.owes = true;
    var effects = [];
    if (ctx.powered && !ctx.confirmed) {
        effects.push("start");
        next.owes = true;
    }
    return { state: next, effects: effects, id: state.next };
}

// The end of lease ID; `known` is false for an id no lease holds. The last
// lease's end writes a stop at once when BlueZ confirms discovering; a start
// still unconfirmed is stopped by discoveryTick once it is confirmed.
function discoveryEnd(state, id, ctx) {
    var at = state.leases.indexOf(id);
    if (at === -1) return { state: state, effects: [], known: false };
    var leases = state.leases.slice();
    leases.splice(at, 1);
    var next = withState(state, { leases: leases });
    if (leases.length > 0) return { state: next, effects: [], known: true };
    next.attempts = 0;
    return { state: next, effects: next.owes && ctx.confirmed ? ["stop"] : [], known: true };
}

// Whether the one DISCOVERY_TICK_MS timer runs: while a lease waits for a
// powered adapter's start, or while a debt waits on a confirmed session.
function discoveryTickWanted(state, ctx) {
    if (state.leases.length > 0) return ctx.powered && !ctx.confirmed;
    return state.owes && ctx.confirmed;
}

// One tick. With a lease: BlueZ refuses a start while an adapter powers up,
// and ends discovery on its own timeout, so a start is written again. With
// none: a stop, until DISCOVERY_STOP_ATTEMPTS were written; past that the
// session is another client's and the debt is dropped.
function discoveryTick(state, ctx) {
    if (state.leases.length > 0) {
        if (!ctx.powered || ctx.confirmed) return { state: state, effects: [] };
        return { state: withState(state, { owes: true }), effects: ["start"] };
    }
    if (!state.owes || !ctx.confirmed) return { state: state, effects: [] };
    if (state.attempts >= DISCOVERY_STOP_ATTEMPTS) return { state: withState(state, { owes: false, attempts: 0 }), effects: [] };
    return { state: withState(state, { attempts: state.attempts + 1 }), effects: ["stop"] };
}

// BlueZ's confirmed state changed. A session that ended with no lease open
// settles the debt; one confirmed while a lease is open is adopted.
function discoveryConfirmed(state, ctx) {
    if (state.leases.length === 0 && !ctx.confirmed) return { state: withState(state, { owes: false, attempts: 0 }), effects: [] };
    if (state.leases.length > 0 && ctx.confirmed) return { state: withState(state, { owes: true }), effects: [] };
    return { state: state, effects: [] };
}

// The default adapter was replaced: the old adapter's session is not this
// adapter's, so the debt goes; the leases stay, and the tick starts the new
// adapter's session.
function discoveryReplaced(state) {
    return { state: withState(state, { owes: false, attempts: 0 }), effects: [] };
}

// The service's teardown: a stop for a session it owes and BlueZ confirms,
// then nothing is left.
function discoveryTeardown(state, ctx) {
    return { state: discoveryIdle(), effects: state.owes && ctx.confirmed ? ["stop"] : [] };
}

// --- pairing --------------------------------------------------------------

// One pairing from the pane: { phase, address, name, ended, reason }.
// `phase` is idle, leasing (the agent lease is pending), pairing (Pair was
// called), settling (Pair ended with the device unpaired and no prompt
// open), done or failed (`reason` canceled, agent-busy, not-paired or
// gone). `name` is the device's name when the pairing started; `ended`
// records that Pair answered. Every step answers { state, effects },
// effects run in order, each one of "begin-lease", "pair", "cancel-pair",
// "release-lease", "trust-connect", "arm-settle" and "disarm-settle".
function pairIdle() { return { phase: "idle", address: "", name: "", ended: false, reason: "" }; }

function pairActive(state) { return state.phase === "leasing" || state.phase === "pairing" || state.phase === "settling"; }

function pairWith(state, changes) {
    var out = { phase: state.phase, address: state.address, name: state.name, ended: state.ended, reason: state.reason };
    for (var key in changes) out[key] = changes[key];
    return out;
}

// EVENT is one of
//   { type: "start", address, name }  the user asked to pair ADDRESS
//   { type: "lease", state }          the agent lease's state changed
//   { type: "pair-ended", open }      the Pair call answered, OPEN agent
//                                     prompts still open
//   { type: "paired" }                the device reads paired
//   { type: "prompts", open }         how many agent prompts are open
//   { type: "settled" }               PAIR_SETTLE_MS passed while settling
//   { type: "cancel" }                the user canceled, or BlueZ did
//   { type: "gone" }                  the device left the list
// A start while a pairing runs changes nothing, its name included.
function pairStep(state, event) {
    switch (event.type) {
    case "start":
        if (pairActive(state)) return { state: state, effects: [] };
        return { state: { phase: "leasing", address: event.address, name: event.name, ended: false, reason: "" }, effects: ["begin-lease"] };
    case "lease":
        if (state.phase !== "leasing") return { state: state, effects: [] };
        if (event.state === "ready") return { state: pairWith(state, { phase: "pairing" }), effects: ["pair"] };
        if (event.state === "refused") return { state: pairWith(state, { phase: "failed", reason: "agent-busy" }), effects: ["release-lease"] };
        return { state: state, effects: [] };
    case "pair-ended":
        if (state.phase !== "pairing") return { state: state, effects: [] };
        if (event.open > 0) return { state: pairWith(state, { ended: true }), effects: [] };
        return { state: pairWith(state, { phase: "settling", ended: true }), effects: ["arm-settle"] };
    case "prompts":
        if (state.phase === "settling" && event.open > 0) return { state: pairWith(state, { phase: "pairing" }), effects: ["disarm-settle"] };
        if (state.phase === "pairing" && state.ended && event.open === 0) return { state: pairWith(state, { phase: "settling" }), effects: ["arm-settle"] };
        return { state: state, effects: [] };
    case "paired":
        if (!pairActive(state)) return { state: state, effects: [] };
        return { state: pairWith(state, { phase: "done" }), effects: ["disarm-settle", "release-lease", "trust-connect"] };
    case "settled":
        if (state.phase !== "settling") return { state: state, effects: [] };
        return { state: pairWith(state, { phase: "failed", reason: "not-paired" }), effects: ["release-lease"] };
    case "cancel":
        if (!pairActive(state)) return { state: state, effects: [] };
        return { state: pairWith(state, { phase: "failed", reason: "canceled" }), effects: ["disarm-settle", "cancel-pair", "release-lease"] };
    case "gone":
        if (!pairActive(state)) return { state: state, effects: [] };
        return { state: pairWith(state, { phase: "failed", reason: "gone" }), effects: ["disarm-settle", "release-lease"] };
    default:
        throw new Error("bluetooth: pair event " + JSON.stringify(event.type) + " is not one of start, lease, pair-ended, prompts, paired, settled, cancel, gone");
    }
}

// The line the pane shows for a pairing STATE, "" for none.
function pairText(state) {
    switch (state.phase) {
    case "idle": return "";
    case "leasing":
    case "pairing":
    case "settling": return "Pairing with " + state.name;
    case "done": return "Paired with " + state.name;
    case "failed":
        switch (state.reason) {
        case "agent-busy": return "Another app handles Bluetooth pairing. Close it and try again.";
        case "canceled": return "Pairing was canceled.";
        case "not-paired": return state.name + " did not pair. Make sure it is in pairing mode and try again.";
        case "gone": return state.name + " is out of range.";
        default: throw new Error("bluetooth: pair reason " + JSON.stringify(state.reason) + " is not one of agent-busy, canceled, not-paired, gone");
        }
    default:
        throw new Error("bluetooth: pair phase " + JSON.stringify(state.phase) + " is not one of idle, leasing, pairing, settling, done, failed");
    }
}

// --- the pairing dialog ---------------------------------------------------

// Each prompt of the pairing dialog, by kind: the agent's request kinds
// (docs/architecture/bluetooth-agent.md § Requests) and `rename`. `field`
// is what the dialog's text field takes, "" for no field; `accept` how
// Pair, Allow, OK or Rename answers: `true`, the field's text, the field's
// number, or the field's name (`alias`); `dismiss` the value Cancel,
// Decline or Escape sends the agent, and `cancels` whether it ends the
// pairing. `actions` are the Dialog's, the accept action last; its
// `needsField` is disabled while the field is empty.
var PROMPTS = {
    "confirm": {
        field: "", accept: "true", dismiss: false, cancels: true,
        title: function (who, entry) { return "Pair with " + who + "?"; },
        message: function (who, entry) { return "Make sure " + who + " shows " + entry.code + "."; },
        actions: [{ label: "Cancel", role: "cancel" }, { label: "Pair", role: "accept" }]
    },
    "pin": {
        field: "PIN", accept: "text", dismiss: false, cancels: true,
        title: function (who, entry) { return "Enter the PIN for " + who; },
        message: function (who, entry) { return "Find the PIN on the device or in its manual."; },
        actions: [{ label: "Cancel", role: "cancel" }, { label: "Pair", role: "accept", needsField: true }]
    },
    "passkey-entry": {
        field: "Passkey", accept: "number", dismiss: false, cancels: true,
        title: function (who, entry) { return "Enter the passkey for " + who; },
        message: function (who, entry) { return "Enter the number " + who + " shows."; },
        actions: [{ label: "Cancel", role: "cancel" }, { label: "Pair", role: "accept", needsField: true }]
    },
    "passkey-display": {
        field: "", accept: "true", dismiss: true, cancels: true,
        title: function (who, entry) { return "Type this code on " + who; },
        message: function (who, entry) { return entry.code + (entry.entered > 0 ? "\n" + entry.entered + " of " + entry.code.length + " typed" : ""); },
        actions: [{ label: "Cancel", role: "cancel" }]
    },
    "authorize": {
        field: "", accept: "true", dismiss: false, cancels: true,
        title: function (who, entry) { return entry.service !== "" ? "Allow " + who + " to connect?" : "Pair with " + who + "?"; },
        message: function (who, entry) { return entry.service !== "" ? "It asks for the service " + entry.service + "." : "Another device asks to pair with this computer."; },
        actions: [{ label: "Decline", role: "cancel" }, { label: "Allow", role: "accept" }]
    },
    "cancel": {
        field: "", accept: "true", dismiss: true, cancels: false,
        title: function (who, entry) { return "Pairing was canceled"; },
        message: function (who, entry) { return "The other device ended pairing."; },
        actions: [{ label: "OK", role: "accept" }]
    },
    "rename": {
        field: "Name", accept: "alias", dismiss: null, cancels: false,
        title: function (who, entry) { return "Rename " + who; },
        message: function (who, entry) { return "The new name shows on this computer only."; },
        actions: [{ label: "Cancel", role: "cancel" }, { label: "Rename", role: "accept", needsField: true }]
    }
};

function promptOf(kind) {
    var prompt = PROMPTS[kind];
    if (prompt === undefined) throw new Error("bluetooth: prompt kind " + JSON.stringify(kind) + " is not one of " + Object.keys(PROMPTS).join(", "));
    return prompt;
}

// What the dialog draws for KIND: { title, message, field, actions }, WHO
// the device it names and ENTRY the agent's request, null for a rename.
// FIELDTEXT disables an accept action that needs the field while it is
// blank.
function promptView(kind, who, entry, fieldText) {
    var prompt = promptOf(kind);
    var blank = String(fieldText).trim() === "";
    return {
        title: prompt.title(who, entry),
        message: prompt.message(who, entry),
        field: prompt.field,
        actions: prompt.actions.map(function (action) {
            return { label: action.label, role: action.role, enabled: !(action.needsField === true && blank) };
        })
    };
}

// The accept action's answer for KIND from FIELDTEXT: { answer } or
// { error }, the line under the field. A rename answers the alias
// aliasOf allows; UTF8BYTES counts a name's bytes.
function promptAccept(kind, fieldText, utf8Bytes) {
    switch (promptOf(kind).accept) {
    case "true": return { answer: true };
    case "text": return { answer: String(fieldText) };
    case "number":
        if (!/^[0-9]{1,6}$/.test(fieldText)) return { error: "Enter a number from 0 to 999999." };
        return { answer: Number(fieldText) };
    case "alias":
        var alias = aliasOf(fieldText, utf8Bytes);
        if (alias.refused === "empty") return { error: "Enter a name." };
        if (alias.refused === "too-long") return { error: "Enter a shorter name." };
        return { answer: alias.alias };
    default:
        throw new Error("bluetooth: prompt accept " + JSON.stringify(promptOf(kind).accept) + " is not one of true, text, number, alias");
    }
}

// The line under the field when the agent refuses an accepted answer for
// KIND, such as a PIN bluetoothctl cannot take.
function promptRefusal(kind) {
    return promptOf(kind).field === "PIN" ? "Enter 1 to 16 letters or digits." : "VGS could not send that answer.";
}

// What dismissing KIND does: { answer, cancels }, `answer` the value the
// agent receives, null for a rename, which answers nothing.
function promptDismiss(kind) {
    var prompt = promptOf(kind);
    return { answer: prompt.dismiss, cancels: prompt.cancels };
}

// A rename the pane may write: { alias }, the trimmed TEXT, or
// { refused: "empty" | "too-long" } past ALIAS_MAX_BYTES. UTF8BYTES counts
// the bytes, qs.Commons SettingValues.utf8Bytes in the shell.
function aliasOf(text, utf8Bytes) {
    var value = String(text).trim();
    if (value === "") return { refused: "empty" };
    if (utf8Bytes(value) > ALIAS_MAX_BYTES) return { refused: "too-long" };
    return { alias: value };
}

// --- devices --------------------------------------------------------------

// A device's display name: its alias, else its own name, else its address.
function deviceName(device) {
    var alias = String(device.name || "").trim();
    if (alias !== "") return alias;
    var own = String(device.deviceName || "").trim();
    return own !== "" ? own : String(device.address || "");
}

// Whether a nearby device names itself: an alias that is only its address
// or a UUID is a beacon or a phone's random address, which the list hides.
function namesItself(device) {
    var label = String(device.name || device.deviceName || "").trim();
    if (label === "") return false;
    if (/^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(label)) return false;
    return !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(label);
}

// The device of DEVICES whose address is ADDRESS, or null.
function deviceAt(devices, address) {
    for (var i = 0; i < devices.length; i++)
        if (devices[i] !== null && devices[i] !== undefined && devices[i].address === address) return devices[i];
    return null;
}

// Plain rows of DEVICES, Quickshell BluetoothDevice objects, for the lists:
// { mine, nearby }, each sorted by name, in the shape a qs.Ui DeviceList
// takes ({ key, text, secondary, iconName, battery }) plus `connected`,
// `trusted` and `pairing`. A row holds primitives alone, so no delegate
// keeps a device object BlueZ may remove while it is built; actions find the device by address, the key.
// `mine` is every paired, bonded or trusted device; `nearby` every other
// device that names itself.
function deviceRows(devices) {
    var mine = [], nearby = [];
    for (var i = 0; i < devices.length; i++) {
        var d = devices[i];
        if (d === null || d === undefined) continue;
        var known = d.paired || d.bonded || d.trusted;
        if (!known && !namesItself(d)) continue;
        var row = {
            key: String(d.address),
            text: deviceName(d),
            secondary: stateText(d),
            iconName: DEVICE_ICONS[d.icon] || "bluetooth",
            battery: d.batteryAvailable ? d.battery : NaN,
            connected: d.connected === true,
            trusted: d.trusted === true,
            pairing: d.pairing === true
        };
        (known ? mine : nearby).push(row);
    }
    var byName = function (a, b) { return a.text.localeCompare(b.text) || a.key.localeCompare(b.key); };
    mine.sort(byName);
    nearby.sort(byName);
    return { mine: mine, nearby: nearby };
}

// The secondary line of a device row.
function stateText(d) {
    if (d.pairing) return "Pairing";
    if (d.connected) return "Connected";
    if (d.paired || d.bonded) return "Not connected";
    return "Not paired";
}

// The action button of one of your devices: Connect or Disconnect.
function mineAction(row) {
    return row.connected ? { text: "Disconnect", variant: "secondary" } : { text: "Connect", variant: "primary" };
}

// The action button of a nearby device: Pair, or none while it or another
// device pairs.
function nearbyAction(row, pairing) {
    return pairing || row.pairing ? null : { text: "Pair", variant: "primary" };
}

// The overflow menu of one of your devices: Rename, Trust or Don't trust,
// and Forget.
function mineMenu(row) {
    return [
        { key: "rename", text: "Rename", iconName: "pencil" },
        row.trusted ? { key: "untrust", text: "Don't trust", iconName: "shield-off" } : { key: "trust", text: "Trust", iconName: "shield-check" },
        { key: "forget", text: "Forget", iconName: "trash" }
    ];
}

// --- the bar --------------------------------------------------------------

// What the bar icon shows for POWER, the published power view or null,
// CONNECTED, the count of connected devices, and HIDEWHENOFF, the setting:
// { shown, icon, count, tooltip }. It hides before the service published,
// with no adapter, and while off when HIDEWHENOFF holds; `count` is the
// connected count while on, "" otherwise.
function barView(power, connected, hideWhenOff) {
    if (power === null) return { shown: false, icon: "bluetooth", count: "", tooltip: "Bluetooth" };
    var linked = power.on && connected > 0;
    return {
        shown: power.key !== "no-adapter" && power.key !== "service-needed" && !(hideWhenOff && !power.on),
        icon: !power.on ? "bluetooth-off" : linked ? "bluetooth-connected" : "bluetooth",
        count: linked ? String(connected) : "",
        tooltip: linked ? "Bluetooth: " + connected + " connected" : "Bluetooth: " + power.text
    };
}
