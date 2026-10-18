// vgshell self: how this VGS tree was installed, what its channel offers now,
// and the update of a curl install (D040). bin/vgshell runs it under node and
// owns the git calls: it hands in whether the tree is its own checkout and,
// for a checkout or a vgshell-git package, the commits git read.
//
//   self.js detect <root> <data-home> <version> <checkout>
//       the install method: one line `<method> <package> <current>
//       <manager>`, `-` for an empty field. <checkout> is true when the
//       tree is the top level of its own git checkout.
//   self.js latest <repository>
//       the newest release's version, X.Y.Z, from the GitHub API
//   self.js changed <repository> <current> <latest>
//       `true` when main's commit <latest> changes an installed path since
//       the commit the vgshell-git version <current> was built from, else
//       `false`, from the GitHub API's compare of the two
//   self.js helper
//       the binary of the AUR helper `vgshell pkg detect` finds, its `aur`
//       overlay, or `-` with none
//   self.js report text|json <version> <method> <package> <current> <manager> <latest> <behind> <helper> <error>
//       judge `behind`, the step an update takes and the reason none runs,
//       and print the status; <manager> is the package manager detect
//       printed, <behind> a checkout's count of upstream commits it lacks
//       or vgshell-git's `changed` answer; `-` is an absent value
//   self.js install <repository> <data-home> <root> <current> <shell-tree>
//       replace a curl install by the newest release when it is newer;
//       <shell-tree> is the tree the running shell was started from, `-`
//       with no shell running
//
// The methods, judged in this order on the real path of the tree:
//   checkout  the tree is the top level of its own git checkout
//   nix       the tree lies in the Nix store: $NIX_STORE_DIR, else /nix/store
//   curl      <data-home>/vgshell/current resolves to the tree, a directory of
//             <data-home>/vgshell
//   package   the system's primary package manager owns the tree's VERSION
//             (`vgshell pkg owner`), as the package vgshell or vgshell-git
// Any other tree is refused as `method=unknown path=<root>`.
//
// The release and compare API is https://api.github.com. VGS_RELEASE_API
// replaces it only in a test run, VGS_TEST_RUN non-empty, and only with a
// loopback base, http://127.0.0.1:<port>; anything else set there is
// refused. A download is https, or on the loopback base's origin.
//
// Every refusal is one line on stderr, `vgshell: refused: <key>=<value>`,
// through bin/lib/judge-files.js, exit 1; a bad invocation exits 2.
// docs/architecture/distribution.md § Installation ownership.
"use strict";
const childProcess = require("child_process");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { Readable } = require("stream");
const { pipeline } = require("stream/promises");

const { Refusal, refuse, main, writing } = require(path.join(__dirname, "judge-files.js"));
const packageTable = require(path.join(__dirname, "qml-library.js")).load(path.join(__dirname, "..", "..", "shell", "Core", "PackageManagers.js"));

const VERSION_PATTERN = /^[0-9]+\.[0-9]+\.[0-9]+$/;
// Also read by bin/vgshell's Reset through directory-pattern.
const CURL_DIRECTORY_PATTERN = /^[0-9]+\.[0-9]+\.[0-9]+(-repair-[A-Za-z0-9]+)?$/;
// A vgshell-git package's version ends in the commit it was built from: the
// AUR form X.Y.Z.r<N>.g<hash> and the COPR form X.Y.Z^<N>.git<hash>.
const GIT_PACKAGE_PATTERN = /^[0-9]+\.[0-9]+\.[0-9]+(?:\.r|\^)[0-9]+\.g(?:it)?([0-9a-f]{7,40})$/;
const PACKAGES = ["vgshell", "vgshell-git"];
const API = "https://api.github.com";
// The seconds the release query may take, and the seconds and bytes one
// download may take. The release archive was 5.5 MB at 0.1.0.
const API_TIMEOUT = 10;
const DOWNLOAD_TIMEOUT = 120;
const MAX_ARCHIVE = 128 * 1024 * 1024;
const MAX_SUMS = 64 * 1024;
// GitHub's compare lists at most 300 changed files, and fewer commits than
// the comparison holds when it cuts the list short; either way the files
// it names may not be all that changed.
// https://docs.github.com/en/rest/commits/commits#compare-two-commits
const COMPARE_FILES = 300;
const COMMIT_PATTERN = /^(?:[0-9a-f]{40}|[0-9a-f]{64})$/;
// What the vgshell-git recipe installs or builds from. Its package() runs
// packaging/install-system.sh with SYSCONFDIR, which copies bin, shell,
// config, themes, packaging/jarvis-home and VERSION into the tree, README.md
// and LICENSE beside it, and the Hyprland portal preference; the installer
// and the recipe decide what lands. A directory ends in `/`. Markdown under
// shell/ that the installer drops still counts: matching the installer's
// skip rule here would be a second copy of it, and a needless update costs
// less than a missed one. scripts/test-vgshell-self.sh holds the list to
// the installer.
const INSTALLED_PATHS = ["bin/", "shell/", "config/", "themes/", "packaging/jarvis-home/", "VERSION", "README.md", "LICENSE",
    "packaging/xdg-desktop-portal/hyprland-portals.conf", "packaging/install-system.sh", "packaging/arch/vgshell-git/"];

