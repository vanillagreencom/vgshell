#!/usr/bin/env node
// Controls for scripts/kendex-pin.js, the reading of the kendex release pin
// against the newest kendex release. Each row runs the reading in a child
// node with a stand-in `curl` first on PATH that answers canned release
// JSON, so no row touches the network. The shipped pin is read from
// shell/Core/PackageManagers.js, and each table copy rewrites that pin, so
// the rows hold through every pin move.
//
// - The shipped table against a newest release equal to its pin is current.
// - A copy pinned below the newest release is behind (the must-fail
//   control), and so is one whose pin is below by number but not by text.
// - The shipped table against an older newest release is ahead, a refusal.
// - A copy whose rpm-file row pins another version, whose deb-file url
//   names no release of its version, or whose deb-file row has no releases
//   list, is refused, and so is a copy that does not parse: exit 2, never
//   exit 1, which reads as behind.
// - A curl that fails, a status other than 200, a body that is no JSON and
//   a tag that is no version are unreadable, exit 77.
"use strict";
const assert = require("node:assert/strict");
const cp = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const repo = path.join(__dirname, "..");
const READING = path.join(repo, "scripts", "kendex-pin.js");
const TABLE = path.join(repo, "shell", "Core", "PackageManagers.js");
const LATEST = "https://api.github.com/repos/vanillagreencom/kendex/releases/latest";
const shipped = fs.readFileSync(TABLE, "utf8");
const pin = load(TABLE).managerRow("deb-file").files.releases.find(r => r.name === "kendex").version;
const major = pin.split(".")[0];
// A version below PIN: its last nonzero part less one.
function below(version) {
    const parts = version.split(".").map(Number);
    const at = parts.map(n => n !== 0).lastIndexOf(true);
    assert.notEqual(at, -1, "pin " + version + " has no version below it");
    parts[at] -= 1;
    return parts.join(".");
}

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "test-kendex-pin-"));
process.on("exit", () => fs.rmSync(tmp, { recursive: true, force: true }));
const tools = path.join(tmp, "tools");
fs.mkdirSync(tools);
// The stand-in answers only the latest-release endpoint, so a reading of any
// other release list fails its row.
fs.writeFileSync(path.join(tools, "curl"), [
    "#!/bin/sh",
    "for last in \"$@\"; do :; done",
    "[ \"$last\" = \"$STUB_URL\" ] || { echo \"stub curl: url=$last\" >&2; exit 99; }",
    "[ \"$STUB_EXIT\" = 0 ] || { echo \"curl: (7) Failed to connect\" >&2; exit \"$STUB_EXIT\"; }",
    "cat -- \"$STUB_BODY\"",
    "printf '\\n%s' \"$STUB_CODE\"",
    ""].join("\n"), { mode: 0o755 });

// TEXT with each of the COUNT occurrences of FROM replaced by TO.
function swap(text, from, to, count) {
    const found = text.split(from).length - 1;
    assert.equal(found, count, "table copy: " + JSON.stringify(from) + " occurs " + found + " times");
    return text.split(from).join(to);
}
const pinText = version => ["version: \"" + version + "\"", "/releases/download/v" + version + "/"];
// The shipped table, both rows pinned to VERSION.
function pinnedTo(version) {
    let text = shipped;
    pinText(pin).forEach((from, i) => { text = swap(text, from, pinText(version)[i], 2); });
    return text;
}
// The shipped table with EDIT applied to the rpm-file row and every row after
// it (TAIL true) or to every row before it.
function split(edit, tail) {
    const parts = shipped.split("id: \"rpm-file\"");
    assert.equal(parts.length, 2, "table copy: the rpm-file row occurs " + (parts.length - 1) + " times");
    if (tail) parts[1] = edit(parts[1]); else parts[0] = edit(parts[0]);
    return parts.join("id: \"rpm-file\"");
}
const lower = below(pin);
const copies = {
    lowered: pinnedTo(lower),
    narrow: pinnedTo(major + ".9.0"),
    disagree: split(text => pinText(pin).reduce((t, from, i) => swap(t, from, pinText(lower)[i], 1), text), true),
    url: split(text => swap(text, "/releases/download/v" + pin + "/", "/releases/download/v" + lower + "/", 1), false),
    shape: split(text => swap(text, "releases: [", "release: [", 1), false),
    syntax: split(text => swap(text, "releases: [", "releases: [[", 1), false),
};
for (const [name, text] of Object.entries(copies)) fs.writeFileSync(path.join(tmp, name + ".js"), text);

