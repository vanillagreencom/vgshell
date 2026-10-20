#!/usr/bin/env node
// vgs.printers's decisions under the same loader as QML: what lpstat
// prints, the watcher's lines, gdbus's replies and failures, the helper
// calls each change makes, the change's steps, which found device takes
// Add, the queue name, the address field and the lines and rows the
// screens draw. The lpstat lines are the host's own (cups 2.4.19, C locale)
// less its -d line, and lpstat.c's formats; the default.test lines are
// ipptool.c's -t print of a printer-name; the gdbus replies and errors are gdbus 2.88's
// prints of scripts/smoke/fixtures/devices/cups.py on a private bus. Each
// control below plants one defect in a copy of the logic; the suite must
// turn red on every one.
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");
const assert = require("node:assert/strict");
const { load } = require("../bin/lib/qml-library.js");
const file = path.join(__dirname, "../shell/plugins/vgs.printers/PrintersLogic.js");
const plain = value => JSON.parse(JSON.stringify(value));

const SINCE = "Sat Oct 10 17:32:40 2026";
const host = [
    "scheduler is running",
    `printer Brother is idle.  enabled since ${SINCE}`,
    "\tWaiting for job to complete.",
    "device for Brother: ipp://BRWF4289DE3354F.local:631/ipp/print",
    ""
].join("\n");
const busy = [
    "scheduler is running",
    `printer Lab disabled since ${SINCE} -`,
    "\treason unknown",
    `printer Office now printing Office-100.  enabled since ${SINCE}`,
    `printer Office-2 disabled since ${SINCE} -`,
    "\tPaper jam",
    `printer Office-2/duplex disabled since ${SINCE} -`,
    "\tPaper jam",
    `printer Spare is holding new jobs.  enabled since ${SINCE}`,
    "Office-100              smoke                 1024   " + SINCE,
    "Office-101              smoke                 1024   " + SINCE,
    "Office-2-7              smoke                 1024   " + SINCE,
    "device for Lab: ipp://lab.local/ipp/print",
    "device for Office: socket://192.0.2.9",
    "device for Office-2: usb://Brother/HL",
    "device for Office-2/duplex: usb://Brother/HL",
    "device for Spare: ipp://spare.local/ipp/print",
    ""
].join("\n");
const devices = "('', {'device-class:0': 'network', 'device-info:0': 'Lab Printer', 'device-make-and-model:0': 'HP LaserJet', 'device-uri:0': 'ipp://lab.local:631/ipp/print', 'device-class:1': 'direct', 'device-info:1': 'Brother HL-L2350DW', 'device-make-and-model:1': 'Brother HL-L2350DW', 'device-uri:1': 'usb://Brother/HL-L2350DW?serial=E7', 'device-class:2': 'network', 'device-info:2': \"It's \\\"quoted\\\"\", 'device-uri:2': 'socket://192.0.2.9'})\n";

