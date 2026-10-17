.pragma library

// Pure decisions for vgs.printers: what `lpstat` reports, what the CUPS
// D-Bus helper (cups-pk-helper) answers, which found device takes Add, the
// queue name a new printer gets, the address the IPP field accepts, the
// helper calls each change makes and the rows and lines the pane draws.
// Service.qml owns the processes and runs the calls these plan.
//
// Every helper call is argv for `gdbus call --system`, each string
// argument written as a GVariant text literal: gdbus parses an argument as
// GVariant text first and takes the raw text only when that fails, so an
// unquoted name or address that parses, such as one in quotes, would
// reach the helper changed (gdbus-tool.c, handle_call).

// The CUPS D-Bus helper's bus name, object interface and the requirement
// the manifest declares for it.
var HELPER = "org.opensuse.CupsPkHelper.Mechanism";
// The requirements CUPS brings: without either the list cannot be read.
var CUPS_COMMANDS = ["lpstat", "ipptool"];
// lpstat's options, in the order it prints their answers: the scheduler,
// the printers, the queued jobs, the device URIs. The service runs it under
// LC_ALL=C, so each line is the C locale's. Its `-d` is left out: it names
// the user's own lpoptions default first, which Set as default does not
// change (cups/dest.c, cupsGetNamedDest), so the default is the
// scheduler's, read with CUPS_URI and ipp/default.test.
var LPSTAT_ARGV = ["lpstat", "-r", "-p", "-o", "-v"];
// cupsd's local domain socket, CUPS's own default server, as an ipp URI:
// ipptool decodes the host (httpSeparateURI with HTTP_URI_CODING_ALL) and
// connects to a host that starts with `/` as a domain socket
// (httpAddrGetList). There cupsd authenticates the peer by PeerCred, so
// the subscription's owner may renew and cancel it under the stock
// `Require user @OWNER @SYSTEM` policy, which refuses an unauthenticated
// TCP client; the same socket starts a socket-activated cupsd.
var CUPS_URI = "ipp://%2Frun%2Fcups%2Fcups.sock/";
// How long one ipptool request may take, in seconds.
var IPP_TIMEOUT_S = 10;
// How long a helper call may take, in seconds: polkit holds the call while
// the session's agent asks the user, so it covers a person reading the
// prompt.
var CALL_TIMEOUT_S = 120;
// DevicesGet's own wait for CUPS's backends, in seconds, and the most
// devices it lists.
var FIND_WAIT_S = 10;
var FIND_LIMIT = 32;
// The driverless model PrinterAdd takes as its PPD name: IPP Everywhere,
// lpadmin's `-m everywhere`.
var DRIVERLESS_MODEL = "everywhere";
// CUPS refuses a queue name longer than 127 bytes (lpadmin.c,
// validate_name); a suffix for a taken name needs room under it.
var NAME_ROOM = 100;
// The path IPP Everywhere printers serve, for an address given without one.
var DEFAULT_PATH = "/ipp/print";

// The user's sentence for each failure key a change can end with.
var PROBLEM_TEXT = {
    "refused": "You did not give permission. Nothing changed.",
    "helper-missing": "Install the printer helper to add or change printers.",
    "timeout": "The printer helper did not answer in time. Try again.",
    "cups": "Printing could not make this change.",
    "failed": "VGS could not reach the printer helper.",
    "address": "Enter a printer address, such as printer.local.",
    "scheme": "Enter an IPP address, such as ipp://printer.local.",
    "driver": "This printer needs a driver. Add it in Print Settings.",
    "installed": "This printer is already added.",
    "added-stopped": "The printer was added, but it is stopped and does not take jobs. Turn it on in Print Settings."
};

// gdbus's failure text, one pattern per kind, read from its stderr. The
// examples are in scripts/test-printers-logic.js. Any other failure is
// `failed`.
var HELPER_FAILURES = [
    { kind: "refused", pattern: /GDBus\.Error:org\.opensuse\.CupsPkHelper\.Mechanism\.NotPrivileged:/ },
    { kind: "helper-missing", pattern: /GDBus\.Error:org\.freedesktop\.DBus\.Error\.(ServiceUnknown|NameHasNoOwner):/ },
    { kind: "timeout", pattern: /^Error: Timeout was reached$/m }
];

