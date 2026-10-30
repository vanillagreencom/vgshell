// VGS's engine release uses Quickshell's supported DISTRIBUTOR metadata;
// --version prints it as `distributed by VGS N (package: vgshell-quickshell)`.
// Upstream keeps its own version. Every channel requires the VGS engine.
"use strict";
const RELEASE = 3;
const DEBIAN_VERSION = "0.3.2+git2b4501a+vgs3-1";
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

// Only the identities emitted by the VGS recipes enter this comparison.
// Epoch/upstream/revision ordering follows vercmp(8), rpm-version(7) and
// Debian Policy 5.6.12 within these forms; they admit no ~ or ^ operators.
// The separate VGS release condition survives an overriding distro epoch.
function packageCurrent(manager, version) {
    const forms = {
        pacman: /^(?:(?<epoch>[0-9]+):)?(?<upstream>[0-9]+\.[0-9]+\.[0-9]+\.r[0-9]+\.g[0-9a-f]+)-(?<revision>(?<release>[0-9]+)(?:\.[0-9]+)?)$/,
        dnf: /^(?:(?<epoch>[0-9]+):)?(?<upstream>[0-9]+\.[0-9]+\.[0-9]+)-(?<revision>(?<release>[0-9]+)\.[0-9a-f]+(?:\.(?:fc|el)[0-9]+)?)$/,
        apt: /^(?:(?<epoch>[0-9]+):)?(?<upstream>[0-9]+\.[0-9]+\.[0-9]+\+git[0-9a-f]+\+vgs(?<release>[0-9]+))-(?<revision>[0-9]+(?:\+b[0-9]+)?)$/,
    };
    const read = value => {
        const match = typeof value === "string" ? forms[manager]?.exec(value) : null;
        if (!match) throw new Error("engine=package-version manager=" + manager + " value=" + value);
        return { ...match.groups, epoch: BigInt(match.groups.epoch || "0"), release: BigInt(match.groups.release) };
    };
    const have = read(version), need = read(manager === "apt" ? DEBIAN_VERSION : PACKAGE_FLOORS[manager]);
    if (have.release < BigInt(RELEASE)) return false;
    const compare = (a, b) => a === b ? 0 : a < b ? -1 : 1;
    const component = (a, b) => {
        const pattern = manager === "apt" ? /[0-9]+|[^0-9]/g : /[0-9]+|[a-z]+/g;
        const left = a.match(pattern) || [], right = b.match(pattern) || [];
        const numeric = value => value !== undefined && /^[0-9]/.test(value);
        for (let i = 0, j = 0; i < left.length || j < right.length; ++i, ++j) {
            const x = left[i], y = right[j], xn = numeric(x), yn = numeric(y);
            let order;
            if (manager === "apt") {
                if ((xn || x === undefined) && (yn || y === undefined)) order = compare(BigInt(x || "0"), BigInt(y || "0"));
                else {
                    const weight = value => value === undefined || numeric(value) ? 0 : value.charCodeAt(0) + (/^[a-z]$/.test(value) ? 0 : 256);
                    order = compare(weight(x), weight(y));
                }
            } else if (x === undefined || y === undefined) {
                // libalpm sorts a trailing alpha suffix before the empty
                // suffix; RPM sorts every additional segment after it.
                order = x === undefined ? (manager === "pacman" && !yn ? 1 : -1) : (manager === "pacman" && !xn ? -1 : 1);
            } else order = xn && yn ? compare(BigInt(x), BigInt(y)) : xn !== yn ? (xn ? 1 : -1) : compare(x, y);
            if (order !== 0) return order;
        }
        return 0;
    };
    return (compare(have.epoch, need.epoch) || component(have.upstream, need.upstream) || component(have.revision, need.revision)) >= 0;
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

module.exports = { RELEASE, PACKAGE_FLOORS, DEBIAN_VERSION, RELEASE_KEY, debianAsset, rootFor, classify, current, packageCurrent };
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