function usage(first) {
    process.stderr.write("vgshell: refused: " + first + "\nusage: self.js detect|latest|changed|helper|report|install ...\n");
    process.exit(2);
}

// The real path of FILE, or null when it does not resolve.
function real(file) {
    try {
        return fs.realpathSync(file);
    } catch (e) {
        if (e.code === "ENOENT" || e.code === "ENOTDIR" || e.code === "ELOOP") return null;
        refuse("path=unreadable path=" + file + " error=" + e.code);
    }
}

function inside(file, dir) {
    return dir !== null && file.startsWith(dir.endsWith("/") ? dir : dir + "/");
}

// The package that owns ROOT's VERSION, through `vgshell pkg owner`, the
// package layer's one owner query: `{ manager, package, version }`.
function owner(root) {
    const run = childProcess.spawnSync(process.execPath, [path.join(__dirname, "..", "vgshell-pkg"), "owner", path.join(root, "VERSION")], { encoding: "utf8" });
    if (run.error !== undefined) refuse("pkg=failed error=" + run.error.code);
    if (run.status !== 0) refuse("method=unknown path=" + root, undefined, 1, run.stderr);
    try {
        return JSON.parse(run.stdout);
    } catch (e) {
        refuse("pkg=unreadable output=" + JSON.stringify(run.stdout));
    }
}

// The binary of the `aur` overlay `vgshell pkg detect` finds, the helper the
// update pipeline upgrades the AUR's packages and rebuilds vgshell-git
// with, or null.
function aurHelper() {
    const run = childProcess.spawnSync(process.execPath, [path.join(__dirname, "..", "vgshell-pkg"), "detect", "--json"], { encoding: "utf8" });
    if (run.error !== undefined) refuse("pkg=failed error=" + run.error.code);
    if (run.status !== 0) refuse("pkg=detect exit=" + run.status, undefined, 1, run.stderr);
    let found;
    try {
        found = JSON.parse(run.stdout);
    } catch (e) {
        found = null;
    }
    if (found === null || !Array.isArray(found.overlays)) refuse("pkg=unreadable output=" + JSON.stringify(run.stdout));
    const aur = found.overlays.find(row => row !== null && row.id === "aur");
    return aur === undefined ? null : aur.binary;
}

// The method line for ROOT, as the header states.
function detect(root, dataHome, version, checkout) {
    if (checkout) return ["checkout", "-", "-", "-"];
    const tree = real(root);
    if (tree === null) refuse("path=unreadable path=" + root);
    if (inside(tree, real(process.env.NIX_STORE_DIR || "/nix/store"))) return ["nix", "-", version, "-"];
    const vgsData = real(path.join(dataHome, "vgshell"));
    if (vgsData !== null && real(path.join(vgsData, "current")) === tree && path.dirname(tree) === vgsData) return ["curl", "-", version, "-"];
    const found = owner(tree);
    if (!PACKAGES.includes(found.package)) refuse("package=" + found.package + " manager=" + found.manager + " reason=not-vgs");
    if (found.version === null) refuse("package=" + found.package + " manager=" + found.manager + " reason=version-unknown");
    const pattern = found.package === "vgshell" ? VERSION_PATTERN : GIT_PACKAGE_PATTERN;
    if (!pattern.test(found.version)) refuse("package=" + found.package + " version=" + found.version + " reason=not-a-version");
    return ["package", found.package, found.version, found.manager];
}

