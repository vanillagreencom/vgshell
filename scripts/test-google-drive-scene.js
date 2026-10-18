#!/usr/bin/env node
// The googledrive scene of scripts/sandbox-shots.sh plants no status: it
// stages each Google Drive state through the plugin's own runner and waits
// for the plugin's GoogleDriveLogic.js to read the published values as that
// state. This check reads the scene's text, from its `# The googledrive
// scene` comment to the end of scene_googledrive, against that code:
//   cause        a state's `cs_shots MODE STATE CAUSE [KIND]` line names a
//                CAUSE GoogleDriveLogic.headline never returns.
//   kind         its KIND is not an error kind the code has words for.
//   state        a state the issue (VGS-1316) lists has no line: first-run,
//                no-keys, no-pair, empty-review, paused, syncing, error,
//                review, pairs-invalid, migrated and renamed.
//   state-write  a command line names the runner's state directory,
//                status.json or control.json and is not an `rm`: the
//                scene would hand the service a record no run wrote.
//   words        a command line holds a status word or sentence the code
//                publishes, which the scene would show rather than read.
// Each finding is one line `test-google-drive-scene: <key>=<value>`; a clean
// scene prints `test-google-drive-scene: ok states=<n>`. Exit 1 on a
// finding, 2 when the scene cannot be found. The controls then plant one
// defect per rule in a copy of the text and require that rule's finding.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const root = path.join(__dirname, "..");
const SHOTS = path.join(root, "scripts", "sandbox-shots.sh");
const L = load(path.join(root, "shell", "plugins", "vgs.google-drive", "GoogleDriveLogic.js"));
const ISSUE_STATES = ["first-run", "no-keys", "no-pair", "empty-review", "paused", "syncing", "error", "review", "pairs-invalid", "migrated", "renamed"];

// Every cause headline returns over each runner state, unit state, pair
// state, review count and data age.
function headlineCauses() {
    const causes = new Set();
    const now = Date.parse("2026-10-11T12:00:00Z");
    for (const state of L.STATES) for (const units of L.UNITS) for (const pair of [null].concat(L.PAIR_STATES))
        for (const conflictCount of [0, 1]) for (const staleAfter of [null, now - 1, now + 1]) {
            const pairs = pair === null ? [] : [{ id: "p", label: "P", remote: "P", state: pair, lastSuccess: null, staleAfter: staleAfter, lastError: null }];
            causes.add(L.headline({ state, units, staleAfter, pairs, conflictCount, lastError: null, paused: false }, now).cause);
        }
    return causes;
}

// The words the code publishes: each state's text, each error and
// conflict sentence, each review row's folder line before its path, and
// the review line without its count.
function publishedWords() {
    const views = Object.values(L.STATE_VIEW).concat([L.CURRENT, L.OUT_OF_DATE, L.NOT_SYNCED, L.NO_PAIRS]).map(v => v.text);
    return views.concat(Object.values(L.ERROR_TEXT), Object.values(L.PAGE_ERROR_TEXT), Object.values(L.CONFLICT_TEXT), Object.values(L.CONFLICT_FOLDER_TEXT),
        [L.ERROR_DEFAULT, L.reviewLine(2).replace(/^2 /, ""), L.reviewLine(1).replace(/^1 /, "")]);
}

function sceneOf(text) {
    const lines = text.split("\n");
    const start = lines.findIndex(l => l.startsWith("# The googledrive scene"));
    const fn = lines.findIndex(l => l.startsWith("scene_googledrive()"));
    if (start < 0 || fn < start) return null;
    const end = lines.findIndex((l, i) => i > fn && l === "}");
    return end < 0 ? null : lines.slice(start, end + 1);
}

function check(text) {
    const scene = sceneOf(text);
    if (scene === null) return { scene: false, findings: [] };
    const causes = headlineCauses(), kinds = new Set(Object.keys(L.ERROR_TEXT).concat(["none"])), words = publishedWords();
    const findings = [], states = [];
    // Heredoc bodies are stand-in programs, which hold no status.
    let heredoc = null;
    for (const line of scene) {
        if (heredoc !== null) { if (line === heredoc) heredoc = null; continue; }
        const open = /<<'?([A-Z]+)'?\s*$/.exec(line);
        const code = line.trim();
        if (code.startsWith("#")) continue;
        const shots = /^cs_shots "\$m" (\d+-)?([a-z-]+) ([a-z-]+)(?: ([a-z-]+))?$/.exec(code);
        if (shots !== null) {
            states.push(shots[2]);
            if (!causes.has(shots[3])) findings.push("cause=" + shots[2] + ":" + shots[3]);
            if (shots[4] !== undefined && !kinds.has(shots[4])) findings.push("kind=" + shots[2] + ":" + shots[4]);
        }
        if (/\.local\/state\/vgshell\/google-drive|status\.json|control\.json/.test(code) && !/^rm\s/.test(code)) findings.push("state-write=" + code);
        for (const word of words) if (code.includes(word)) findings.push("words=" + JSON.stringify(word));
        if (open !== null) heredoc = open[1];
    }
    for (const state of ISSUE_STATES) if (!states.includes(state)) findings.push("state=" + state);
    return { scene: true, findings, states: states.length };
}

const text = fs.readFileSync(SHOTS, "utf8");
const result = check(text);
if (!result.scene) {
    console.log("test-google-drive-scene: scene=missing path=scripts/sandbox-shots.sh");
    process.exit(2);
}
for (const f of result.findings) console.log("test-google-drive-scene: " + f);
if (result.findings.length > 0) process.exit(1);
console.log("test-google-drive-scene: ok states=" + result.states);

// Controls: one planted defect per rule, each on a copy of the text,
// requires that rule's finding.
function plant(from, to) {
    if (text.split(from).length !== 2) throw new Error("control: " + JSON.stringify(from) + " is not in the scene once");
    return text.replace(from, () => to);
}
const anchor = '  cs_shots "$m" 5-paused paused\n';
const controls = [
    ["cause", plant('cs_shots "$m" 8-review review\n', 'cs_shots "$m" 8-review reviewing\n'), "cause=review:reviewing"],
    ["kind", plant("9-pairs-invalid error pairs-invalid\n", "9-pairs-invalid error pairs-damaged\n"), "kind=pairs-invalid:pairs-damaged"],
    ["state", plant(anchor, ""), "state=paused"],
    ["state-write", plant(anchor, anchor + "  printf '{}' >\"$home/.local/state/vgshell/google-drive/status.json\"\n"), "state-write="],
    ["words", plant(anchor, anchor + '  echo "' + L.CURRENT.text + '" >"$cs/headline"\n'), "words=" + JSON.stringify(L.CURRENT.text)]
];
let failed = 0;
for (const [rule, mutant, want] of controls) {
    const got = check(mutant);
    if (got.scene && got.findings.some(f => f.startsWith(want))) console.log("test-google-drive-scene: control=" + rule + " red");
    else { console.log("test-google-drive-scene: control=" + rule + " stayed-green findings=" + JSON.stringify(got.findings)); failed++; }
}
const cut = check(text.replace(/^scene_googledrive\(\)/m, "scene_google()"));
if (cut.scene) { console.log("test-google-drive-scene: control=scene stayed-found"); failed++; }
else console.log("test-google-drive-scene: control=scene red");
process.exit(failed === 0 ? 0 : 1);
