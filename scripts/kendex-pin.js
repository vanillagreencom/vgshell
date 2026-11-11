#!/usr/bin/env node
// The kendex release pin against the newest kendex release.
//
//   node scripts/kendex-pin.js [--table FILE]
//
// Reads the kendex release the `deb-file` and `rpm-file` rows of
// shell/Core/PackageManagers.js pin (`files.releases`), or the rows of the
// table copy FILE names, and the newest stable kendex release from GitHub's
// latest-release endpoint. It prints one line on stdout and exits:
//
//   kendex-pin: pin=<version> newest=<version> status=current   exit 0
//   kendex-pin: pin=<version> newest=<version> status=behind    exit 1
//   kendex-pin: pin=<version> newest=<version> status=ahead     exit 2
//
// A pin ahead of the newest stable release names no release the owner can
// move from, so it is a refusal. Every other refusal is one keyed line on
// stderr:
//
//   kendex-pin: refused: usage                                   exit 2
//   kendex-pin: refused: release=missing manager=<id>            exit 2
//   kendex-pin: refused: version=<value> manager=<id>            exit 2
//   kendex-pin: refused: url=<value> manager=<id>                exit 2
//   kendex-pin: refused: pins-disagree deb-file=<v> rpm-file=<v> exit 2
//   kendex-pin: refused: error=<name> message=<text>             exit 2
//   kendex-pin: unreadable: transport=<curl exit or error> url=<url>   exit 77
//   kendex-pin: unreadable: http=<code> url=<url>                exit 77
//   kendex-pin: unreadable: json url=<url>                       exit 77
//   kendex-pin: unreadable: tag=<value> url=<url>                exit 77
//
// Exit 77 means the newest release could not be read; it is never a pass.
// The table loader's own refusals (bin/lib/qml-library.js) exit 2. Any other
// error, such as a table copy that does not parse, is the `error=` refusal,
// so no failure reads as exit 1, behind.
//
// The reading only tells the pin's owner that a newer release exists. It
// writes nothing, and bin/lib/pkg-file.js keeps the pinned SHA-256 as the
// only thing it accepts. The owner and the pin-move rule are in
// docs/architecture/distribution.md § Channels; scripts/test-kendex-pin.js
// holds this contract.
//
// The status line, the refusal and unreadable lines, their exits and the
// version compare are the pin reading's contract. This file exports it as
// pinReading for scripts/engine-pin.js, which reads another pin by it.
"use strict";
const cp = require("node:child_process");
const path = require("node:path");
const { load } = require("../bin/lib/qml-library.js");

const MANAGERS = ["deb-file", "rpm-file"];
const DOWNLOADS = "https://github.com/vanillagreencom/kendex/releases/download/v";
// GitHub's "Get the latest release" endpoint answers the most recent release
// that is neither a pre-release nor a draft, and needs no authentication for
// a public repository:
// https://docs.github.com/en/rest/releases/releases#get-the-latest-release
const LATEST = "https://api.github.com/repos/vanillagreencom/kendex/releases/latest";
const VERSION = /^[0-9]+(\.[0-9]+)*$/;

// The pin reading NAME makes: refuse, unreadable and report each write one
// line and exit, run turns any error MAIN throws into a refusal, and compare
// orders two versions as report does.
function pinReading(name) {
    function refuse(key) {
        process.stderr.write(name + ": refused: " + key + "\n");
        process.exit(2);
    }
    function unreadable(key, url) {
        process.stderr.write(name + ": unreadable: " + key + " url=" + url + "\n");
        process.exit(77);
    }
    // PIN is the text the line shows, VERSION the dotted version it compares.
    function report(pin, version, newest) {
        const status = ["behind", "current", "ahead"][compare(version, newest) + 1];
        process.stdout.write(name + ": pin=" + pin + " newest=" + newest + " status=" + status + "\n");
        process.exit({ current: 0, behind: 1, ahead: 2 }[status]);
    }
    // node exits 1 on an uncaught error, the exit that reads as behind. An
    // error thrown inside a vm context is of that context's realm, so it is
    // read by its fields, not by instanceof.
    function run(main) {
        try {
            main();
        } catch (e) {
            const known = e !== null && typeof e === "object";
            refuse("error=" + (known && typeof e.name === "string" ? e.name : typeof e) + " message=" + JSON.stringify(known ? String(e.message) : String(e)));
        }
    }
    return { refuse, unreadable, report, run, compare };
}
const { refuse, unreadable, report, run } = pinReading("kendex-pin");

// The one kendex version both rows pin, each row's url naming that version's
// release download folder, so one pin move raises both rows. A pin move that
// edits one row alone, or a version and not its url, is what this refuses.
function pinned(table) {
    const versions = MANAGERS.map(id => {
        const row = table.managerRow(id);
        const files = row === null ? null : row.files;
        const releases = files !== null && typeof files === "object" && Array.isArray(files.releases) ? files.releases : [];
        const release = releases.find(r => r !== null && typeof r === "object" && r.name === "kendex");
        if (release === undefined) refuse("release=missing manager=" + id);
        if (typeof release.version !== "string" || !VERSION.test(release.version)) refuse("version=" + JSON.stringify(release.version) + " manager=" + id);
        if (release.url !== DOWNLOADS + release.version + "/") refuse("url=" + JSON.stringify(release.url) + " manager=" + id);
        return release.version;
    });
    if (versions[0] !== versions[1]) refuse("pins-disagree " + MANAGERS.map((id, i) => id + "=" + versions[i]).join(" "));
    return versions[0];
}

function newest() {
    const curl = cp.spawnSync("curl", ["--silent", "--show-error", "--location", "--max-time", "20", "--max-filesize", "16777216",
        "--header", "Accept: application/vnd.github+json", "--write-out", "\n%{http_code}", "--", LATEST],
        { encoding: "utf8", timeout: 25000, maxBuffer: 32 * 1024 * 1024 });
    if (curl.error !== undefined || curl.status !== 0) unreadable("transport=" + (curl.error !== undefined ? curl.error.code : curl.status), LATEST);
    const cut = curl.stdout.lastIndexOf("\n");
    const code = curl.stdout.slice(cut + 1);
    if (code !== "200") unreadable("http=" + JSON.stringify(code), LATEST);
    let release;
    try { release = JSON.parse(curl.stdout.slice(0, cut)); } catch { unreadable("json", LATEST); }
    const tag = release !== null && typeof release === "object" ? release.tag_name : undefined;
    if (typeof tag !== "string" || !tag.startsWith("v") || !VERSION.test(tag.slice(1))) unreadable("tag=" + JSON.stringify(tag), LATEST);
    return tag.slice(1);
}

// Dotted versions compared number by number, a missing part counting as 0.
// bin/lib/pkg-file.js compares installed packages with each format's own
// tool, which a host reading a release tag need not have.
function compare(a, b) {
    const x = a.split(".").map(Number), y = b.split(".").map(Number);
    for (let i = 0; i < Math.max(x.length, y.length); i++) {
        const d = (x[i] || 0) - (y[i] || 0);
        if (d !== 0) return Math.sign(d);
    }
    return 0;
}

function main(args) {
    if (!(args.length === 0 || (args.length === 2 && args[0] === "--table" && args[1] !== ""))) refuse("usage");
    const file = args.length === 2 ? path.resolve(args[1]) : path.join(__dirname, "..", "shell", "Core", "PackageManagers.js");
    const pin = pinned(load(file));
    report(pin, pin, newest());
}

module.exports = { pinReading };
if (require.main === module) run(() => main(process.argv.slice(2)));