// Whether version A is newer than version B, both X.Y.Z.
function newer(a, b) {
    const x = a.split(".").map(Number);
    const y = b.split(".").map(Number);
    for (let i = 0; i < 3; i++) if (x[i] !== y[i]) return x[i] > y[i];
    return false;
}

// The API base and, for a loopback override, the one origin a download
// may use besides https.
function apiBase() {
    const value = process.env.VGS_RELEASE_API;
    if (value === undefined || value === "") return { base: API, origin: null };
    let url;
    try {
        url = new URL(value);
    } catch (e) {
        url = null;
    }
    if (!process.env.VGS_TEST_RUN || url === null || url.protocol !== "http:" || url.hostname !== "127.0.0.1")
        refuse("release-api=refused value=" + JSON.stringify(value), undefined, 1, "VGS_RELEASE_API is a loopback base for a test run alone");
    return { base: value.replace(/\/+$/, ""), origin: url.origin };
}

// Refuse the network error E from reading URL as KEY=timeout or
// KEY=unreachable.
function unread(e, url, seconds, key) {
    if (e.name === "TimeoutError") refuse(key + "=timeout seconds=" + seconds + " url=" + url);
    refuse(key + "=unreachable url=" + url, undefined, 1, String(e.cause || e.message));
}

// GET URL within SECONDS, the body read included: the signal stays on the
// response. KEY leads each refusal: KEY=timeout, KEY=unreachable and KEY=http
// for a status other than 200.
async function get(url, seconds, key, api) {
    const parsed = new URL(url);
    if (parsed.protocol !== "https:" && parsed.origin !== api.origin) refuse(key + "=insecure url=" + url);
    let response;
    try {
        response = await fetch(url, { headers: { "Accept": "application/vnd.github+json", "User-Agent": "vgshell" }, redirect: "follow", signal: AbortSignal.timeout(seconds * 1000) });
    } catch (e) {
        unread(e, url, seconds, key);
    }
    const landed = new URL(response.url || url);
    if (landed.protocol !== "https:" && landed.origin !== api.origin) refuse(key + "=insecure url=" + landed.href);
    return response;
}

// The JSON document RESPONSE from get(URL, SECONDS, KEY) carries. A body
// read the network ends is refused as get() refuses it; KEY=malformed is a
// body that is not JSON alone.
async function readJson(response, url, seconds, key) {
    let text;
    try {
        text = await response.text();
    } catch (e) {
        unread(e, url, seconds, key);
    }
    try {
        return JSON.parse(text);
    } catch (e) {
        refuse(key + "=malformed url=" + url);
    }
}

// The newest release of REPOSITORY: `{ version, assets }`, assets mapping
// each asset's name to its download URL.
async function latestRelease(repository, api, requestedVersion = null) {
    const url = api.base + "/repos/" + repository + "/releases/" + (requestedVersion === null ? "latest" : "tags/v" + requestedVersion);
    const response = await get(url, API_TIMEOUT, "release", api);
    if (response.status === 404) refuse("release=none repository=" + repository);
    if (response.status !== 200) refuse("release=http status=" + response.status + " url=" + url);
    const doc = await readJson(response, url, API_TIMEOUT, "release");
    if (doc === null || typeof doc.tag_name !== "string" || !Array.isArray(doc.assets)) refuse("release=malformed url=" + url);
    const version = doc.tag_name.replace(/^v/, "");
    if (!doc.tag_name.startsWith("v") || !VERSION_PATTERN.test(version)) refuse("tag=" + doc.tag_name + " reason=not-a-version");
    const assets = new Map();
    for (const asset of doc.assets)
        if (asset !== null && typeof asset.name === "string" && typeof asset.browser_download_url === "string") assets.set(asset.name, asset.browser_download_url);
    return { version, assets };
}