function suite(logic) {
    // lpstat, one row per output: the code, the text and the reading.
    for (const [name, code, text, want] of [
        ["the host's one idle printer", 0, host, { state: "read", default: "", printers: [{ name: "Brother", state: "idle", message: "Waiting for job to complete.", jobs: 0, isDefault: false, uri: "ipp://BRWF4289DE3354F.local:631/ipp/print" }] }],
        ["no printer", 0, "scheduler is running\n", { state: "read", default: "", printers: [] }],
        ["a busy printer with its jobs, stopped ones, an instance and one holding new jobs", 0, busy, { state: "read", default: "", printers: [
            { name: "Lab", state: "stopped", message: "", jobs: 0, isDefault: false, uri: "ipp://lab.local/ipp/print" },
            { name: "Office", state: "printing", message: "", jobs: 2, isDefault: false, uri: "socket://192.0.2.9" },
            { name: "Office-2", state: "stopped", message: "Paper jam", jobs: 1, isDefault: false, uri: "usb://Brother/HL" },
            { name: "Spare", state: "holding", message: "", jobs: 0, isDefault: false, uri: "ipp://spare.local/ipp/print" }] }],
        ["an instance's message adds nothing to its printer", 0, "scheduler is running\n" + `printer Lab is idle.  enabled since ${SINCE}\nprinter Lab/duplex disabled since ${SINCE} -\n\treason unknown\n`, { state: "read", default: "", printers: [{ name: "Lab", state: "idle", message: "", jobs: 0, isDefault: false, uri: "" }] }],
        ["a scheduler that is not running", 1, "scheduler is not running\n", { state: "down" }],
        ["a failed read while running", 1, "scheduler is running\n", { state: "failed", reason: "exit=1" }],
        ["no scheduler line", 0, "printer Lab is idle.  enabled since X\n", { state: "failed", reason: "scheduler-line" }],
        ["a line lpstat does not print", 0, "scheduler is running\nsomething else\n", { state: "failed", reason: "line" }],
        ["a message before any printer", 0, "scheduler is running\n\tPaper jam\n", { state: "failed", reason: "message-line" }],
        ["an idle line without its date", 0, "scheduler is running\nprinter Lab is idle\n", { state: "failed", reason: "printer-line" }],
        ["a stopped line with an enabled date", 0, `scheduler is running\nprinter Lab disabled since ${SINCE} -.  enabled since ${SINCE}\n`, { state: "failed", reason: "printer-line" }]
    ]) assert.deepEqual(plain(logic.lpstatReading(code, text)), want, name);

    // The scheduler's default, and the reading that marks it.
    for (const [name, code, text, want] of [
        ["a default", 0, '"default.test":\n    Get the default printer                                              [PASS]\n        printer-name (nameWithoutLanguage) = Lab\n', { ok: true, name: "Lab" }],
        ["none", 0, '"default.test":\n    Get the default printer                                              [PASS]\n', { ok: true, name: "" }],
        ["a failed request", 1, 'ipptool: Unable to connect to "/run/cups/cups.sock" on port 631 - Connection refused\n', { ok: false, reason: "exit=1" }]
    ]) assert.deepEqual(plain(logic.defaultReading(code, text)), want, name);
    assert.deepEqual(plain(logic.withDefault(logic.lpstatReading(0, busy), "Office").printers.map(p => [p.name, p.isDefault])),
        [["Lab", false], ["Office", true], ["Office-2", false], ["Spare", false]]);
    assert.equal(logic.withDefault(logic.lpstatReading(0, busy), "Office").default, "Office");
    assert.deepEqual(plain(logic.withDefault({ state: "down" }, "Office")), { state: "down" });
    assert.deepEqual(plain(logic.ippArgv("/p/ipp/default.test", { id: "4" })), ["ipptool", "-T", "10", "-t", "-d", "id=4", "ipp://%2Frun%2Fcups%2Fcups.sock/", "/p/ipp/default.test"]);

    for (const [line, want] of [
        ["ready subscription=7", { kind: "ready" }],
        ["event PrinterAdded", { kind: "event", name: "PrinterAdded" }],
        ["event Printer Added", { kind: "unknown" }],
        ["ready", { kind: "unknown" }]
    ]) assert.deepEqual(plain(logic.watchLine(line)), want, line);

    // gdbus's prints.
    for (const [name, text, want] of [
        ["a string reply", "('',)", [""]],
        ["a CUPS refusal", "('The printer or class does not exist.',)", ["The printer or class does not exist."]],
        ["an empty dictionary", "('', @a{ss} {})", ["", {}]],
        ["DevicesGet", devices.trim(), ["", {
            "device-class:0": "network", "device-info:0": "Lab Printer", "device-make-and-model:0": "HP LaserJet", "device-uri:0": "ipp://lab.local:631/ipp/print",
            "device-class:1": "direct", "device-info:1": "Brother HL-L2350DW", "device-make-and-model:1": "Brother HL-L2350DW", "device-uri:1": "usb://Brother/HL-L2350DW?serial=E7",
            "device-class:2": "network", "device-info:2": "It's \"quoted\"", "device-uri:2": "socket://192.0.2.9" }]],
        ["escapes", "('a\\nb\\u00e9\\\\', [true, false], uint32 5, -3)", ["a\nbé\\", [true, false], 5, -3]],
        ["text left over", "('',) x", null],
        ["an open string", "('abc", null],
        ["an unknown word", "(objectpath '/a',)", null]
    ]) assert.deepEqual(plain(logic.parseGVariant(text)), want, name);
    for (const value of ["plain", "it's", "back\\slash", "\\'", "Büro \"2\""])
        assert.equal(logic.parseGVariant(logic.quoted(value)), value, "quoted round trip " + JSON.stringify(value));

    // gdbus's ends.
    for (const [name, code, stdout, stderr, want] of [
        ["success", 0, "('',)\n", "", { ok: true, value: [""] }],
        ["CUPS refused the request", 0, "('The printer or class does not exist.',)\n", "", { ok: false, problem: "cups", detail: "The printer or class does not exist." }],
        ["polkit refused", 1, "", "Error: GDBus.Error:org.opensuse.CupsPkHelper.Mechanism.NotPrivileged: Not Authorized for action: org.opensuse.cupspkhelper.mechanism.printeraddremove\n", { ok: false, problem: "refused", detail: "Error: GDBus.Error:org.opensuse.CupsPkHelper.Mechanism.NotPrivileged: Not Authorized for action: org.opensuse.cupspkhelper.mechanism.printeraddremove" }],
        ["the helper is not installed", 1, "", "Error: GDBus.Error:org.freedesktop.DBus.Error.ServiceUnknown: The name org.opensuse.CupsPkHelper.Mechanism was not provided by any .service files\n", { ok: false, problem: "helper-missing", detail: "Error: GDBus.Error:org.freedesktop.DBus.Error.ServiceUnknown: The name org.opensuse.CupsPkHelper.Mechanism was not provided by any .service files" }],
        ["no answer in time", 1, "", "Error: Timeout was reached\n", { ok: false, problem: "timeout", detail: "Error: Timeout was reached" }],
        ["no bus", 1, "", "Error connecting: Could not connect: No such file or directory\n", { ok: false, problem: "failed", detail: "exit=1 Error connecting: Could not connect: No such file or directory" }],
        ["a failed start", -1, "", "", { ok: false, problem: "failed", detail: "exit=-1 " }],
        ["an unreadable reply", 0, "garbage\n", "", { ok: false, problem: "failed", detail: "reply=unparsable" }]
    ]) assert.deepEqual(plain(logic.helperReply(code, stdout, stderr)), want, name);

    // The calls, as argv.
    const call = (method, args) => ["gdbus", "call", "--system", "--dest", "org.opensuse.CupsPkHelper.Mechanism", "--object-path", "/", "--timeout", "120",
        "--method", "org.opensuse.CupsPkHelper.Mechanism." + method].concat(args);
    assert.deepEqual(plain(logic.addSteps("Lab", "ipp://lab.local/ipp/print", "Lab's printer")), [
        call("PrinterAdd", ["'Lab'", "'ipp://lab.local/ipp/print'", "'everywhere'", "'Lab\\'s printer'", "''"]),
        call("PrinterSetEnabled", ["'Lab'", "true"]),
        call("PrinterSetAcceptJobs", ["'Lab'", "true", "''"])]);
    assert.deepEqual(plain(logic.defaultSteps("Office")), [call("PrinterSetDefault", ["'Office'"])]);
    assert.deepEqual(plain(logic.removeSteps("Office")), [call("PrinterDelete", ["'Office'"])]);
    assert.deepEqual(plain(logic.findSteps()), [call("DevicesGet", ["10", "32", "@as []", "@as []"])]);

    // A change: every step in order; a failure ends it where it failed.
    const ok = { ok: true, value: [""] };
    let op = logic.opBegin("add", "Lab", logic.addSteps("Lab", "ipp://lab.local/ipp/print", "Lab"));
    assert.equal(op.phase, "running");
    op = logic.opAdvance(op, ok);
    assert.deepEqual([op.phase, op.index], ["running", 1]);
    op = logic.opAdvance(op, ok);
    op = logic.opAdvance(op, ok);
    assert.deepEqual([op.phase, op.problem], ["done", ""]);
    assert.throws(() => logic.opAdvance(op, ok), /a step ended while the change is done/);
    // A refusal past PrinterAdd leaves the queue: the change says so.
    const added = logic.opAdvance(logic.opAdvance(logic.opBegin("add", "Lab", logic.addSteps("Lab", "ipp://lab.local/ipp/print", "Lab")), ok), { ok: false, problem: "refused", detail: "" });
    assert.deepEqual([added.phase, added.problem], ["failed", "added-stopped"]);
    const atAdd = logic.opAdvance(logic.opBegin("add", "Lab", logic.addSteps("Lab", "ipp://lab.local/ipp/print", "Lab")), { ok: false, problem: "refused", detail: "" });
    assert.deepEqual([atAdd.phase, atAdd.problem], ["failed", "refused"]);
    const refused = logic.opAdvance(logic.opBegin("default", "Lab", logic.defaultSteps("Lab")), { ok: false, problem: "refused", detail: "" });
    assert.deepEqual([refused.phase, refused.problem, refused.index], ["failed", "refused", 0]);
    assert.deepEqual(plain(logic.opView(refused)), { kind: "default", target: "Lab", phase: "failed", problem: "refused" });
    for (const key of Object.keys(logic.PROBLEM_TEXT)) assert.notEqual(logic.problemText(key), "", "a sentence for " + key);
    assert.equal(logic.problemText(""), "");
    assert.equal(logic.problemText("unheard-of"), logic.PROBLEM_TEXT.failed);

    // The pane's view leases: each end closes its own lease once.
    let views = logic.viewIdle();
    const first = logic.viewBegin(views);
    const second = logic.viewBegin(first.state);
    assert.deepEqual([first.id, second.id], [1, 2]);
    assert.deepEqual(plain(second.state.leases), [1, 2]);
    assert.deepEqual(plain(logic.viewEnd(second.state, 2).state.leases), [1]);
    const ended = logic.viewEnd(second.state, 1);
    assert.deepEqual([ended.known, plain(ended.state.leases)], [true, [2]]);
    assert.deepEqual([logic.viewEnd(ended.state, 1).known, plain(logic.viewEnd(ended.state, 1).state.leases)], [false, [2]]);
    assert.deepEqual(plain(logic.viewEnd(ended.state, 2).state.leases), []);
    assert.equal(logic.viewBegin(logic.viewEnd(ended.state, 2).state).id, 3);

    // Driverless addresses.
    for (const [uri, want] of [
        ["ipp://lab.local:631/ipp/print", true],
        ["IPPS://lab.local/ipp/print", true],
        ["dnssd://Brother%20HL._ipp._tcp.local/?uuid=1", true],
        ["dnssd://Brother%20HL._ipps._tcp.local/?uuid=1", true],
        ["dnssd://Brother%20HL._pdl-datastream._tcp.local/", false],
        ["usb://Brother/HL-L2350DW?serial=E7", false],
        ["socket://192.0.2.9", false],
        ["ipp", false]
    ]) assert.equal(logic.driverless(uri), want, uri);

    // Found devices: CUPS's order, no backend entry, no installed URI.
    const dictionary = logic.parseGVariant(devices.trim())[1];
    dictionary["device-class:3"] = "network";
    dictionary["device-info:3"] = "Internet Printing Protocol (ipp)";
    dictionary["device-uri:3"] = "ipp";
    assert.deepEqual(plain(logic.foundDevices(dictionary, [{ uri: "socket://192.0.2.9" }])), [
        { key: "ipp://lab.local:631/ipp/print", uri: "ipp://lab.local:631/ipp/print", info: "Lab Printer", make: "HP LaserJet", driverless: true },
        { key: "usb://Brother/HL-L2350DW?serial=E7", uri: "usb://Brother/HL-L2350DW?serial=E7", info: "Brother HL-L2350DW", make: "Brother HL-L2350DW", driverless: false }]);
    assert.deepEqual(plain(logic.foundDevices({ "device-uri:0": "ipp://a/ipp/print", "device-info:0": "Line\none" }, [])).map(d => d.info), ["Line one"]);
    const shown = logic.foundShown(logic.foundDevices(dictionary, []), [{ uri: "ipp://lab.local:631/ipp/print" }]);
    assert.deepEqual(plain(shown.map(d => d.uri)), ["usb://Brother/HL-L2350DW?serial=E7", "socket://192.0.2.9"]);

    for (const [text, taken, want] of [
        ["Lab Printer", [], "Lab_Printer"],
        ["HP LaserJet 400 (M401)", [], "HP_LaserJet_400_M401"],
        ["Büro", [], "B_ro"],
        ["  ", [], "Printer"],
        ["lab.local", [], "lab.local"],
        ["Lab", ["lab"], "Lab_2"],
        ["Lab", ["Lab", "Lab_2"], "Lab_3"],
        ["#/", [], "Printer"],
        ["x".repeat(200), [], "x".repeat(100)]
    ]) assert.equal(logic.queueName(text, taken), want, text);

    for (const [text, want] of [
        ["printer.local", { ok: true, uri: "ipp://printer.local/ipp/print", host: "printer.local" }],
        [" 192.0.2.7 ", { ok: true, uri: "ipp://192.0.2.7/ipp/print", host: "192.0.2.7" }],
        ["printer.local:8631", { ok: true, uri: "ipp://printer.local:8631/ipp/print", host: "printer.local" }],
        ["ipps://printer.local/ipp/print", { ok: true, uri: "ipps://printer.local/ipp/print", host: "printer.local" }],
        ["IPP://printer.local/", { ok: true, uri: "ipp://printer.local/ipp/print", host: "printer.local" }],
        ["ipp://[2001:db8::7]:631/printers/lab", { ok: true, uri: "ipp://[2001:db8::7]:631/printers/lab", host: "[2001:db8::7]" }],
        ["", { ok: false, problem: "address" }],
        ["printer local", { ok: false, problem: "address" }],
        ["lpd://printer.local/queue", { ok: false, problem: "scheme" }],
        ["user@printer.local", { ok: false, problem: "address" }],
        ["printer.local:99999", { ok: false, problem: "address" }],
        ["-printer", { ok: false, problem: "address" }],
        ["printer.local/a\tb", { ok: false, problem: "address" }]
    ]) assert.deepEqual(plain(logic.addressDevice(text)), want, JSON.stringify(text));

    // The Setup step `printing`: To do with Turn on printing while the step
    // applies, Not available (`available: false`) wherever the user cannot
    // act, each with its own hint, which the status judge requires
    // (PluginLogic.statusDeclarationFits), and while CUPS is missing with a
    // link to the Setup tab, whose Optional tools step installs it.
    const read = n => ({ state: "read", printers: Array.from({ length: n }, (_, i) => ({ name: "P" + i })) });
    for (const [name, reading, step, want] of [
        ["no printer", read(0), "ready", { tone: "ok", text: "No printers" }],
        ["one printer", read(1), "ready", { tone: "ok", text: "1 printer" }],
        ["two printers", read(2), "ready", { tone: "ok", text: "2 printers" }]
    ]) assert.deepEqual(plain(logic.printingView(reading, false, step)), want, name);
    const INSTALL = "page:vgs.printers/Setup";
    const shape = value => ({
        available: value.available !== false,
        tone: value.tone,
        action: value.action === undefined ? "none" : value.action === true ? "declared" : "other",
        link: (/\]\((page:[^)]*)\)/.exec(value.hint ?? "") ?? [null, null])[1]
    });
    const todo = (tone, action, link) => ({ available: true, tone, action, link });
    const unavailable = (tone, link) => ({ available: false, tone, action: "none", link: link ?? null });
    const down = { state: "down" };
    const failed = { state: "failed", reason: "line" };
    for (const [name, reading, missing, step, want] of [
        ["unread", { state: "unread" }, false, "", todo("info", "none", null)],
        ["read", read(1), false, "ready", todo("ok", "none", null)],
        ["not installed links the install", { state: "unread" }, true, "needed", unavailable("warning", INSTALL)],
        ["not installed, printing off", down, true, "denied", unavailable("warning", INSTALL)],
        ["off, step needed", down, false, "needed", todo("warning", "declared", null)],
        ["off, on NixOS", down, false, "nixos", todo("warning", "declared", null)],
        ["off, step denied", down, false, "denied", unavailable("warning")],
        ["off, step unknown", down, false, "unknown", unavailable("warning")],
        ["off, step absent", down, false, "absent", unavailable("warning")],
        ["off, step ready", down, false, "ready", unavailable("warning")],
        ["failed", failed, false, "needed", unavailable("danger")]
    ]) {
        const value = plain(logic.printingView(reading, missing, step));
        assert.deepEqual(shape(value), want, name);
        if (value.available === false) assert.ok(typeof value.hint === "string" && value.hint !== "", name + " says why");
    }
    assert.throws(() => logic.printingView({ state: "other" }, false, ""), /reading state "other"/);
    // Before the core's first probe the step has no reading (""): printing
    // that is off publishes nothing, so Setup reads Checking, never the
    // failed check's Not available.
    assert.equal(logic.printingView(down, false, ""), null, "off with no step reading publishes nothing");

    const rows = logic.printerRows(logic.withDefault(logic.lpstatReading(0, busy), "Lab").printers);
    assert.deepEqual(plain(rows.map(r => [r.key, r.secondary, r.iconName, r.badge])), [
        ["Lab", "Stopped", "printer-x", "Default"],
        ["Office", "Printing · 2 jobs", "printer", ""],
        ["Office-2", "Stopped: Paper jam · 1 job", "printer-x", ""],
        ["Spare", "Holding new jobs", "printer", ""]]);
    assert.deepEqual(plain(rows.map(r => r.secondaryTone)), ["danger", "", "danger", ""]);
    for (const [cups, want] of [["missing", false], ["read", true], ["down", true], ["failed", true], ["unread", true]])
        assert.equal(logic.settingsOffered(cups), want, "Print Settings offered while " + cups);
    assert.equal(logic.printerAction(rows[0]), null);
    assert.deepEqual(plain(logic.printerAction(rows[1])), { text: "Set as default" });
    assert.deepEqual(plain(logic.printerMenu(rows[0]).map(e => e.key)), ["remove"]);
    assert.deepEqual(plain(logic.printerMenu(rows[1]).map(e => e.key)), ["default", "remove"]);
    const foundRows = logic.foundRows(logic.foundDevices(dictionary, []));
    assert.deepEqual(plain(foundRows.map(r => logic.foundAction(r).text)), ["Add", "Print Settings", "Print Settings"]);
}

