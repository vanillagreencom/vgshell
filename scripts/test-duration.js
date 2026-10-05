#!/usr/bin/env node
// The shared duration contract used by plugin labels, history and notices.
// The controls edit disposable copies and require this table to fail.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");
const file = path.join(__dirname, "..", "shell", "Commons", "Duration.js");

const CASES = [
    [0, "0s"], [1, "1s"], [59, "59s"],
    [60, "1m 0s"], [61, "1m 1s"], [3599, "59m 59s"],
    [3600, "1h 0m"], [3601, "1h 0m"], [3660, "1h 1m"], [86399, "23h 59m"],
    [86400, "1d 0h"], [86401, "1d 0h"], [90000, "1d 1h"], [90180, "1d 1h"], [345600, "4d 0h"]
];
function verify(duration) {
    for (const [seconds, text] of CASES) assert.equal(duration.format(seconds), text, "seconds=" + seconds);
    for (const [seconds, text] of [[0, "0s"], [59, "59s"], [60, "1m"], [3600, "1h"], [86400, "1d"]])
        assert.equal(duration.format(seconds, 1), text, "one part seconds=" + seconds);
}
verify(load(file));
const CONTROLS = [
    ["space before unit", ' + units[i][1]', ' + " " + units[i][1]'],
    ["minute abbreviation", '[60, "m"]', '[60, "min"]'],
    ["unit boundary", 'seconds < units[first][0]', 'seconds <= units[first][0]'],
    ["largest two units", 'maximumParts === undefined ? 2', 'maximumParts === undefined ? 3']
];
const source = fs.readFileSync(file, "utf8");
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "duration-control-"));
try {
    for (const [name, needle, replacement] of CONTROLS) {
        assert.equal(source.split(needle).length - 1, 1, name + " match count");
        const copy = path.join(scratch, "Duration.js");
        fs.writeFileSync(copy, source.replace(needle, replacement));
        assert.throws(() => verify(load(copy)), assert.AssertionError, name + " must fail");
        console.log("  ok    control: " + name + " turns red");
    }
} finally {
    fs.rmSync(scratch, { recursive: true, force: true });
}
console.log("test-duration: ok");
