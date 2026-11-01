#!/usr/bin/env node
// The package outcome channel between `vgshell-tui present` and the package
// owner it runs. The presenter makes one private empty file per recorded
// run and hands the owner its path in VGS_TUI_OUTCOME; the owner writes one
// whole outcome there after its last attempt; the presenter reads it once
// the command exits and puts the judged outcome in the run's ended record.
// shell/Core/PackageReview.js packageOutcome is the one judge of both ends.
//
//   pkg-outcome.js FILE RUN CODE
//       the presenter's read: the outcome FILE holds, judged against RUN
//       and its exit CODE, as one JSON line on stdout; nothing for an
//       empty file, a command that wrote none. A file that is not a
//       private regular file of this user, holds more than
//       PACKAGE_OUTCOME_MAX bytes, is not JSON or that the judge refuses
//       prints `vgshell-tui: package-outcome=unavailable reason=<key>` on
//       stderr and exits 1. A bad invocation exits 2.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const judge = require(path.join(__dirname, "qml-library.js")).load(path.join(__dirname, "..", "..", "shell", "Core", "PackageReview.js"));

// FD's file is a private regular file of this user with one name and at
// most MAX bytes; with EMPTY, also empty.
function privateFd(fd, max, empty) {
    const stat = fs.fstatSync(fd);
    return stat.isFile() && stat.nlink === 1 && stat.uid === process.getuid() && (stat.mode & 0o077) === 0 && stat.size <= max && (!empty || stat.size === 0);
}

// The owner's write: OUTCOME, judged against RUN and the exit STATUS it
// will exit with, to FILE, which must be the presenter's empty private
// file. Answers null once written, else the failure's key; the install
// already ran, so the caller reports it and keeps its status.
function write(file, outcome, run, status) {
    const judged = judge.packageOutcome(outcome, run, status);
    if (!judged.ok) return "judge=" + judged.error;
    let fd;
    try {
        fd = fs.openSync(file, fs.constants.O_WRONLY | fs.constants.O_NOFOLLOW);
    } catch (e) {
        return "open=" + e.code;
    }
    try {
        if (!privateFd(fd, 0, true)) return "file=unsafe";
        fs.writeSync(fd, JSON.stringify(judged.outcome) + "\n");
        return null;
    } finally {
        fs.closeSync(fd);
    }
}

function read(file, run, code) {
    const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
    try {
        if (!privateFd(fd, judge.PACKAGE_OUTCOME_MAX, false)) return { error: "file" };
        const text = fs.readFileSync(fd, "utf8");
        if (text === "") return { outcome: null };
        let value;
        try {
            value = JSON.parse(text);
        } catch (e) {
            return { error: "json" };
        }
        const judged = judge.packageOutcome(value, run, code);
        return judged.ok ? { outcome: judged.outcome } : { error: judged.error };
    } finally {
        fs.closeSync(fd);
    }
}

if (require.main === module) {
    const [file, run, code] = process.argv.slice(2);
    if (process.argv.length !== 5 || !path.isAbsolute(file) || !/^(0|[1-9][0-9]{0,2})$/.test(code)) {
        process.stderr.write("vgshell-tui: refused: package-outcome=arguments\n");
        process.exit(2);
    }
    let answer;
    try {
        answer = read(file, run, Number(code));
    } catch (e) {
        answer = { error: "open=" + e.code };
    }
    if (answer.error !== undefined) {
        process.stderr.write("vgshell-tui: package-outcome=unavailable reason=" + answer.error + "\n");
        process.exit(1);
    }
    if (answer.outcome !== null) process.stdout.write(JSON.stringify(answer.outcome) + "\n");
}

module.exports = { write };