function installedPath(file) {
    return INSTALLED_PATHS.some(entry => (entry.endsWith("/") ? file.startsWith(entry) : file === entry));
}

// Whether main's commit LATEST changes an installed path since the commit
// the vgshell-git version CURRENT names, by REPOSITORY's compare of the two.
// A file counts by its path or, renamed, its old one. A list GitHub may
// have cut short, or a main that no longer holds the installed commit,
// counts as a change, since no file list proves the tree the same.
async function changed(repository, current, latest) {
    const built = GIT_PACKAGE_PATTERN.exec(current);
    if (built === null) refuse("version=" + current + " reason=not-a-git-package");
    if (!COMMIT_PATTERN.test(latest)) refuse("commit=" + latest + " reason=not-a-commit");
    if (latest.startsWith(built[1])) return false;
    const api = apiBase();
    const url = api.base + "/repos/" + repository + "/compare/" + built[1] + "..." + latest;
    const response = await get(url, API_TIMEOUT, "compare", api);
    if (response.status !== 200) refuse("compare=http status=" + response.status + " url=" + url);
    const doc = await readJson(response, url, API_TIMEOUT, "compare");
    const named = file => file !== null && typeof file === "object" && typeof file.filename === "string"
        && (file.previous_filename === undefined || typeof file.previous_filename === "string");
    if (doc === null || typeof doc !== "object" || typeof doc.status !== "string" || !Array.isArray(doc.files) || !doc.files.every(named)
        || !Array.isArray(doc.commits) || !Number.isInteger(doc.total_commits))
        refuse("compare=malformed url=" + url);
    if (doc.status === "diverged" || doc.files.length >= COMPARE_FILES || doc.commits.length < doc.total_commits) return true;
    return doc.files.some(file => installedPath(file.filename) || (file.previous_filename !== undefined && installedPath(file.previous_filename)));
}

// Stream NAME's download from RELEASE into FILE, refusing past MAX bytes.
// Answers the file's sha256 in hex.
async function download(release, name, file, max, api) {
    const url = release.assets.get(name);
    if (url === undefined) refuse("asset=missing name=" + name + " release=v" + release.version);
    const response = await get(url, DOWNLOAD_TIMEOUT, "download", api);
    if (response.status !== 200 || response.body === null) refuse("download=http status=" + response.status + " url=" + url);
    const hash = crypto.createHash("sha256");
    let bytes = 0;
    try {
        await pipeline(Readable.fromWeb(response.body), async function* (chunks) {
            for await (const chunk of chunks) {
                bytes += chunk.length;
                if (bytes > max) refuse("download=too-large name=" + name + " limit=" + max);
                hash.update(chunk);
                yield chunk;
            }
        }, fs.createWriteStream(file, { flags: "wx" }));
    } catch (e) {
        if (e.name === "TimeoutError") refuse("download=timeout seconds=" + DOWNLOAD_TIMEOUT + " url=" + url);
        if (e instanceof Refusal) throw e;
        refuse("download=failed url=" + url, undefined, 1, String(e.message));
    }
    return hash.digest("hex");
}

// The sha256 SHA256SUMS lists for NAME: exactly one `<hex>  <name>` or
// `<hex> *<name>` line.
function listedSum(text, name) {
    const sums = [];
    for (const line of text.split("\n")) {
        const m = /^([0-9a-f]{64}) [ *](.+)$/.exec(line);
        if (m !== null && m[2] === name) sums.push(m[1]);
    }
    if (sums.length !== 1) refuse("checksum=unlisted name=" + name + " count=" + sums.length);
    return sums[0];
}

function run(argv, options, key) {
    const r = childProcess.spawnSync(argv[0], argv.slice(1), Object.assign({ encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }, options));
    if (r.error !== undefined) refuse(key + " error=" + r.error.code);
    if (r.status !== 0) refuse(key + " exit=" + (r.status === null ? r.signal : r.status), undefined, 1, (r.stdout || "") + (r.stderr || ""));
}

