#!/usr/bin/env node
// Every wallpaper a catalog theme installs has a name, and no name stands on
// a file its archive lacks: the `backgrounds` map of each
// THEMES/catalog/<name>/theme.json against the images of the archive its
// index entry pins. Install judges only the names' shape for a catalog
// package (ThemeLogic.accept), never the archive's files, so this is the
// one check of the pair. Names inside one theme must differ, compared
// without case.
//
// An archive's image list is read once per pin: fetched and verified by
// bin/lib/theme-download.js into a scratch folder under LISTINGS, read by
// the install's member rule, and kept as LISTINGS/<sha256>/listing.json; the
// archive is removed at once. --prepare owns that input step before any
// offline row starts. The ordinary check reads only the prepared listings.
// LISTINGS defaults to the caller's XDG cache under
// vgshell/validate/theme-listings/<sha256>/listing.json.
// VGS_THEME_ASSET_BASE replaces the pin's `<repo>/releases/download`, and
// VGS_TEST_RUN allows a file:// base, as for `vgshell theme wallpapers`.
//
// One line per entry: `ok theme=<name> images=<n>`, or a
// `refused: theme=<name> reason=<key> ...` line per defect, `missing`
// (an image with no name), `unknown` (a name on a file the archive lacks),
// `duplicate`, `member` (a member install refuses), `sha256` or `size`
// (the archive is not its pin). Preparation prints `prepared` per entry;
// an unreadable listing or unavailable archive prints `input-step: failed`.
// Exit 0 when every entry passes, 1 when any is refused, 2 when the index
// or a package cannot be read, or the input step cannot fetch an archive.
//
// Usage: scripts/check-catalog-wallpaper-names.js [--prepare] [THEMES] [LISTINGS]
"use strict";
const fs = require("fs");
const os = require("os");
const path = require("path");

const repo = path.resolve(__dirname, "..");
const download = require(path.join(repo, "bin", "lib", "theme-download.js"));
const backgrounds = require(path.join(repo, "bin", "lib", "theme-backgrounds.js"));

class Unreadable extends Error {}

function readJson(file) {
    try {
        return JSON.parse(fs.readFileSync(file, "utf8"));
    } catch (e) {
        throw new Unreadable("check-catalog-wallpaper-names: unreadable path=" + file + " error=" + (e.code ?? "json"));
    }
}

function defaultListings() {
    return path.resolve(process.env.XDG_CACHE_HOME || path.join(process.env.HOME || os.homedir(), ".cache"),
        "vgshell", "validate", "theme-listings");
}

// The sorted image names of PIN's archive, or the refusal reasons of its
// members: { files } or { refused: [[reason, detail]] }.
async function listing(pin, listings, prepare) {
    const kept = path.join(listings, pin.sha256, "listing.json");
    if (fs.existsSync(kept)) {
        let cached;
        try { cached = readJson(kept); }
        catch (error) { throw new Unreadable("input-step: failed listing=unreadable path=" + kept + " error=" + error.message); }
        if (!cached || !Array.isArray(cached.files) || cached.files.some(file => typeof file !== "string"))
            throw new Unreadable("input-step: failed listing=invalid path=" + kept);
        return cached;
    }
    if (!prepare) throw new Unreadable("input-step: failed listing=missing sha256=" + pin.sha256 + " path=" + kept);
    fs.mkdirSync(listings, { recursive: true });
    const scratch = fs.mkdtempSync(path.join(listings, ".fetch-"));
    try {
        const url = download.archiveUrl(pin, process.env.VGS_THEME_ASSET_BASE, Boolean(process.env.VGS_TEST_RUN));
        const archive = await download.fetchArchive(pin, url, scratch, () => {});
        const files = [];
        const refused = [];
        await download.readArchive(archive, member => {
            const file = member.name.slice(backgrounds.DIR.length + 1);
            if (member.kind !== "file" || !member.name.startsWith(backgrounds.DIR + "/") || !backgrounds.isImageName(file))
                refused.push(["member", "member=" + JSON.stringify(member.name) + " kind=" + member.kind]);
            else
                files.push(file);
            return null;
        }, () => {});
        if (refused.length > 0) return { refused };
        const answer = { files: files.sort() };
        const part = path.join(scratch, "listing.json");
        fs.writeFileSync(part, JSON.stringify(answer) + "\n");
        fs.mkdirSync(path.dirname(kept), { recursive: true });
        fs.renameSync(part, kept);
        return answer;
    } finally {
        fs.rmSync(scratch, { recursive: true, force: true });
    }
}

// The defects of NAMES, a package's `backgrounds` map, against FILES.
function defects(names, files) {
    const out = [];
    const held = new Set(files);
    for (const file of files)
        if (!Object.hasOwn(names, file)) out.push(["missing", "file=" + JSON.stringify(file)]);
    for (const file of Object.keys(names))
        if (!held.has(file)) out.push(["unknown", "file=" + JSON.stringify(file)]);
    const seen = new Map();
    for (const [file, name] of Object.entries(names)) {
        const key = String(name).toLowerCase();
        if (seen.has(key)) out.push(["duplicate", "name=" + JSON.stringify(name) + " files=" + JSON.stringify([seen.get(key), file])]);
        else seen.set(key, file);
    }
    return out;
}

// Whether REFUSAL says the archive could not be fetched, rather than that
// the archive or its pin is wrong.
function unavailable(refusal) {
    return refusal.step === "fetch" && !["sha256", "size", "pin"].includes(refusal.reason);
}

async function main(args) {
    const prepare = args[0] === "--prepare";
    const [themes = path.join(repo, "themes"), listings] = prepare ? args.slice(1) : args;
    const index = readJson(path.join(themes, "catalog", "index.json"));
    const kept = listings ?? defaultListings();
    let refused = false;
    let missed = false;
    for (const entry of index.entries) {
        const names = readJson(path.join(themes, "catalog", entry.name, "theme.json")).backgrounds ?? {};
        let found;
        try {
            found = await listing(entry.imagery, kept, prepare);
        } catch (e) {
            if (!(e instanceof download.AssetRefusal)) throw e;
            if (unavailable(e)) {
                process.stderr.write("input-step: failed theme=" + entry.name + " reason=" + e.reason + " " + e.detail + "\n");
                missed = true;
            } else {
                process.stdout.write("refused: theme=" + entry.name + " reason=" + e.reason + " " + e.detail + "\n");
                refused = true;
            }
            continue;
        }
        const problems = found.refused ?? (prepare ? [] : defects(names, found.files));
        for (const [reason, detail] of problems)
            process.stdout.write("refused: theme=" + entry.name + " reason=" + reason + " " + detail + "\n");
        if (problems.length === 0)
            process.stdout.write((prepare ? "prepared" : "ok") + " theme=" + entry.name + " images=" + found.files.length + "\n");
        else
            refused = true;
    }
    return refused ? 1 : missed ? 2 : 0;
}

main(process.argv.slice(2)).then(code => { process.exitCode = code; }, e => {
    process.stderr.write((e instanceof Unreadable ? e.message : "check-catalog-wallpaper-names: failed: " + String(e.stack ?? e)) + "\n");
    process.exitCode = 2;
});
