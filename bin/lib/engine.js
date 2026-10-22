// VGS's engine release uses Quickshell's supported DISTRIBUTOR metadata;
// --version prints it as `distributed by VGS N (package: vgshell-quickshell)`.
// Upstream keeps its own version. Stock channels retain the upstream floor.
"use strict";
const RELEASE = 2;
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

module.exports = { RELEASE, PACKAGE_FLOORS, classify, current };
if (require.main === module) {
    const text = require("node:fs").readFileSync(0, "utf8");
    const read = classify(text);
    if (read.kind === "stock") console.log("stock");
    else {
        console.log(`${read.release === null ? "unknown" : read.release} ${RELEASE}`);
        process.exitCode = current(text) ? 0 : 1;
    }
}