// The engine's package identity, not its version provision, proves the VGS
// patches are installed. The package layer owns detection and ownership.
function engineFacts() {
    const r = childProcess.spawnSync(process.execPath, [path.join(__dirname, "..", "vgshell-pkg"), "detect", "--json", "--holders", "qs"], { encoding: "utf8" });
    if (r.error !== undefined || r.status !== 0) refuse("engine=detect-failed", undefined, 1, r.stderr);
    let found;
    try { found = JSON.parse(r.stdout); } catch (e) { refuse("engine=detect-unreadable"); }
    if (found === null || !Array.isArray(found.overlays) || !found.holders || !found.holders.qs) refuse("engine=detect-unreadable");
    return found;
}

function engineInstalled(found) {
    return found.primary !== null && found.holders.qs.owners[found.primary.id] === "vgshell-quickshell";
}

// Run only inside the presenter. It owns the terminal, and the existing
// package and system runners own elevation and show their plans.
function engineRun(manager) {
    if (manager === "dnf")
        run([path.join(__dirname, "..", "vgshell-system"), "apply", "vgs-quickshell-repository"], { stdio: "inherit" }, "engine=repository-failed");
    run([process.execPath, path.join(__dirname, "..", "vgshell-pkg"), "run", "install", "--manager", manager, "vgshell-quickshell"], { stdio: "inherit" }, "engine=install-failed");
    if (!engineInstalled(engineFacts())) refuse("engine=not-installed package=vgshell-quickshell");
}

function migrateEngine() {
    const found = engineFacts();
    if (found.primary === null || !["pacman", "dnf"].includes(found.primary.id) || engineInstalled(found)) return;
    const manager = found.primary.id === "pacman" ? "aur" : "dnf";
    if (manager === "aur" && !found.overlays.some(row => row.id === "aur"))
        refuse("engine=helper-missing manager=aur", undefined, 1, "Open Settings, Updates after installing an AUR helper.");
    const tui = path.join(__dirname, "..", "vgshell-tui");
    const command = [process.execPath, __filename, "engine-run", manager];
    let tty;
    try { tty = fs.openSync("/dev/tty", "r+"); } catch (e) {
        if (!["ENXIO", "ENODEV", "ENOENT"].includes(e.code)) refuse("engine=terminal-failed error=" + e.code);
    }
    if (tty !== undefined) {
        try {
            // The previous updater captures its installer child's streams.
            // Reopen the controlling terminal for the conflict question.
            run([tui, "present", "--presentation", "plain", "--", ...command], { stdio: [tty, tty, tty] }, "engine=migration-failed");
        } finally { fs.closeSync(tty); }
    } else {
        const key = "core/curl-engine", id = "engine-" + process.pid;
        run([tui, "launch", "--title", "Update VGS engine", "--record", key, "--run", id, "--", ...command], {}, "engine=launch-failed");
        const ended = childProcess.spawnSync(tui, ["wait", "--record", key, "--run", id], { encoding: "utf8" });
        if (ended.error !== undefined || ended.status !== 0) refuse("engine=wait-failed", undefined, 1, ended.stderr);
        let record;
        try { record = JSON.parse(ended.stdout); } catch (e) { refuse("engine=result-unreadable"); }
        if (record === null || record.state !== "ended" || !Number.isInteger(record.code)) refuse("engine=result-unreadable");
        if (record.code !== 0) refuse("engine=migration-failed exit=" + record.code);
    }
    if (!engineInstalled(engineFacts())) refuse("engine=not-installed package=vgshell-quickshell");
}

