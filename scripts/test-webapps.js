#!/usr/bin/env node
// Checks for vgs.webapps' `open`: the app's window is looked for among the
// windows Hyprland's reply lists, never among Quickshell's
// Hyprland.toplevels, which can keep a closed window
// (docs/architecture/runtime-hyprland.md). windowOf and
// windowsRead run as Service.qml holds them, with WebApps.js loaded through
// bin/lib/qml-library.js, against a model that keeps a closed window of the
// app. The control reads that model, as the service once did, and the
// suite must fail on it. Exit 1 when a row or the control fails.
"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const { load } = require("../bin/lib/qml-library.js");

const DIR = path.join(__dirname, "..", "shell", "plugins", "vgs.webapps");
const WebApps = load(path.join(DIR, "WebApps.js"));
const service = fs.readFileSync(path.join(DIR, "Service.qml"), "utf8");

let failures = 0;
function report(name, got, want) {
    const g = JSON.stringify(got), w = JSON.stringify(want);
    if (g === w) { console.log("  ok    " + name); return; }
    failures += 1;
    console.log("  FAIL  " + name + "\n        got  " + g + "\n        want " + w);
}

// The text of one QML function, from its header to the line that closes it.
function functionText(source, header) {
    const start = "    function " + header + " {\n";
    const parts = source.split(start);
    if (parts.length !== 2) throw new Error("function " + header + " occurs " + (parts.length - 1) + " times");
    return "function " + header + " {\n" + parts[1].split("\n    }\n")[0] + "\n}\n";
}

const apps = WebApps.apps([{ name: "smoke-mail", url: "https://mail.example.test/inbox" }]).good;
if (apps.length !== 1) throw new Error("the fixture app is refused");
const appClass = "chrome-mail.example.test__inbox-Default";
const closed = { address: "0xdead", lastIpcObject: { address: "0xdead", class: appClass } };

// What one `open` of the app does, given Hyprland's reply STATE.
function opened(source, state) {
    const calls = { reveal: [], looks: 0, errors: [] };
    const context = {
        WebApps,
        Hyprland: { toplevels: { values: [closed] } },
        shell: { compositor: { reveal: (addresses, awaitSender) => { calls.reveal.push(addresses); return "ok"; } } },
        current: () => ({ good: apps }),
        lookForBrowser: () => { calls.looks += 1; },
        launching: {},
        opening: [],
        console: { error: text => calls.errors.push(text), warn: text => calls.errors.push(text) },
    };
    vm.runInNewContext(functionText(source, "windowOf(clients, app)") + functionText(source, "windowsRead(name, state)")
        + "windowsRead(\"smoke-mail\", state);", Object.assign(context, { state }));
    return { reveal: calls.reveal, looks: calls.looks, opening: context.opening, errors: calls.errors.length };
}

function suite(source, check) {
    const live = { address: "0xbeef", class: appClass, mapped: true };
    const other = { address: "0xcafe", class: "smoke.other", mapped: true };
    // rows: [name, Hyprland's reply, what the open does]
    const rows = [
        ["a window of the app in the reply is brought into view", { ok: true, clients: [other, live] }, { reveal: [["0xbeef"]], looks: 0, opening: [], errors: 0 }],
        ["a closed window the model keeps opens the site", { ok: true, clients: [other] }, { reveal: [], looks: 1, opening: ["smoke-mail"], errors: 0 }],
        ["no window opens the site", { ok: true, clients: [] }, { reveal: [], looks: 1, opening: ["smoke-mail"], errors: 0 }],
        ["a failed read opens nothing and logs", { ok: false, error: "refused: windows=read-failed windows=failed status=1" }, { reveal: [], looks: 0, opening: [], errors: 1 }],
    ];
    for (const [name, state, want] of rows) check(name, opened(source, state), want);
}
suite(service, report);

// The control: windowOf reads Quickshell's model, as before.
const reader = functionText(service, "windowOf(clients, app)");
const model = "function windowOf(clients, app) {\n"
    + "    for (const toplevel of Hyprland.toplevels.values)\n"
    + "        if (WebApps.classMatches(toplevel.lastIpcObject[\"class\"], app.url)) return String(toplevel.address);\n"
    + "    return \"\";\n}\n";
const mutant = service.replace(reader.replace(/^function /, "    function ").replace(/\n\}\n$/, "\n    }\n"), () => model.replace(/^function /, "    function ").replace(/\n\}\n$/, "\n    }\n"));
report("control: the model copy changes the service", mutant !== service, true);
let red = 0;
try {
    suite(mutant, (name, got, want) => { if (JSON.stringify(got) !== JSON.stringify(want)) red += 1; });
} catch (e) {
    red += 1;
}
report("control: the suite fails when windowOf reads Hyprland.toplevels", red > 0, true);

if (failures > 0) { console.log("test-webapps: " + failures + " failing"); process.exit(1); }
console.log("test-webapps: ok");