suite(load(file));
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "printers-logic-"));
try {
    const source = fs.readFileSync(file, "utf8");
    for (const [name, needle, replacement] of [
        ["the scheduler line is not read", 'if (lines[0] === "scheduler is not running") return { state: "down" };', ""],
        ["a job counts for no printer", "jobs[m[1]] = (jobs[m[1]] || 0) + 1;", ""],
        ["lpstat's own no-message line is a message", 'if (last.message === "" && m[1].trim() !== "reason unknown")', 'if (last.message === "")'],
        ["a printer holding new jobs fails the reading", "is idle|is holding new jobs|", "is idle|"],
        ["an instance line adds a printer", 'instance = m[1].indexOf("/") !== -1;', "instance = false;"],
        ["the default's line is not read", "return { ok: true, name: m === null ? \"\" : m[1] };", "return { ok: true, name: \"\" };"],
        ["the default marks no printer", "isDefault: p.name === name,", "isDefault: false,"],
        ["a refusal past PrinterAdd says nothing changed", 'next.problem = op.kind === "add" && op.index > 0 ? "added-stopped" : reply.problem;', "next.problem = reply.problem;"],
        ["a found device a printer uses is shown", "return devices.filter(function (d) { return !printers.some(function (p) { return p.uri === d.uri; }); });", "return devices;"],
        ["printing that is not installed reads as such", "    if (cupsMissing) return", "    if (false) return"],
        ["printing an administrator turned off reads To do", 'text: "Turned off", available: false,', 'text: "Turned off",'],
        ["a step that is not available gives no reason", 'available: false,\n        hint: "VGS could not read your printers. Turn Printers off and on to try again." };', "available: false };"],
        ["a refused prompt reads as a plain failure", '{ kind: "refused", pattern:', '{ kind: "failed", pattern:'],
        ["a string argument goes unquoted", "function quoted(s) { return \"'\" +", "function quoted(s) { return \"\" + String(s); return \"'\" +"],
        ["a new queue is left stopped", '        helperArgv("PrinterSetEnabled", [quoted(name), "true"]),\n', ""],
        ["the change runs on past a failure", "        next.index = op.index;\n        next.phase = \"failed\";", "        next.index = op.index;\n        next.phase = \"running\";"],
        ["a DNS-SD printer of any type is driverless", "return /\\._ipps?\\._tcp(\\.|$)/.test(host);", "return true;"],
        ["an installed printer is found again", "installed.indexOf(uri) !== -1", "false"],
        ["a taken name is taken again", "lower.indexOf(name.toLowerCase()) !== -1", "false"],
        ["another scheme passes the field", 'if (scheme !== "ipp" && scheme !== "ipps") return { ok: false, problem: "scheme" };', ""],
        ["an address keeps no default path", 'if (path === "" || path === "/") path = DEFAULT_PATH;', ""],
        ["Turn on printing offered while the step is ready", 'if (step === "needed" || step === "nixos") return', "if (true) return"],
        ["a step with no reading reads as a failed check", '        if (step === "") return null;\n', ""],
        ["a view's end closes another lease", "leases.splice(at, 1);", "leases.splice(0, 1);"],
        ["a view's end of an unknown lease closes one", "if (at === -1) return { state: state, known: false };", "if (at === -1) at = 0;"],
        ["a stopped printer's state draws in the plain tone", 'secondaryTone: p.state === "stopped" ? "danger" : "",', 'secondaryTone: "",'],
        ["Print Settings offered without CUPS", 'function settingsOffered(cups) { return cups !== "missing"; }', "function settingsOffered(cups) { return true; }"],
        ["the default printer loses its badge", 'badge: p.isDefault ? "Default" : "",', 'badge: "",']
    ]) {
        assert.equal(source.split(needle).length - 1, 1, name + " mutation must match once");
        const mutant = path.join(scratch, "PrintersLogic.js");
        fs.writeFileSync(mutant, source.replace(needle, replacement));
        assert.throws(() => suite(load(mutant)), assert.AssertionError, "control: " + name);
        console.log("printers-logic: control=" + name + " red");
    }
} finally { fs.rmSync(scratch, { recursive: true, force: true }); }
console.log("printers-logic: passed");