// The previous curl updater already produces this layout. Recognizing its
// complete transaction reaches the migration on its first new release,
// without turning package recipe staging into a host package operation.
function migrateCurlStage(source, dest, prefix) {
    if (prefix !== "/vgshell") return;
    const data = real(path.join(process.env.XDG_DATA_HOME || path.join(process.env.HOME, ".local", "share"), "vgshell"));
    const stage = real(path.dirname(dest));
    if (data === null || stage === null || path.dirname(stage) !== data || !path.basename(stage).startsWith(".self-update-")) return;
    const current = real(path.join(data, "current"));
    if (current === null || path.dirname(current) !== data || !CURL_DIRECTORY_PATTERN.test(path.basename(current))) return;
    const version = fs.readFileSync(path.join(source, "VERSION"), "utf8").trim();
    if (!VERSION_PATTERN.test(version) || real(source) !== real(path.join(stage, "source", "vgshell-" + version))
        || real(dest) !== path.join(stage, "tree")) return;
    migrateEngine();
}

// Replace the curl install whose data directory is DATA and whose tree
// ROOT, the one this command runs from, holds version CURRENT by
// REPOSITORY's newest release, when it is newer. The release is staged
// under DATA, checked against its SHA256SUMS, installed by its own
// packaging/install-system.sh, moved to DATA/<version> and made current by
// renaming a new `current` link over the old one. ROOT and SHELL_TREE, the
// tree a running shell was started from, stay, since a shell whose restart
// was refused still runs from a tree `current` no longer names; every other
// version directory is removed. bin/vgshell holds DATA/.self.lock around the
// call.
async function install(repository, dataHome, root, current, shellTree, repair = false) {
    const data = path.join(dataHome, "vgshell");
    // An update can move current while the user answers Repair's question.
    if (repair && real(path.join(data, "current")) !== real(root)) refuse("repair=selection-changed");
    const api = apiBase();
    const release = await latestRelease(repository, api, repair ? current : null);
    if (repair && release.version !== current) refuse("repair=version expected=" + current + " found=" + release.version);
    if (!repair && !newer(release.version, current)) {
        migrateEngine();
        process.stdout.write("ok up-to-date=vgshell version=" + current + "\n");
        return;
    }
    // A same-version repair publishes a fresh tree through `current`, just
    // like an update. The running and previous trees never disappear.
    const target = repair ? fs.mkdtempSync(path.join(data, current + "-repair-")) : path.join(data, release.version);
    let taken = true;
    try {
        fs.lstatSync(target);
    } catch (e) {
        if (e.code !== "ENOENT") refuse("target=unreadable path=" + target + " error=" + e.code);
        taken = false;
    }
    if (taken && !repair) refuse("target=exists path=" + target, undefined, 1, "remove it and run vgshell self update again");
    let stage;
    writing(data, "data", () => {
        // Under the lock, a staging directory left behind is a dead run's.
        for (const entry of fs.readdirSync(data))
            if (entry.startsWith(".self-update-")) fs.rmSync(path.join(data, entry), { recursive: true, force: true });
        stage = fs.mkdtempSync(path.join(data, ".self-update-"));
    });
    try {
        const archive = "vgshell-" + release.version + ".tar.gz";
        const sums = path.join(stage, "SHA256SUMS");
        await download(release, "SHA256SUMS", sums, MAX_SUMS, api);
        const got = await download(release, archive, path.join(stage, archive), MAX_ARCHIVE, api);
        const want = listedSum(fs.readFileSync(sums, "utf8"), archive);
        if (got !== want) refuse("checksum=mismatch name=" + archive + " want=" + want + " got=" + got);
        const source = path.join(stage, "source");
        writing(source, "stage", () => fs.mkdirSync(source));
        run(["tar", "-xzf", path.join(stage, archive), "-C", source], {}, "archive=unpack name=" + archive);
        const top = fs.readdirSync(source);
        const unpacked = path.join(source, "vgshell-" + release.version);
        if (top.length !== 1 || top[0] !== "vgshell-" + release.version || !fs.lstatSync(unpacked).isDirectory())
            refuse("archive=layout name=" + archive + " top=" + JSON.stringify(top));
        let shipped;
        try {
            shipped = fs.readFileSync(path.join(unpacked, "VERSION"), "utf8");
        } catch (e) {
            refuse("archive=layout name=" + archive + " version=missing");
        }
        if (shipped !== release.version + "\n") refuse("archive=version name=" + archive + " version=" + JSON.stringify(shipped));
        const destdir = path.join(stage, "tree");
        run(["bash", path.join(unpacked, "packaging", "install-system.sh")], { env: Object.assign({}, process.env, { DESTDIR: destdir, PREFIX: "/vgshell" }) }, "install=failed name=" + archive);
        writing(target, "target", () => fs.renameSync(path.join(destdir, "vgshell", "share", "vgshell"), target));
        const link = path.join(stage, "current");
        writing(path.join(data, "current"), "current", () => {
            fs.symlinkSync(path.basename(target), link);
            fs.renameSync(link, path.join(data, "current"));
        });
    } finally {
        fs.rmSync(stage, { recursive: true, force: true });
        if (repair && real(path.join(data, "current")) !== real(target)) fs.rmSync(target, { recursive: true, force: true });
    }
    const kept = [path.basename(target), path.basename(root)];
    const running = shellTree === "-" ? null : real(shellTree);
    if (running !== null && path.dirname(running) === real(data)) kept.push(path.basename(running));
    writing(data, "prune", () => {
        for (const entry of fs.readdirSync(data)) {
            if (!CURL_DIRECTORY_PATTERN.test(entry) || kept.includes(entry)) continue;
            const dir = path.join(data, entry);
            if (fs.lstatSync(dir).isDirectory()) fs.rmSync(dir, { recursive: true, force: true });
        }
    });
    process.stdout.write("ok " + (repair ? "repaired" : "updated") + "=vgshell from=" + current + " to=" + release.version + " path=" + target + "\n");
}

