// VGS's engine release uses Quickshell's supported DISTRIBUTOR metadata;
// --version prints it as `distributed by VGS N (package: vgshell-quickshell)`.
// Upstream keeps its own version. Every channel requires the VGS engine.
"use strict";
const RELEASE = 2;
const DEBIAN_VERSION = "0.3.2+git2b4501a+vgs2-1";
const RELEASE_KEY = "8BC162233D519169B9574148CC6862AD90B7D7EA";
const PACKAGE_FLOORS = Object.freeze({
    pacman: `0.3.2.r7.g2b4501a-${RELEASE}`,
    dnf: `0.3.2-${RELEASE}.2b4501a`
});

function classify(text) {
    if (!/distributed by VGS(?: |\))/.test(text)) return { kind: "stock" };
    const match = /distributed by VGS ([0-9]+) \(package: vgshell-quickshell\)\)/.exec(text);
    return { kind: "vgs", release: match === null ? null : Number(match[1]) };
}

function current(text) {
    const read = classify(text);
    return read.kind === "vgs" && read.release !== null && read.release >= RELEASE;
}

function debianAsset(architecture) {
    if (architecture !== "amd64") throw new Error("engine=architecture unsupported=" + architecture);
    return `vgshell-quickshell_${DEBIAN_VERSION}_debian-forky_${architecture}.deb`;
}

// Release repairs share the authenticated release identity. Checkout roots
// bind the original checkout path and its exact commit, never the scratch path.
function rootFor(dataHome, tree, revision = "-", version = null) {
    const fs = require("node:fs"), path = require("node:path"), crypto = require("node:crypto");
    // install.sh creates the parent before naming its not-yet-published git tree.
    const real = fs.existsSync(tree) ? fs.realpathSync(tree) : path.join(fs.realpathSync(path.dirname(tree)), path.basename(tree));
    if (real.startsWith("/nix/store/")) return null;
    let identity;
    if (revision !== "-") {
        if (!/^[0-9a-f]{40}$/.test(revision)) throw new Error("engine=revision invalid=" + revision);
        identity = "git-" + crypto.createHash("sha256").update(real).digest("hex") + "-" + revision;
    } else {
        version = version || fs.readFileSync(path.join(tree, "VERSION"), "utf8").trim();
        if (!/^[0-9]+\.[0-9]+\.[0-9]+$/.test(version)) throw new Error("engine=version invalid=" + version);
        identity = "release-" + version;
    }
    return path.join(dataHome, "vgshell", ".engines", identity);
}

module.exports = { RELEASE, PACKAGE_FLOORS, DEBIAN_VERSION, RELEASE_KEY, debianAsset, rootFor, classify, current };
if (require.main === module) {
    if (process.argv[2] === "path") {
        const root = rootFor(process.argv[3], process.argv[4], process.argv[5]);
        if (root !== null && require("node:fs").existsSync(root + "/bin/qs")) console.log(root + "/bin");
    } else {
        const text = require("node:fs").readFileSync(0, "utf8");
        const read = classify(text);
        if (read.kind === "stock") {
            console.log(`stock ${RELEASE}`);
            process.exitCode = 1;
        } else {
            console.log(`${read.release === null ? "unknown" : read.release} ${RELEASE}`);
            process.exitCode = current(text) ? 0 : 1;
        }
    }
}
