#!/usr/bin/env node
// The shared wording of a past moment (shell/Commons/Timestamp.js): under
// an hour before now it reads relative, as does a time under a minute
// ahead, since Time.now ticks once a minute; any other time as the bar clock in
// local time, with the year only outside now's year. The zone is fixed
// before any date is made, and is one where the local and the UTC day and
// year differ, so a reading in UTC fails the table. The controls edit
// disposable copies and require this table to fail.
"use strict";
process.env.TZ = "Asia/Tokyo";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");
const commons = path.join(__dirname, "..", "shell", "Commons");
const file = path.join(commons, "Timestamp.js");

const MINUTE = 60 * 1000;
const HOUR = 60 * MINUTE;
// Fri 9 Oct 2026, 00:19 in Tokyo.
const NOW = Date.UTC(2026, 9, 8, 15, 19);
// Fri 1 Jan 2027, 00:30 in Tokyo, still 2026 in UTC.
const NEW_YEAR = Date.UTC(2026, 11, 31, 15, 30);

// Each row: [name, time, now, text].
const CASES = [
    ["now", NOW, NOW, "just now"],
    ["under a minute", NOW - 59 * 1000, NOW, "just now"],
    ["one minute", NOW - MINUTE, NOW, "1m ago"],
    ["minutes", NOW - 12 * MINUTE - 30 * 1000, NOW, "12m ago"],
    ["just under an hour", NOW - HOUR + 1000, NOW, "59m ago"],
    ["exactly an hour", NOW - HOUR, NOW, "Thu 8 Oct, 23:19"],
    ["days ago", NOW - 3 * 24 * HOUR, NOW, "Tue 6 Oct, 00:19"],
    ["on the hour", Date.UTC(2026, 9, 1, 3, 0), NOW, "Thu 1 Oct, 12:00"],
    ["another year", Date.UTC(2025, 9, 8, 15, 19), NOW, "Thu 9 Oct 2025, 00:19"],
    ["inside the clock's minute", NOW + 30 * 1000, NOW, "just now"],
    ["a minute ahead", NOW + MINUTE, NOW, "Fri 9 Oct, 00:20"],
    ["ahead of now", NOW + 5 * MINUTE, NOW, "Fri 9 Oct, 00:24"],
    ["the local year", Date.UTC(2026, 11, 31, 13, 0), NEW_YEAR, "Thu 31 Dec 2026, 22:00"]
];

function verify(timestamp) {
    for (const [name, ms, now, text] of CASES) assert.equal(timestamp.text(ms, now), text, name);
}
verify(load(file));

const CONTROLS = [
    ["an hour old reads as the clock", "age < RELATIVE_MS", "age <= RELATIVE_MS"],
    ["under a minute reads just now", 'seconds < 60 ? "just now"', 'seconds < 0 ? "just now"'],
    ["a time ahead reads as the clock", "age >= 0 && ", ""],
    ["a time inside the clock's minute reads just now", 'if (age < 0 && age > -CLOCK_LAG_MS) return "just now";', ""],
    ["a minute ahead reads as the clock", "age > -CLOCK_LAG_MS", "age >= -CLOCK_LAG_MS"],
    ["the year shows outside now's year", "=== new Date(now).getFullYear()", "=== at.getFullYear()"],
    ["the hour is local", "twoDigits(at.getHours())", "twoDigits(at.getUTCHours())"],
    ["minutes keep two digits", "twoDigits(at.getMinutes())", "at.getMinutes()"]
];
const source = fs.readFileSync(file, "utf8");
const scratch = fs.mkdtempSync(path.join(os.tmpdir(), "timestamp-control-"));
try {
    fs.copyFileSync(path.join(commons, "Duration.js"), path.join(scratch, "Duration.js"));
    for (const [name, needle, replacement] of CONTROLS) {
        assert.equal(source.split(needle).length - 1, 1, name + " match count");
        const copy = path.join(scratch, "Timestamp.js");
        fs.writeFileSync(copy, source.replace(needle, replacement));
        assert.notEqual(fs.readFileSync(copy, "utf8"), source, name + " changed the copy");
        assert.throws(() => verify(load(copy)), assert.AssertionError, name + " must fail");
        console.log("  ok    control: " + name + " turns red");
    }
} finally {
    fs.rmSync(scratch, { recursive: true, force: true });
}
console.log("test-timestamp: ok");
