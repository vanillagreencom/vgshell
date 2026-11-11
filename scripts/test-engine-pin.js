#!/usr/bin/env node
// Controls for scripts/engine-pin.js, the reading of the Quickshell engine
// pin against the newest upstream release. Each row runs the reading in a
// child node with a stand-in `git` first on PATH that answers a canned tag
// list, so no row touches the network. The shipped pin is read from
// packaging/arch/vgshell-quickshell/PKGBUILD, and each recipe copy rewrites
// that pin, so the rows hold through every pin move.
//
// - The shipped recipe against its own release is current, and so is a pin
//   at a commit past the newest release.
// - A pin below the newest release is behind (the must-fail control), and
//   so is one below by number but not by text, past a release candidate.
// - A pin ahead of the newest release is refused.
// - A failed git, an empty or candidate-only tag list and an answer that is
//   no tag list are unreadable, exit 77.
// - A recipe whose pkgver is no version, that has no pkgver, whose url is no
//   https url, or that cannot be read is refused: exit 2, never exit 1,
//   which reads as behind.
"use strict";
const assert = require("node:assert/strict");
const cp = require("node:child_process");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const repo = path.join(__dirname, "..");
const READING = path.join(repo, "scripts", "engine-pin.js");
const RECIPE = path.join(repo, "packaging", "arch", "vgshell-quickshell", "PKGBUILD");
// The repository the recipe's source builds from: `git+$url.git`.
const UPSTREAM = "https://git.outfoxxed.me/quickshell/quickshell.git";
const shipped = fs.readFileSync(RECIPE, "utf8");
const pkgverLine = shipped.split("\n").filter(line => line.startsWith("pkgver="));
assert.equal(pkgverLine.length, 1, "recipe: " + pkgverLine.length + " pkgver lines");
const pkgver = pkgverLine[0].slice("pkgver=".length);
const release = /^[0-9]+(\.[0-9]+)*/.exec(pkgver)[0];

const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "test-engine-pin-"));
process.on("exit", () => fs.rmSync(tmp, { recursive: true, force: true }));
const tools = path.join(tmp, "tools");
fs.mkdirSync(tools);
// The stand-in answers only a tag listing of the upstream repository, so a
// reading of any other repository or ref list fails its row.
fs.writeFileSync(path.join(tools, "git"), [
    "#!/bin/sh",
    "[ \"$*\" = \"ls-remote --tags --refs -- $STUB_URL\" ] || { echo \"stub git: args=$*\" >&2; exit 99; }",
    "[ \"$STUB_EXIT\" = 0 ] || { echo \"fatal: unable to access '$STUB_URL'\" >&2; exit \"$STUB_EXIT\"; }",
    "cat -- \"$STUB_BODY\"",
    ""].join("\n"), { mode: 0o755 });

// The shipped recipe with its one FROM replaced by TO.
function swap(from, to) {
    const found = shipped.split(from).length - 1;
    assert.equal(found, 1, "recipe copy: " + JSON.stringify(from) + " occurs " + found + " times");
    return shipped.split(from).join(to);
}
const at = version => swap("pkgver=" + pkgver + "\n", "pkgver=" + version + "\n");
const copies = {
    past: at("1.2.3.r7.g2b4501a"),
    plain: at("1.2.3"),
    narrow: at("0.9.1"),
    malformed: at("1.2.3-1"),
    missing: swap("pkgver=" + pkgver + "\n", ""),
    url: swap("url='https://git.outfoxxed.me/quickshell/quickshell'\n", "url='git://git.outfoxxed.me/quickshell/quickshell'\n"),
};
for (const [name, text] of Object.entries(copies)) fs.writeFileSync(path.join(tmp, name), text);