// --- lpstat -------------------------------------------------------------

// What `lpstat -r -p -o -v` printed, CODE its exit status and STDOUT its
// output, as lpstat.c writes each line:
//   { state: "down" }                       the scheduler is not running
//   { state: "failed", reason }             a line or an exit it does not know
//   { state: "read", printers, default }    printers in lpstat's order, each
//                                           { name, state, message, jobs,
//                                           isDefault, uri }; `state` is
//                                           idle, holding (idle, holding new
//                                           jobs), printing or stopped;
//                                           `default` "" until withDefault
// A scheduler that is not running makes the later options fail, so the
// first line alone decides `down`. A `Name/instance` line is an lpoptions
// instance of a printer already listed, so it and its message lines add
// nothing.
function lpstatReading(code, stdout) {
    var lines = String(stdout).split("\n");
    if (lines[0] === "scheduler is not running") return { state: "down" };
    if (lines[0] !== "scheduler is running") return { state: "failed", reason: "scheduler-line" };
    if (code !== 0) return { state: "failed", reason: "exit=" + code };
    var printers = [];
    var jobs = {};
    var uris = {};
    var last = null;
    var instance = false;
    for (var i = 1; i < lines.length; i++) {
        var line = lines[i];
        if (line === "") continue;
        var m;
        if ((m = /^printer (\S+) (is idle|is holding new jobs|now printing \S+|disabled since .* -)(\.  enabled since .*)?$/.exec(line)) !== null) {
            var state = m[2] === "is idle" ? "idle" : m[2] === "is holding new jobs" ? "holding" : m[2].indexOf("now printing") === 0 ? "printing" : "stopped";
            if ((state === "stopped") !== (m[3] === undefined)) return { state: "failed", reason: "printer-line" };
            instance = m[1].indexOf("/") !== -1;
            last = instance ? null : { name: m[1], state: state, message: "", jobs: 0, isDefault: false, uri: "" };
            if (!instance) printers.push(last);
        } else if ((m = /^\t(.*)$/.exec(line)) !== null) {
            if (instance) continue;
            if (last === null) return { state: "failed", reason: "message-line" };
            // lpstat's own words for a stopped printer with no message.
            if (last.message === "" && m[1].trim() !== "reason unknown") last.message = m[1].trim();
        } else if ((m = /^device for (\S+): (\S+)$/.exec(line)) !== null) {
            if (m[1].indexOf("/") === -1) uris[m[1]] = m[2];
            last = null;
            instance = false;
        } else if ((m = /^(\S+)-[0-9]+ +\S+ +[0-9]+ /.exec(line)) !== null) {
            jobs[m[1]] = (jobs[m[1]] || 0) + 1;
            last = null;
            instance = false;
        } else {
            return { state: "failed", reason: "line" };
        }
    }
    for (var p = 0; p < printers.length; p++) {
        printers[p].jobs = jobs[printers[p].name] || 0;
        printers[p].uri = uris[printers[p].name] || "";
    }
    return { state: "read", printers: printers, "default": "" };
}

// The scheduler's default destination from `ipptool -t` over
// ipp/default.test, CODE its exit status: { ok: true, name }, name "" when
// CUPS has none, or { ok: false, reason }. The test accepts CUPS's
// not-found answer, and displays printer-name otherwise.
function defaultReading(code, stdout) {
    if (code !== 0) return { ok: false, reason: "exit=" + code };
    var m = /^ +printer-name \([^)]*\) = (\S+)$/m.exec(String(stdout));
    return { ok: true, name: m === null ? "" : m[1] };
}

// READING, lpstatReading's answer, with NAME the default; any other
// reading unchanged.
function withDefault(reading, name) {
    if (reading.state !== "read") return reading;
    return {
        state: "read",
        "default": name,
        printers: reading.printers.map(function (p) {
            return { name: p.name, state: p.state, message: p.message, jobs: p.jobs, isDefault: p.name === name, uri: p.uri };
        })
    };
}

