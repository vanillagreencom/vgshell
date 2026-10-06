#!/usr/bin/env node
// The wallpaper a catalog theme applies first, for scripts/theme-previews.sh:
// the theme's pinned archive fetched and checked by bin/lib/theme-download.js
// into CACHE, its backgrounds/ unpacked beside OUT, and the first image by
// the apply rule (bin/lib/theme-backgrounds.js `images`) kept as
// OUT/<name>.<ext>. Prints that path. An existing one is kept.
//
// Usage: scripts/theme-preview-wallpaper.js NAME OUT CACHE
"use strict";
const fs = require("fs");
const path = require("path");

const repo = path.resolve(__dirname, "..");
const download = require(path.join(repo, "bin", "lib", "theme-download.js"));
const backgrounds = require(path.join(repo, "bin", "lib", "theme-backgrounds.js"));

async function main([name, out, cache]) {
    if (name === undefined || out === undefined || cache === undefined || !/^[a-z0-9][a-z0-9-]*$/.test(name)) {
        process.stderr.write("theme-preview-wallpaper: refused: arguments=" + JSON.stringify([name, out, cache]) + "\n");
        return 2;
    }
    const kept = fs.readdirSync(out, { withFileTypes: true, throwIfNoEntry: false }) ?? [];
    const existing = kept.find(entry => entry.isFile() && path.parse(entry.name).name === name);
    if (existing !== undefined) {
        process.stdout.write(path.join(out, existing.name) + "\n");
        return 0;
    }
    const index = JSON.parse(fs.readFileSync(path.join(repo, "themes", "catalog", "index.json"), "utf8"));
    const entry = index.entries.find(e => e.name === name);
    if (entry === undefined || entry.imagery === null) {
        process.stderr.write("theme-preview-wallpaper: refused: theme=" + name + " reason=" + (entry === undefined ? "not-in-catalog" : "no-imagery") + "\n");
        return 1;
    }
    const pin = entry.imagery;
    const unpacked = path.join(out, "." + name + ".unpacked");
    fs.rmSync(unpacked, { recursive: true, force: true });
    fs.mkdirSync(path.join(unpacked, backgrounds.DIR), { recursive: true });
    const fetched = await download.fetchArchive(pin, download.archiveUrl(pin), cache, () => {});
    try {
        await download.readArchive(fetched, member => {
            if (member.kind !== "file" || !member.name.startsWith(backgrounds.DIR + "/")) return null;
            const file = member.name.slice(backgrounds.DIR.length + 1);
            if (file.includes("/") || !backgrounds.isImageName(file)) return null;
            const fd = fs.openSync(path.join(unpacked, backgrounds.DIR, file), "wx");
            return { write(chunk) { download.writeAll(fd, chunk); }, close() { fs.closeSync(fd); } };
        }, () => {});
    } finally {
        fs.rmSync(fetched, { force: true });
    }
    const first = backgrounds.images(unpacked, "theme-preview-wallpaper: theme=" + name)[0];
    if (first === undefined) {
        fs.rmSync(unpacked, { recursive: true, force: true });
        process.stderr.write("theme-preview-wallpaper: refused: theme=" + name + " reason=no-image\n");
        return 1;
    }
    const target = path.join(out, name + path.extname(first).toLowerCase());
    fs.renameSync(path.join(unpacked, backgrounds.DIR, first), target);
    fs.rmSync(unpacked, { recursive: true, force: true });
    process.stdout.write(target + "\n");
    return 0;
}

main(process.argv.slice(2)).then(code => { process.exitCode = code; }, e => {
    process.stderr.write("theme-preview-wallpaper: failed: " + (e instanceof download.AssetRefusal ? e.step + "=" + e.reason + " " + (e.detail ?? "") : String(e.stack ?? e)) + "\n");
    process.exitCode = 1;
});