// A git ls-remote answer listing TAGS.
const tags = (...names) => names.map((name, i) => String(i + 1).repeat(40).slice(0, 40) + "\trefs/tags/" + name + "\n").join("");
const ok = (pin, newest, status) => "engine-pin: pin=" + pin + " newest=" + newest + " status=" + status + "\n";
const lost = key => "engine-pin: unreadable: " + key + " url=" + UPSTREAM + "\n";
// name, recipe copy (null for the shipped recipe, a path for any other),
// git answer, git exit, wanted exit, wanted stdout, wanted stderr (a RegExp
// where the line carries the error's own message after its key).
const ROWS = [
    ["the shipped pin at its release is current", null, tags("v0.1.0", "v" + release), 0, 0, ok(pkgver, release, "current"), ""],
    ["a pin at a commit past the newest release is current", "past", tags("v1.2.2", "v1.2.3"), 0, 0, ok("1.2.3.r7.g2b4501a", "1.2.3", "current"), ""],
    ["a pin below the newest release is behind", "plain", tags("v1.2.3", "v1.3.0"), 0, 1, ok("1.2.3", "1.3.0", "behind"), ""],
    ["a commit past an older release is behind", "past", tags("v1.2.3", "v1.2.4"), 0, 1, ok("1.2.3.r7.g2b4501a", "1.2.4", "behind"), ""],
    ["the newest release is the highest by number, past a candidate", "narrow", tags("v0.10.0", "v0.9.1", "v0.11.0-rc1", "nightly"), 0, 1, ok("0.9.1", "0.10.0", "behind"), ""],
    ["a pin ahead of the newest release is refused", "plain", tags("v1.2.2"), 0, 2, ok("1.2.3", "1.2.2", "ahead"), ""],
    ["a failed git is unreadable", null, "", 128, 77, "", lost("transport=128")],
    ["an empty tag list is unreadable", null, "", 0, 77, "", lost("releases=none")],
    ["a tag list with no release is unreadable", null, tags("v0.4.0-rc1"), 0, 77, "", lost("releases=none")],
    ["an answer that is no tag list is unreadable", null, "<html>\n", 0, 77, "", lost("line=\"<html>\"")],
    ["a pkgver that is no version is refused", "malformed", tags("v1.2.3"), 0, 2, "", "engine-pin: refused: pkgver=\"1.2.3-1\"\n"],
    ["a recipe with no pkgver is refused", "missing", tags("v1.2.3"), 0, 2, "", "engine-pin: refused: pkgver-lines=0\n"],
    ["a url that is no https url is refused", "url", tags("v" + release), 0, 2, "", "engine-pin: refused: url=\"git://git.outfoxxed.me/quickshell/quickshell\"\n"],
    ["a recipe that cannot be read is refused", path.join(tmp, "absent"), tags("v" + release), 0, 2, "", /^engine-pin: refused: error=Error message="ENOENT[^\n]*"\n$/],
];

let failures = 0;
ROWS.forEach(([name, copy, body, gitExit, wantExit, wantOut, wantErr], i) => {
    const bodyFile = path.join(tmp, "body-" + i);
    fs.writeFileSync(bodyFile, body);
    const recipe = copy === null ? [] : ["--recipe", path.isAbsolute(copy) ? copy : path.join(tmp, copy)];
    const run = cp.spawnSync(process.execPath, [READING, ...recipe], {
        encoding: "utf8", timeout: 30000,
        env: { PATH: tools + ":" + path.dirname(process.execPath) + ":/usr/bin:/bin", HOME: tmp, TMPDIR: tmp, LC_ALL: "C",
            STUB_URL: UPSTREAM, STUB_BODY: bodyFile, STUB_EXIT: String(gitExit) },
    });
    const got = { status: run.status, stdout: run.stdout, stderr: run.stderr };
    const want = { status: wantExit, stdout: wantOut, stderr: wantErr instanceof RegExp ? String(wantErr) : wantErr };
    const errOk = wantErr instanceof RegExp ? wantErr.test(run.stderr) : run.stderr === wantErr;
    if (run.status === wantExit && run.stdout === wantOut && errOk) console.log("ok " + name);
    else { failures++; console.log("FAIL " + name + ": got " + JSON.stringify(got) + " want " + JSON.stringify(want)); }
});
if (failures > 0) { console.log("test-engine-pin: failed=" + failures); process.exit(1); }
console.log("test-engine-pin: ok");