// The Home step consumes this plan without installing or consulting a
// marketplace. The same plan is run by `vgshell self repair` after consent.
function repairPlan(root, dataHome, version, checkout) {
    let detected;
    try { detected = detect(root, dataHome, version, checkout); }
    catch (error) {
        if (!(error instanceof Refusal)) throw error;
        return { kind: "by-hand", method: "unknown", reason: "method-unknown", cause: error.first, command: null,
            notice: "VGS could not identify this installation's owner. Repair it through the installer that supplied this copy." };
    }
    const [method, pkg, current, manager] = detected;
    const cli = path.join(root, "bin", "vgshell");
    let command;
    if (method === "checkout") command = ["git", "-C", root, "restore", "--source=HEAD", "--worktree", "--", "."];
    else if (method === "curl") command = [process.execPath, __filename, "restore", "vanillagreencom/vgshell", dataHome, root, current, "-"];
    else if (method === "package") {
        const target = manager === AUR_PRIMARY ? "aur" : manager;
        if (target === "aur" && aurHelper() === null) return { kind: "by-hand", method, reason: "no-aur-helper", command: null,
            notice: "The VGS package needs an AUR helper before its package manager can reinstall it." };
        command = [cli, "pkg", "run", "reinstall", "--manager", target, pkg];
    } else return { kind: "by-hand", method, reason: "nix", command: null,
        notice: "Update the Nix configuration that installed VGS, then rebuild it. VGS cannot change that configuration." };
    return { kind: "run", method, reason: null, command };
}

// `behind` from the facts bin/vgshell gathered: a checkout is behind while its
// upstream holds commits it lacks, a vgshell-git package while main changed
// an installed path since the commit it was built from, and every other
// install while the newest release is newer than its version.
function behind(method, pkg, current, latest, fact) {
    if (method === "checkout") return Number(fact) > 0;
    if (pkg === "vgshell-git") return fact === "true";
    return newer(latest, current);
}

// The primary manager whose packages include the AUR's, the one the table's
// `aur` overlay requires: both VGS packages there come from the AUR, which
// only an AUR helper updates.
const AUR_PRIMARY = packageTable.managerRow("aur").requires;