// The argv of one ipptool request to the scheduler: TEST, an ipp/ test
// file's path, with each of VARIABLES as `-d name=value`.
function ippArgv(test, variables) {
    var argv = ["ipptool", "-T", String(IPP_TIMEOUT_S), "-t"];
    for (var name in variables) argv.push("-d", name + "=" + variables[name]);
    return argv.concat([CUPS_URI, test]);
}

// --- the watcher --------------------------------------------------------

// One line of bin/printers-watch: { kind: "ready" }, { kind: "event",
// name } for a CUPS notification, else { kind: "unknown" }.
function watchLine(line) {
    if (/^ready subscription=[0-9]+$/.test(line)) return { kind: "ready" };
    var m = /^event ([A-Za-z]+)$/.exec(line);
    if (m !== null) return { kind: "event", name: m[1] };
    return { kind: "unknown" };
}

// --- the pane's views ---------------------------------------------------

// The open views of the pane: { leases, next }. The watcher, and with it
// the CUPS subscription, runs only while a lease is open, since nothing but
// the pane shows live printer state.
function viewIdle() { return { leases: [], next: 1 }; }

// A new lease: { state, id }.
function viewBegin(state) { return { state: { leases: state.leases.concat([state.next]), next: state.next + 1 }, id: state.next }; }

// The end of lease ID: { state, known }, `known` false for an id no lease
// holds.
function viewEnd(state, id) {
    var at = state.leases.indexOf(id);
    if (at === -1) return { state: state, known: false };
    var leases = state.leases.slice();
    leases.splice(at, 1);
    return { state: { leases: leases, next: state.next }, known: true };
}

// --- GVariant text ------------------------------------------------------

// The value of TEXT, gdbus's print of a reply: a tuple or an array as a
// list, a dictionary as an object, a string, a boolean or a whole number,
// with `@type` annotations skipped. null for anything else, or for text
// left over.
function parseGVariant(text) {
    var at = 0;
    var s = String(text);
    function space() { while (at < s.length && /\s/.test(s[at])) at++; }
    function fail() { throw new Error("gvariant"); }
    function word() {
        var m = /^[A-Za-z0-9_+-]+/.exec(s.slice(at));
        if (m === null) fail();
        at += m[0].length;
        return m[0];
    }
    function string() {
        var quote = s[at++];
        var out = "";
        while (at < s.length && s[at] !== quote) {
            var c = s[at++];
            if (c !== "\\") { out += c; continue; }
            var e = s[at++];
            var simple = { "n": "\n", "t": "\t", "r": "\r", "f": "\f", "v": "\v", "a": "\x07", "b": "\b", "\\": "\\", "'": "'", "\"": "\"" };
            if (simple[e] !== undefined) out += simple[e];
            else if (e === "u" || e === "U") {
                var digits = s.slice(at, at + (e === "u" ? 4 : 8));
                if (!/^[0-9A-Fa-f]+$/.test(digits) || digits.length !== (e === "u" ? 4 : 8)) fail();
                out += String.fromCodePoint(parseInt(digits, 16));
                at += digits.length;
            } else fail();
        }
        if (at >= s.length) fail();
        at++;
        return out;
    }
    function list(close) {
        var out = [];
        at++;
        space();
        while (s[at] !== close) {
            out.push(value());
            space();
            if (s[at] === ",") { at++; space(); } else if (s[at] !== close) fail();
        }
        at++;
        return out;
    }
    function dict() {
        var out = {};
        at++;
        space();
        while (s[at] !== "}") {
            var key = value();
            space();
            if (s[at++] !== ":") fail();
            space();
            out[String(key)] = value();
            space();
            if (s[at] === ",") { at++; space(); } else if (s[at] !== "}") fail();
        }
        at++;
        return out;
    }
    function value() {
        space();
        if (s[at] === "@") {
            at++;
            while (at < s.length && !/\s/.test(s[at])) at++;
            space();
        }
        var c = s[at];
        if (c === "(") return list(")");
        if (c === "[") return list("]");
        if (c === "{") return dict();
        if (c === "'" || c === "\"") return string();
        var w = word();
        if (w === "true") return true;
        if (w === "false") return false;
        if (/^-?[0-9]+$/.test(w)) return Number(w);
        // A typed number, such as `uint32 5`.
        if (/^(byte|int16|uint16|int32|uint32|int64|uint64)$/.test(w)) return value();
        fail();
    }
    try {
        var out = value();
        space();
        return at === s.length ? out : null;
    } catch (e) {
        return null;
    }
}