const release = tag => JSON.stringify({ tag_name: tag, name: tag, draft: false, prerelease: false });
// name, table copy (null for the shipped table), body, status code, curl
// exit, wanted exit, wanted stdout, wanted stderr (a RegExp where the line
// carries the error's own message after its key).
const ROWS = [
    ["the shipped pin at the newest release is current", null, release("v" + pin), "200", 0, 0, "kendex-pin: pin=" + pin + " newest=" + pin + " status=current\n", ""],
    ["a lowered pin is behind", "lowered", release("v" + pin), "200", 0, 1, "kendex-pin: pin=" + lower + " newest=" + pin + " status=behind\n", ""],
    ["a pin below by number but not by text is behind", "narrow", release("v" + major + ".10.0"), "200", 0, 1, "kendex-pin: pin=" + major + ".9.0 newest=" + major + ".10.0 status=behind\n", ""],
    ["a pin ahead of the newest release is refused", null, release("v" + lower), "200", 0, 2, "kendex-pin: pin=" + pin + " newest=" + lower + " status=ahead\n", ""],
    ["rows that pin two versions are refused", "disagree", release("v" + pin), "200", 0, 2, "", "kendex-pin: refused: pins-disagree deb-file=" + pin + " rpm-file=" + lower + "\n"],
    ["a url naming another release is refused", "url", release("v" + pin), "200", 0, 2, "", "kendex-pin: refused: url=\"https://github.com/vanillagreencom/kendex/releases/download/v" + lower + "/\" manager=deb-file\n"],
    ["a row with no releases list is refused", "shape", release("v" + pin), "200", 0, 2, "", "kendex-pin: refused: release=missing manager=deb-file\n"],
    ["a table that does not parse is refused", "syntax", release("v" + pin), "200", 0, 2, "", /^kendex-pin: refused: error=SyntaxError message="[^\n]*"\n$/],
    ["a failed curl is unreadable", null, "", "000", 7, 77, "", "kendex-pin: unreadable: transport=7 url=" + LATEST + "\n"],
    ["a rate-limited answer is unreadable", null, "{\"message\":\"API rate limit exceeded\"}", "403", 0, 77, "", "kendex-pin: unreadable: http=\"403\" url=" + LATEST + "\n"],
    ["a body that is no JSON is unreadable", null, "<html>", "200", 0, 77, "", "kendex-pin: unreadable: json url=" + LATEST + "\n"],
    ["a tag that is no version is unreadable", null, release("nightly"), "200", 0, 77, "", "kendex-pin: unreadable: tag=\"nightly\" url=" + LATEST + "\n"],
];

let failures = 0;
ROWS.forEach(([name, copy, body, code, curlExit, wantExit, wantOut, wantErr], i) => {
    const bodyFile = path.join(tmp, "body-" + i);
    fs.writeFileSync(bodyFile, body);
    const run = cp.spawnSync(process.execPath, [READING, ...(copy === null ? [] : ["--table", path.join(tmp, copy + ".js")])], {
        encoding: "utf8", timeout: 30000,
        env: { PATH: tools + ":" + path.dirname(process.execPath) + ":/usr/bin:/bin", HOME: tmp, TMPDIR: tmp, LC_ALL: "C",
            STUB_URL: LATEST, STUB_BODY: bodyFile, STUB_CODE: code, STUB_EXIT: String(curlExit) },
    });
    const got = { status: run.status, stdout: run.stdout, stderr: run.stderr };
    const want = { status: wantExit, stdout: wantOut, stderr: wantErr instanceof RegExp ? String(wantErr) : wantErr };
    const errOk = wantErr instanceof RegExp ? wantErr.test(run.stderr) : run.stderr === wantErr;
    if (run.status === wantExit && run.stdout === wantOut && errOk) console.log("ok " + name);
    else { failures++; console.log("FAIL " + name + ": got " + JSON.stringify(got) + " want " + JSON.stringify(want)); }
});
if (failures > 0) { console.log("test-kendex-pin: failed=" + failures); process.exit(1); }
console.log("test-kendex-pin: ok");