// What an Update runs for an install that is behind: `self` is `vgshell
// self update`, `install-helper` installs paru before that rebuild,
// `rebuild` the AUR helper's rebuild of vgshell-git, and
// `none` names the reason VGS runs nothing: an AUR package with no helper
// to update it, a package the system's packages update (the AUR helper's
// upgrade for the AUR release package, the primary manager's elsewhere),
// and a Nix tree its flake updates.
function update(method, pkg, manager, helper) {
    if (method === "checkout" || method === "curl") return { step: "self", reason: null };
    if (method === "nix") return { step: "none", reason: "nix" };
    if (method !== "package") throw new Error("self.js: method=" + method + " has no update step");
    if (manager === AUR_PRIMARY && pkg === "vgshell-git" && helper === null) return { step: "install-helper", reason: null };
    if (manager === AUR_PRIMARY && helper === null) return { step: "none", reason: "no-aur-helper" };
    if (manager === AUR_PRIMARY && pkg === "vgshell-git") return { step: "rebuild", reason: null };
    return { step: "none", reason: "package-manager" };
}

function report(format, fields) {
    const [version, method, pkg, current, manager, latest, fact, helper, error] = fields.map(v => (v === "-" || v === "" ? null : v));
    const status = { version, method, package: pkg, current, latest, behind: null, step: null, reason: null, error };
    if (error === null) {
        status.behind = behind(method, pkg, current, latest, fact);
        Object.assign(status, status.behind ? update(method, pkg, manager, helper) : { step: "none", reason: null });
    } else {
        status.latest = null;
    }
    if (format === "json") {
        process.stdout.write(JSON.stringify(status) + "\n");
        return;
    }
    const words = [];
    for (const key of ["version", "method", "package", "current", "latest", "behind", "step", "reason", "error"])
        if (status[key] !== null) words.push(key + "=" + status[key]);
    process.stdout.write(words.join(" ") + "\n");
}

// The recipe check in scripts/test-vgshell-self.sh reads installedPath.
module.exports = { installedPath };

const [verb, ...args] = process.argv.slice(2);
if (require.main === module) main(() => {
    switch (verb) {
    case "detect":
        if (args.length !== 4 || !["true", "false"].includes(args[3])) usage("detect-arguments=" + JSON.stringify(args));
        process.stdout.write(detect(args[0], args[1], args[2], args[3] === "true").join(" ") + "\n");
        return undefined;
    case "latest":
        if (args.length !== 1) usage("latest-arguments=" + JSON.stringify(args));
        return latestRelease(args[0], apiBase()).then(r => process.stdout.write(r.version + "\n"));
    case "changed":
        if (args.length !== 3) usage("changed-arguments=" + JSON.stringify(args));
        return changed(args[0], args[1], args[2]).then(answer => process.stdout.write(answer + "\n"));
    case "helper":
        if (args.length !== 0) usage("helper-arguments=" + JSON.stringify(args));
        process.stdout.write((aurHelper() || "-") + "\n");
        return undefined;
    case "report":
        if (args.length !== 10 || !["text", "json"].includes(args[0])) usage("report-arguments=" + JSON.stringify(args));
        report(args[0], args.slice(1));
        return undefined;
    case "migrate-curl-stage":
        if (args.length !== 3) usage("migrate-curl-stage-arguments=" + JSON.stringify(args));
        migrateCurlStage(...args);
        return undefined;
    case "engine-run":
        if (args.length !== 1 || !["aur", "dnf"].includes(args[0])) usage("engine-run-arguments=" + JSON.stringify(args));
        engineRun(args[0]);
        return undefined;
    case "install":
        if (args.length !== 5) usage("install-arguments=" + JSON.stringify(args));
        return install(args[0], args[1], args[2], args[3], args[4]);
    case "restore":
        if (args.length !== 5) usage("restore-arguments=" + JSON.stringify(args));
        return install(...args, true);
    case "repair-plan":
        if (args.length !== 4 || !["true", "false"].includes(args[3])) usage("repair-plan-arguments=" + JSON.stringify(args));
        process.stdout.write(JSON.stringify(repairPlan(args[0], args[1], args[2], args[3] === "true")) + "\n");
        return undefined;
    case "directory-pattern":
        if (args.length !== 0) usage("directory-pattern-arguments=" + JSON.stringify(args));
        process.stdout.write(CURL_DIRECTORY_PATTERN.source + "\n");
        return undefined;
    default:
        usage("self-subcommand=" + (verb === undefined ? "missing" : verb));
    }
    return undefined;
});
