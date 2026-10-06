#!/usr/bin/env node
// The wallpaper a catalog theme applies first, for scripts/theme-previews.sh:
// the theme's pinned archive fetched and checked by bin/lib/theme-download.js
// into CACHE, its backgrounds/ unpacked beside OUT, and the first image by
// the apply rule (bin/lib/theme-backgrounds.js `images`) kept as
// OUT/<name>-<first 12 hex of the pin's sha256>.<ext>, so a re-pinned theme
// is fetched again. Prints that path. A kept one with the same pin is
// printed without a fetch. VGS_THEME_ASSET_BASE replaces the pin's
// `<repo>/releases/download` and VGS_TEST_RUN allows a file:// base, as for
// `vgshell theme wallpapers`.
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
    const index = JSON.parse(fs.readFileSync(path.join(repo, "themes", "catalog", "index.json"), "utf8"));
    const entry = index.entries.find(e => e.name === name);
    if (entry === undefined || entry.imagery === null) {
        process.stderr.write("theme-preview-wallpaper: refused: theme=" + name + " reason=" + (entry === undefined ? "not-in-catalog" : "no-imagery") + "\n");
        return 1;
    }
    const pin = entry.imagery;
    const keptName = name + "-" + pin.sha256.slice(0, 12);
    const kept = fs.readdirSync(out, { withFileTypes: true });
    const existing = kept.find(file => file.isFile() && path.parse(file.name).name === keptName);
    if (existing !== undefined) {
        process.stdout.write(path.join(out, existing.name) + "\n");
        return 0;
    }
    const unpacked = path.join(out, "." + name + ".unpacked");
    fs.rmSync(unpacked, { recursive: true, force: true });
    fs.mkdirSync(path.join(unpacked, backgrounds.DIR), { recursive: true });
    const url = download.archiveUrl(pin, process.env.VGS_THEME_ASSET_BASE, Boolean(process.env.VGS_TEST_RUN));
    const fetched = await download.fetchArchive(pin, url, cache, () => {});
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
    const target = path.join(out, keptName + path.extname(first).toLowerCase());
    fs.renameSync(path.join(unpacked, backgrounds.DIR, first), target);
    fs.rmSync(unpacked, { recursive: true, force: true });
    process.stdout.write(target + "\n");
    return 0;
}

main(process.argv.slice(2)).then(code => { process.exitCode = code; }, e => {
    process.stderr.write("theme-preview-wallpaper: failed: " + (e instanceof download.AssetRefusal ? e.step + "=" + e.reason + " " + (e.detail ?? "") : String(e.stack ?? e)) + "\n");
    process.exitCode = 1;
});
