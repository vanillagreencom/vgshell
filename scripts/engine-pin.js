#!/usr/bin/env node
// The Quickshell engine pin against the newest upstream Quickshell release.
//
//   node scripts/engine-pin.js [--recipe FILE]
//
// Reads the engine pin from the `pkgver` of
// packaging/arch/vgshell-quickshell/PKGBUILD, or of the recipe copy FILE
// names, and the newest upstream release from the tags of the git repository
// at that recipe's `url` with `.git` appended, the source the recipe builds
// from. It prints one line on stdout and exits:
//
//   engine-pin: pin=<pkgver> newest=<version> status=current   exit 0
//   engine-pin: pin=<pkgver> newest=<version> status=behind    exit 1
//   engine-pin: pin=<pkgver> newest=<version> status=ahead     exit 2
//
// A pkgver is the release it builds on, optionally followed by
// `.r<count>.g<commit>`, a commit that many commits past that release, as
// the recipe's `provides` cuts it at `.r`. The release alone is compared, so
// a pin at a commit past the newest release reads current. A release is a
// tag `v<version>`, a version being dotted numbers; any other tag, such as a
// release candidate, is no release. A pin ahead of the newest release names
// no release the owner can move from, so it is a refusal. Every other
// refusal is one keyed line on stderr:
//
//   engine-pin: refused: usage                                   exit 2
//   engine-pin: refused: pkgver-lines=<count other than 1>       exit 2
//   engine-pin: refused: pkgver=<value>                          exit 2
//   engine-pin: refused: url-lines=<count other than 1>          exit 2
//   engine-pin: refused: url=<value>                             exit 2
//   engine-pin: refused: error=<name> message=<text>             exit 2
//   engine-pin: unreadable: transport=<git exit or error> url=<url>   exit 77
//   engine-pin: unreadable: line=<text> url=<url>                exit 77
//   engine-pin: unreadable: releases=none url=<url>              exit 77
//
// Exit 77 means the newest release could not be read; it is never a pass.
// Any other error is the `error=` refusal, so no failure reads as exit 1,
// behind. scripts/kendex-pin.js owns this line, refusal and exit contract
// and the version compare.
//
// The same engine commit is pinned in the other recipes, flake.nix,
// bin/lib/engine.js and scripts/check-packaging.js; that check, not this
// reading, judges their agreement. The reading writes nothing. The pin-move
// rule is in docs/architecture/distribution.md § Quickshell engine, and
// scripts/test-engine-pin.js holds this contract.
"use strict";
const cp = require("node:child_process");
const fs = require("node:fs");
const path = require("node:path");
const { pinReading } = require("./kendex-pin.js");

const { refuse, unreadable, report, run, compare } = pinReading("engine-pin");
const PKGVER = /^([0-9]+(?:\.[0-9]+)*)(?:\.r[0-9]+\.g[0-9a-f]+)?$/;
const HTTPS = /^https:\/\/[^\s'"]+$/;
const TAG = /^[0-9a-f]{40}(?:[0-9a-f]{24})?\trefs\/tags\/(.+)$/;
const RELEASE = /^v([0-9]+(?:\.[0-9]+)*)$/;

// The one value of the recipe's `KEY=` line, quoted or not.
function field(recipe, key) {
    const lines = recipe.split("\n").filter(line => line.startsWith(key + "="));
    if (lines.length !== 1) refuse(key + "-lines=" + lines.length);
    return lines[0].slice(key.length + 1).replace(/^'(.*)'$/, "$1");
}

function newest(url) {
    // --refs leaves out the peeled `^{}` entries of annotated tags. git keeps
    // the caller's environment, its proxy and certificate settings included;
    // with no terminal prompt, a repository asking for credentials fails
    // instead of waiting.
    const git = cp.spawnSync("git", ["ls-remote", "--tags", "--refs", "--", url], {
        encoding: "utf8", timeout: 30000, maxBuffer: 16 * 1024 * 1024,
        env: { ...process.env, GIT_TERMINAL_PROMPT: "0" },
    });
    if (git.error !== undefined || git.status !== 0) unreadable("transport=" + (git.error !== undefined ? git.error.code : git.status), url);
    const releases = [];
    for (const line of git.stdout.split("\n")) {
        if (line === "") continue;
        const tag = TAG.exec(line);
        if (tag === null) unreadable("line=" + JSON.stringify(line), url);
        const release = RELEASE.exec(tag[1]);
        if (release !== null) releases.push(release[1]);
    }
    if (releases.length === 0) unreadable("releases=none", url);
    // The newest by number, as report compares the pin with it.
    return releases.reduce((a, b) => (compare(a, b) >= 0 ? a : b));
}

function main(args) {
    if (!(args.length === 0 || (args.length === 2 && args[0] === "--recipe" && args[1] !== ""))) refuse("usage");
    const file = args.length === 2 ? path.resolve(args[1]) : path.join(__dirname, "..", "packaging", "arch", "vgshell-quickshell", "PKGBUILD");
    const recipe = fs.readFileSync(file, "utf8");
    const pkgver = field(recipe, "pkgver");
    const pin = PKGVER.exec(pkgver);
    if (pin === null) refuse("pkgver=" + JSON.stringify(pkgver));
    const url = field(recipe, "url");
    if (!HTTPS.test(url)) refuse("url=" + JSON.stringify(url));
    report(pkgver, pin[1], newest(url + ".git"));
}

run(() => main(process.argv.slice(2)));