// --- the helper ---------------------------------------------------------

// S as a GVariant text string literal.
function quoted(s) { return "'" + String(s).replace(/\\/g, "\\\\").replace(/'/g, "\\'") + "'"; }

// The argv of one helper call: METHOD of the helper's interface with
// ARGS, each already GVariant text.
function helperArgv(method, args) {
    return ["gdbus", "call", "--system", "--dest", HELPER, "--object-path", "/", "--timeout", String(CALL_TIMEOUT_S),
        "--method", HELPER + "." + method].concat(args);
}

// The calls each change makes, in order. A new queue starts stopped and
// refuses jobs until it is enabled and accepts them, as lpadmin -E does.
function addSteps(name, uri, info) {
    return [
        helperArgv("PrinterAdd", [quoted(name), quoted(uri), quoted(DRIVERLESS_MODEL), quoted(info), quoted("")]),
        helperArgv("PrinterSetEnabled", [quoted(name), "true"]),
        helperArgv("PrinterSetAcceptJobs", [quoted(name), "true", quoted("")])
    ];
}
function defaultSteps(name) { return [helperArgv("PrinterSetDefault", [quoted(name)])]; }
function removeSteps(name) { return [helperArgv("PrinterDelete", [quoted(name)])]; }
function findSteps() { return [helperArgv("DevicesGet", [String(FIND_WAIT_S), String(FIND_LIMIT), "@as []", "@as []"])]; }

// One helper call's end, CODE gdbus's exit status: { ok: true, value },
// value the reply as parseGVariant reads it, or { ok: false, problem,
// detail }, problem a PROBLEM_TEXT key and detail what the log keeps. The
// helper answers a refused CUPS request with its error text as the
// reply's first string.
function helperReply(code, stdout, stderr) {
    if (code !== 0) {
        var text = String(stderr);
        for (var i = 0; i < HELPER_FAILURES.length; i++)
            if (HELPER_FAILURES[i].pattern.test(text)) return { ok: false, problem: HELPER_FAILURES[i].kind, detail: firstLine(text) };
        return { ok: false, problem: "failed", detail: "exit=" + code + " " + firstLine(text) };
    }
    var value = parseGVariant(String(stdout).trim());
    if (!Array.isArray(value) || typeof value[0] !== "string") return { ok: false, problem: "failed", detail: "reply=unparsable" };
    if (value[0] !== "") return { ok: false, problem: "cups", detail: value[0] };
    return { ok: true, value: value };
}

function firstLine(text) { return String(text).split("\n")[0].trim(); }

// --- changes ------------------------------------------------------------

// A change: { kind, target, steps, index, phase, problem }, `kind` add,
// default, remove or find, `phase` running, done or failed, `problem` a
// PROBLEM_TEXT key once failed. `index` is the step that runs.
function opIdle() { return { kind: "", target: "", steps: [], index: 0, phase: "idle", problem: "" }; }
function opBegin(kind, target, steps) { return { kind: kind, target: target, steps: steps, index: 0, phase: "running", problem: "" }; }

// OP after its running step ended with REPLY, helperReply's answer. A
// failed step ends the change, so a refusal at the first call changes
// nothing.
function opAdvance(op, reply) {
    if (op.phase !== "running") throw new Error("printers: a step ended while the change is " + op.phase);
    var next = { kind: op.kind, target: op.target, steps: op.steps, index: op.index + 1, phase: "running", problem: "" };
    if (!reply.ok) {
        next.index = op.index;
        next.phase = "failed";
        // Past PrinterAdd the queue exists; only enabling it failed.
        next.problem = op.kind === "add" && op.index > 0 ? "added-stopped" : reply.problem;
    } else if (next.index >= op.steps.length) {
        next.phase = "done";
    }
    return next;
}

// What the status publishes of OP.
function opView(op) { return { kind: op.kind, target: op.target, phase: op.phase, problem: op.problem }; }

// The sentence for a failure KEY, "" for none.
function problemText(key) { return key === "" ? "" : PROBLEM_TEXT[key] || PROBLEM_TEXT.failed; }

// --- found devices ------------------------------------------------------

// Whether URI names a printer IPP Everywhere drives with no driver: an
// ipp or ipps address, or a DNS-SD service of type _ipp or _ipps.
function driverless(uri) {
    var m = /^([a-z][a-z0-9+.-]*):\/\/([^/?]*)/i.exec(uri);
    if (m === null) return false;
    var scheme = m[1].toLowerCase();
    if (scheme === "ipp" || scheme === "ipps") return true;
    if (scheme !== "dnssd") return false;
    var host = decodeURIComponent(m[2]);
    return /\._ipps?\._tcp(\.|$)/.test(host);
}

// The found DEVICES no printer of PRINTERS already uses, by URI.
function foundShown(devices, printers) {
    return devices.filter(function (d) { return !printers.some(function (p) { return p.uri === d.uri; }); });
}

// The devices of DEVICES, DevicesGet's dictionary of `device-<field>:<n>`
// keys, in CUPS's order: { key, uri, info, make, driverless }. A backend's
// own entry, a URI with no `:`, is no device, and a URI an installed
// printer of PRINTERS already uses is left out.
function foundDevices(devices, printers) {
    var byIndex = {};
    var order = [];
    for (var key in devices) {
        var m = /^device-(class|id|info|make-and-model|uri|location):([0-9]+)$/.exec(key);
        if (m === null) continue;
        if (byIndex[m[2]] === undefined) {
            byIndex[m[2]] = {};
            order.push(Number(m[2]));
        }
        byIndex[m[2]][m[1]] = String(devices[key]);
    }
    order.sort(function (a, b) { return a - b; });
    var installed = printers.map(function (p) { return p.uri; });
    var out = [];
    for (var i = 0; i < order.length; i++) {
        var d = byIndex[String(order[i])];
        var uri = d.uri || "";
        if (uri.indexOf(":") === -1 || installed.indexOf(uri) !== -1) continue;
        var info = d.info || d["make-and-model"] || uri;
        out.push({ key: uri, uri: uri, info: printable(info), make: printable(d["make-and-model"] || ""), driverless: driverless(uri) });
    }
    return out;
}

function printable(text) { return String(text).replace(/[\x00-\x1f\x7f]/g, " ").trim().slice(0, 127); }

// A queue name for a printer called TEXT that no name of TAKEN holds:
// letters, digits, `_`, `.` and `-`, other runs as one `_`, then `_2`,
// `_3` and on for a name taken. CUPS compares names without case.
function queueName(text, taken) {
    var base = String(text).replace(/[^A-Za-z0-9_.-]+/g, "_").replace(/^[_.-]+|[_.-]+$/g, "").slice(0, NAME_ROOM);
    if (base === "") base = "Printer";
    var lower = taken.map(function (name) { return String(name).toLowerCase(); });
    var name = base;
    for (var n = 2; lower.indexOf(name.toLowerCase()) !== -1; n++) name = base + "_" + n;
    return name;
}

// The address field's TEXT as a printer: { ok: true, uri, host }, or
// { ok: false, problem } with `address` or `scheme`. A host alone, a host
// and port, or an ipp:// or ipps:// address; a missing path is the IPP
// Everywhere path.
function addressDevice(text) {
    var t = String(text).trim();
    if (t === "" || t.length > 512 || /[\s\x00-\x1f\x7f]/.test(t)) return { ok: false, problem: "address" };
    var scheme = "ipp";
    var rest = t;
    var m = /^([A-Za-z][A-Za-z0-9+.-]*):\/\/(.*)$/.exec(t);
    if (m !== null) {
        scheme = m[1].toLowerCase();
        if (scheme !== "ipp" && scheme !== "ipps") return { ok: false, problem: "scheme" };
        rest = m[2];
    }
    var slash = rest.indexOf("/");
    var authority = slash === -1 ? rest : rest.slice(0, slash);
    var path = slash === -1 ? "" : rest.slice(slash);
    var hm = /^(\[[0-9A-Fa-f:.]+\]|[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?)(?::([0-9]{1,5}))?$/.exec(authority);
    if (hm === null || (hm[2] !== undefined && Number(hm[2]) > 65535)) return { ok: false, problem: "address" };
    if (path === "" || path === "/") path = DEFAULT_PATH;
    return { ok: true, uri: scheme + "://" + authority + path, host: hm[1] };
}

// --- what the screens draw ----------------------------------------------

// The status `printing`, the Setup step, from READING, lpstatReading's
// answer or { state: "unread" }, CUPSMISSING, whether the scan found a
// command of CUPS_COMMANDS missing, and STEP, the service-cups system
// step's state, or "" while it has no reading, before the core's first
// probe ends. Printing that is off with no step reading is null, which
// clears the entry, so Setup reads Checking. Printing that is not
// installed reads To do with a hint that links the Details tab, whose
// Tools section installs the optional CUPS commands. Printing that is off offers Turn on printing
// (`action`) while the step applies. Where the user cannot act, the value
// is `available: false` with a hint that says why: an administrator
// masked cups.service (step denied), the step could not be checked, or
// the printers could not be read.
function printingView(reading, cupsMissing, step) {
    if (cupsMissing) return { tone: "warning", text: "Printing is not installed.", hint: "[Install printing](page:vgs.printers/Details) to use printers" };
    switch (reading.state) {
    case "unread": return { tone: "info", text: "Reading printers" };
    case "down":
        if (step === "") return null;
        if (step === "needed" || step === "nixos") return { tone: "warning", text: "Printing is off.", action: true };
        if (step === "denied") return { tone: "warning", text: "Turned off", available: false,
            hint: "An administrator turned printing off on this computer. It stays off until they turn it back on." };
        return { tone: "warning", text: "Printing is off.", available: false,
            hint: "VGS could not check printing. Turn Printers off and on to check again." };
    case "failed": return { tone: "danger", text: "Reading printers failed.", available: false,
        hint: "VGS could not read your printers. Turn Printers off and on to try again." };
    case "read":
        var count = reading.printers.length;
        return { tone: "ok", text: count === 0 ? "No printers" : count === 1 ? "1 printer" : count + " printers" };
    default:
        throw new Error("printers: reading state " + JSON.stringify(reading.state) + " is not one of unread, down, failed, read");
    }
}

// One DeviceList row per printer of PRINTERS: its name, its state and
// queued jobs, in the danger tone for a stopped printer, an icon that marks
// a stopped printer and a Default badge.
function printerRows(printers) {
    return printers.map(function (p) {
        var state = p.state === "printing" ? "Printing" : p.state === "holding" ? "Holding new jobs"
            : p.state === "stopped" ? (p.message === "" ? "Stopped" : "Stopped: " + p.message) : "Ready";
        var jobs = p.jobs === 0 ? "" : p.jobs === 1 ? " · 1 job" : " · " + p.jobs + " jobs";
        return {
            key: p.name,
            text: p.name,
            secondary: state + jobs,
            secondaryTone: p.state === "stopped" ? "danger" : "",
            iconName: p.state === "stopped" ? "printer-x" : "printer",
            badge: p.isDefault ? "Default" : "",
            badgeTone: "accent",
            isDefault: p.isDefault
        };
    });
}

// Whether the pane offers Print Settings while the scheduler reads CUPS,
// the pane's `cups`: system-config-printer needs CUPS, so not while
// printing is not installed.
function settingsOffered(cups) { return cups !== "missing"; }

// A printer row's action and its menu.
function printerAction(row) { return row.isDefault ? null : { text: "Set as default" }; }
function printerMenu(row) {
    var out = [];
    if (!row.isDefault) out.push({ key: "default", text: "Set as default", iconName: "printer-check" });
    out.push({ key: "remove", text: "Remove", iconName: "trash" });
    return out;
}

// One DeviceList row per found device: Add for a driverless printer,
// Print Settings for one that needs a driver.
function foundRows(devices) {
    return devices.map(function (d) {
        return { key: d.uri, text: d.info, secondary: d.driverless ? d.uri : "Needs a driver", iconName: "printer", driverless: d.driverless };
    });
}
function foundAction(row) { return { text: row.driverless ? "Add" : "Print Settings" }; }
