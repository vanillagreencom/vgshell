// Paru owns the clone-to-build lifetime. VGS reviews tracked snapshots in
// its file-manager step and keeps decisions outside every agent write root.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const cp = require("node:child_process");
const { load } = require("./qml-library.js");
const files = require("./judge-files.js");
const { refuse, commandFile, onPath } = files;
const repo = path.resolve(__dirname, "../..");
const judge = load(path.join(repo, "shell/Core/PackageReview.js"));
const managers = load(path.join(repo, "shell/Core/PackageManagers.js"));
const configLogic = load(path.join(repo, "shell/Core/ConfigLogic.js"));
const MAX_DATA = 1024 * 1024;
const home = () => process.env.HOME || os.homedir();
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const object = v => v !== null && typeof v === "object" && !Array.isArray(v);
function privateFile(file, bounded = true) {
    const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
    try {
        const stat = fs.fstatSync(fd);
        if (!stat.isFile() || stat.nlink !== 1 || stat.uid !== process.getuid() || (stat.mode & 0o077) || (bounded && stat.size > MAX_DATA)) refuse("review=file-unsafe");
        return fs.readFileSync(fd, "utf8");
    } finally { fs.closeSync(fd); }
}
function ownedDirectory(dir, forbiddenMode = 0o077) {
    const stat = fs.lstatSync(dir);
    if (!stat.isDirectory() || stat.uid !== process.getuid() || (stat.mode & forbiddenMode) || fs.realpathSync(dir) !== dir) refuse("review=directory-unsafe");
    return { dev: stat.dev, ino: stat.ino };
}
function query(argv, env = {}) {
    // VGS-2482 read-only `paru -Po -- vgshell-git` on home, 2026-11-12:
    // 1.472 s. Keep the existing 120 s query bound for network variance.
    const answer = cp.spawnSync(argv[0], argv.slice(1), { cwd: home(), encoding: "utf8", timeout: 120000, maxBuffer: 16 * MAX_DATA,
        stdio: ["ignore", "pipe", "pipe"], env: { ...process.env, LC_ALL: "C", ...env } });
    return answer;
}
function output(argv, env) {
    const r = query(argv, env);
    if (r.error || r.status !== 0) throw new Error("query=" + path.basename(argv[0]) + " cause=" + (r.error?.code || r.status || r.signal));
    return r.stdout;
}

// The settings snapshot retains raw bytes for compare-before-write. Only
// ConfigLogic supplies the migrated/effective policy, including absence.
function settingsRead() {
    const shipped = files.readConfig(configLogic, path.join(repo, "config/shell.json"), "shipped-config");
    const file = path.join(process.env.XDG_CONFIG_HOME || path.join(home(), ".config"), "vgshell/shell.json");
    let text = null;
    try { text = fs.readFileSync(file, "utf8"); } catch (e) { if (e.code !== "ENOENT") refuse("user-config=unreadable"); }
    const user = files.readUserConfig(configLogic, file, "user-config", shipped.packageReviewSettingsSource, shipped.shortcutKeyMigrations, shipped.conversationSettingsMigration);
    const effective = configLogic.effectiveConfig(shipped, user);
    const settings = effective.packages?.review || { agent: "", command: "" };
    return { version: 1, text, settings };
}
function settingsWrite(snapshot, settings) {
    if (!object(snapshot) || snapshot.version !== 1 || (snapshot.text !== null && typeof snapshot.text !== "string")) refuse("review-settings=snapshot");
    const latest = settingsRead();
    if (latest.text !== snapshot.text) refuse("review-settings=changed");
    const merged = configLogic.withPackageReview(latest.text === null ? null : JSON.parse(latest.text), settings);
    if (!merged.ok) refuse("review-settings=invalid error=" + merged.error);
    const endpoint = path.join(repo, "bin/vgshell");
    const live = query([endpoint, "ipc", "call", "config", "packageReviewRead"]);
    if (live.status === 0) {
        const write = query([commandFile("bash"), path.join(__dirname, "pkg-review.sh"), "settings-ipc", endpoint, JSON.stringify({ expectedText: snapshot.text, settings })]);
        if (write.error || write.status !== 0 || write.stdout.trim() !== "ok") {
            const reply = write.stdout.trim();
            const category = /^refused: [a-z-]+=[a-z-]+(?: |$)/.exec(reply);
            refuse("review-settings=live-unconfirmed status=" + write.status + " signal=" + (write.signal || "none") + " error=" + (write.error?.code || "none")
                + " reply=" + (reply === "ok" ? "ok" : category ? category[0].trim().replaceAll(" ", "_") : "unknown") + " bytes=" + Buffer.byteLength(write.stdout));
        }
    } else {
        // Only the runner's explicit no-shell result permits offline persistence.
        // A failed/unconfirmed IPC write never falls through to this branch.
        if (live.status !== 69 || !live.stderr.startsWith("vgshell: refused: shell=not-running ")) refuse("review-settings=live-unavailable");
        const file = path.join(process.env.XDG_CONFIG_HOME || path.join(home(), ".config"), "vgshell/shell.json");
        const failed = files.editFile("user-config", file, true, current => {
            if ((current === undefined ? null : Buffer.from(current, "latin1").toString("utf8")) !== snapshot.text) refuse("review-settings=changed");
            const shipped = files.readConfig(configLogic, path.join(repo, "config/shell.json"), "shipped-config");
            const moved = latest.text === null ? { config: null } : configLogic.migrateConfig(JSON.parse(latest.text), shipped.packageReviewSettingsSource, shipped.shortcutKeyMigrations, shipped.conversationSettingsMigration);
            if (moved.error) refuse("review-settings=invalid");
            const next = configLogic.withPackageReview(moved.config, settings);
            if (!next.ok) refuse("review-settings=invalid error=" + next.error);
            return Buffer.from(JSON.stringify(next.config, null, 2) + "\n", "utf8").toString("latin1");
        });
        if (failed !== null) refuse(failed.failure);
    }
    return settingsRead();
}
function available(command) {
    try {
        if (!path.isAbsolute(command)) return onPath(command);
        fs.accessSync(command, fs.constants.X_OK);
        return fs.statSync(command).isFile();
    } catch (e) {
        if (["ENOENT", "ENOTDIR", "EACCES"].includes(e.code)) return false;
        refuse("review=probe-unavailable command=" + JSON.stringify(command) + " error=" + e.code);
    }
}
function customMode(argv) {
    if (argv === null) return "table";
    const found = managers.presentManager("aur", onPath);
    if (!found.ok) return "unknown";
    const stripped = [];
    for (let i = 0; i < argv.length; i++) {
        if (argv[i] === "--config") { if (!argv[++i]) return "unknown"; }
        else if (!argv[i].startsWith("--config=")) stripped.push(argv[i]);
    }
    try {
        if (!stripped.length || fs.realpathSync(commandFile(stripped[0]) || stripped[0]) !== fs.realpathSync(commandFile(found.binary))) return "unknown";
    } catch (_) { return "unknown"; }
    const canonical = managers.plan("aur", "upgrade", [], onPath).plan.steps[0];
    return same(stripped.slice(1), canonical.slice(1)) ? "table" : "unknown";
}
function foundAgents(settings) {
    const words = judge.commandWords(settings.command || "");
    return [...new Set(judge.REVIEW_AGENTS.map(a => a.id).concat(words.slice(0, 1)))].filter(available);
}
// The one foreground child this process waits on, a package step, a review
// question or the review agent, with the signal that interrupted it. These
// handlers are its only signal owner. The terminal sends Ctrl-C and a
// hangup to its whole foreground group, the child included, so they are
// only recorded; this process outlives the child to report and exit with
// its status. A SIGTERM sent to this process alone, as logout sends, is
// passed on to the child, so the owner's cleanup still runs; one that
// arrives between children ends this process as TERM would, and its exit
// handlers run. Once installed, Ctrl-C between children ends only the
// command the terminal's group runs then.
let foreground = null;
let signalsOwned = false;
function ownForeground(child) {
    if (!signalsOwned) {
        signalsOwned = true;
        for (const signal of ["SIGINT", "SIGHUP"]) process.on(signal, () => { if (foreground !== null) foreground.interrupted = signal; });
        process.on("SIGTERM", () => {
            if (foreground === null) process.exit(143);
            foreground.interrupted = "SIGTERM";
            foreground.child.kill("SIGTERM");
        });
    }
    foreground = { child, interrupted: null };
    return foreground;
}
function releaseForeground(slot) { if (foreground === slot) foreground = null; }
function terminalChild(argv, cwd, { stderr, env } = {}) {
    return new Promise((resolve, reject) => {
        const child = cp.spawn(commandFile("bash"), argv, { stdio: ["inherit", "inherit", stderr === undefined ? "inherit" : "pipe"], cwd: cwd || process.env.HOME || "/", env });
        const slot = ownForeground(child);
        if (child.stderr) child.stderr.on("data", data => { process.stderr.write(data); stderr(data.toString()); });
        child.on("error", e => { releaseForeground(slot); reject(new files.Refusal("runner=failed error=" + e.code)); });
        child.on("close", (status, signal) => {
            releaseForeground(slot);
            resolve(status !== null ? status : 128 + os.constants.signals[signal]);
        });
    });
}
// Foreground interactive children keep the user's terminal. The recorded
// signal cancels the phase; a signal is never converted into a successful
// review decision, even if the child exits zero.
function interactive(argv, options = {}) {
    return new Promise(resolve => {
        let stdout = "", failed = null;
        const child = cp.spawn(argv[0], argv.slice(1), { cwd: options.cwd || home(), stdio: ["inherit", options.output ? "pipe" : "inherit", "inherit"] });
        const slot = ownForeground(child);
        if (child.stdout) child.stdout.on("data", data => {
            stdout += data.toString();
            if (Buffer.byteLength(stdout) > MAX_DATA) { failed = "output-bound"; child.kill("SIGTERM"); }
        });
        child.on("error", error => { failed = error.code; });
        child.on("close", (status, signal) => {
            releaseForeground(slot);
            resolve({ status, signal: slot.interrupted || signal, stdout, error: failed });
        });
    });
}
// A question left without an answer is cancelled, and reports the status
// of a cancel, 128 or more, as PackageReview.packageOutcome judges it: its
// signal's, else 130, the user's cancel status fzf and gum give Ctrl-C.
// gum 2.0.2's choose exits 1 for Esc and 130 for Ctrl-C, and a question
// that could not be asked consents to nothing either.
async function ui(kind, ...args) {
    const result = await interactive([commandFile("bash"), path.join(__dirname, "pkg-review.sh"), kind, ...args], { output: true });
    if (result.error) refuse("review=ui-unavailable");
    if (result.status !== 0 || result.signal)
        return { cancelled: true, status: result.signal ? 128 + (os.constants.signals[result.signal] || 2) : result.status >= 128 ? result.status : 130 };
    return { value: result.stdout.trim() };
}

function effectiveConfig(config, binary) {
    if (config !== undefined) return config;
    // Reuse the package owner's effective helper-config adapter.
    const r = query([process.execPath, path.join(__dirname, "pkg-config.js"), binary]);
    if (r.error || r.status !== 0) throw new Error("config=helper-unreadable");
    return JSON.parse(r.stdout).config;
}

// The package names VGS publishes: the pkgname lines of its Arch recipes'
// .SRCINFO files, which install-system.sh ships into the runtime tree, so a
// checkout and an installed tree read the same path. { names: null, cause }
// when a recipe cannot be read or none names a package.
function publishedPackages() {
    const dir = path.join(repo, "packaging/arch"), names = [], fields = [];
    try {
        for (const entry of fs.readdirSync(dir, { withFileTypes: true }))
            if (entry.isDirectory()) for (const field of judge.srcinfoFields(fs.readFileSync(path.join(dir, entry.name, ".SRCINFO"), "utf8"))) {
                fields.push({ ...field, recipe: entry.name });
                if (field.key === "pkgname") names.push(field.value);
            }
    } catch (e) { return { names: null, fields: null, cause: e.code || "read" }; }
    return names.length ? { names, fields, cause: null } : { names: null, fields: null, cause: "empty" };
}

function aurDependencyFields(text, name) {
    const fields = new Map();
    let key = null;
    for (const line of text.split(/\r?\n/)) {
        const field = /^([^\s:][^:]*?)\s*:\s*(.*)$/.exec(line);
        if (field) {
            key = field[1].trim();
            if (fields.has(key)) throw new Error("dependency=metadata-duplicate name=" + name);
            fields.set(key, field[2].trim());
        } else if (/^\s+\S/.test(line) && key !== null) fields.set(key, fields.get(key) + " " + line.trim());
    }
    if (fields.get("Repository") !== "aur" || fields.get("Name") !== name) throw new Error("dependency=metadata-identity name=" + name);
    for (const field of ["Depends On", "Make Deps", "Check Deps"]) {
        if (!fields.has(field) || !fields.get(field)) throw new Error("dependency=metadata-missing name=" + name);
        fields.set(field, fields.get(field) === "None" ? [] : fields.get(field).split(/\s+/));
    }
    return fields;
}
function dependencyName(entry) {
    const match = /^([A-Za-z0-9@_+.-]+)(?:(?:[<>]=?|=)[^\s\x00-\x1f\x7f]+)?$/.exec(entry);
    if (!match || !managers.validName(match[1])) throw new Error("dependency=entry-invalid");
    return match[1];
}

// pacman v7.1.0 lib/libalpm/be_local.c::_alpm_local_db_write omits make/check
// dependencies from the installed record. Use the
// shipped publisher declarations and the helper's current foreign metadata
// to keep declared build tools out of the orphan removal offer.
function orphanInfo(names) {
    const tools = new Map(), unavailable = [];
    let foreign = [];
    const add = (entry, owner) => {
        const name = dependencyName(entry);
        tools.set(name, [...new Set([...(tools.get(name) || []), owner])]);
    };
    const published = publishedPackages();
    if (published.fields === null) unavailable.push("publisher=" + published.cause);
    else for (const field of published.fields)
        if (/^(make|check)depends(?:_.+)?$/.test(field.key)) add(field.value, field.recipe);
    const found = managers.presentManager("aur", onPath);
    try {
        if (!found.ok) throw new Error("helper=absent");
        const config = effectiveConfig(undefined, found.binary);
        const installed = query(["pacman", "--config", config, "-Qmq"]);
        if (installed.error || installed.signal || installed.stderr || ![0, 1].includes(installed.status)
            || (installed.status === 1 && installed.stdout)) throw new Error("foreign=unreadable");
        foreign = installed.stdout.trim().split(/\s+/).filter(Boolean);
        if (foreign.some(name => !managers.validName(name))) throw new Error("foreign=malformed");
        // One helper request bounds network/process cost for the installed
        // collection. -Si separates records with their Repository field.
        const metadata = new Map();
        if (foreign.length) {
            const answer = query([found.binary, "--config", config, "-Si", "--", ...foreign]);
            // Paru 2.2.0 keeps complete records on stdout when a requested
            // foreign package is absent from AUR (VGS-2373 home receipt).
            // Admit only that failure, never a network or truncated read.
            const missingOnly = answer.status === 1 && answer.stderr
                && answer.stderr.replace(/\n$/, "").split("\n").every(line => {
                    const match = /^error: package '([^']+)' was not found$/.exec(line);
                    return match !== null && foreign.includes(match[1]);
                });
            if (answer.error || answer.signal || !((answer.status === 0 && !answer.stderr) || missingOnly))
                throw new Error("query=" + path.basename(found.binary) + " cause=" + (answer.error?.code || answer.status || answer.signal));
            for (const record of answer.stdout.split(/(?=^Repository\s*:)/m).filter(s => s.trim())) {
                const name = /^Name\s*:\s*(\S+)\s*$/m.exec(record)?.[1];
                if (!foreign.includes(name) || metadata.has(name)) throw new Error("foreign=metadata-collection");
                metadata.set(name, record);
            }
        }
        for (const name of foreign) {
            try {
                if (!metadata.has(name)) throw new Error("foreign=metadata-missing");
                const fields = aurDependencyFields(metadata.get(name), name);
                for (const field of ["Make Deps", "Check Deps"]) for (const entry of fields.get(field)) add(entry, name);
            } catch (e) { unavailable.push(name + ":" + e.message); }
        }
    } catch (e) {
        unavailable.push(e.message);
        for (const name of foreign) unavailable.push(name + ":foreign=metadata-unreadable");
    }
    return { packages: names.map(name => ({ name, builds: tools.get(name) || [] })), unavailable };
}
// Read-only evidence, never authority to mutate or to skip package tests.
// Unknown/custom helpers and incomplete order reports preserve the stop.
function rebuildAllowed(config, target, failed) {
    if (!failed.length) return false;
    const found = managers.presentManager("aur", onPath);
    if (!found.ok) return false;
    const argv = managers.rebuildOrder(found.binary, config, target);
    if (argv === null) return false;
    const answer = query(argv);
    if (answer.error || answer.signal || answer.status !== 0 || answer.stderr) return false;
    const order = managers.parseBuildOrder(answer.stdout);
    if (!order.ok || !order.packages.some(p => p.kind === "TARGET" && p.name === target)) return false;
    return failed.every(name => !order.packages.some(p => p.name === name));
}
function inside(file, root) { return file === root || file.startsWith(root + path.sep); }
function writableTemporaryRoots() {
    return [...new Set(["/tmp", process.env.TMPDIR].filter(Boolean).map(p => fs.realpathSync(p)))];
}
function ownedFolder(dir, forbiddenMode = 0o077) {
    try { fs.mkdirSync(dir, { mode: 0o700 }); } catch (e) { if (e.code !== "EEXIST") throw e; }
    ownedDirectory(dir, forbiddenMode);
    return dir;
}
// <runtime>/vgshell. A review keeps its verdicts, outcome, agent home and
// evidence here, so REVIEWED also requires the resolved XDG_RUNTIME_DIR to
// be the user's own and outside /tmp and TMPDIR, which an agent may write.
// Retry records and build evidence (pkg-retry.js) belong to every presenter
// or AUR run, a repository package's included, and decide no review: a user
// whose TMPDIR holds the runtime folder still installs those packages, so
// that bookkeeping takes the folder without the placement check.
function runtimeFolder(reviewed) {
    const dir = process.env.XDG_RUNTIME_DIR;
    if (!dir || !path.isAbsolute(dir)) refuse("review=runtime-dir-unset");
    if (!reviewed) return ownedFolder(path.join(dir, "vgshell"), 0o022);
    const real = fs.realpathSync(dir);
    ownedDirectory(real);
    if (writableTemporaryRoots().some(root => inside(real, root))) refuse("review=runtime-dir-agent-writable");
    return ownedFolder(path.join(real, "vgshell"), 0o022);
}
function runtimeRoot() { return runtimeFolder(true); }
function workRoot(reviewed = false) { return ownedFolder(path.join(runtimeFolder(reviewed), "package-review")); }
function agentHome() { return ownedFolder(path.join(workRoot(true), "agent")); }
function createRun(prefix = "review-") {
    const dir = fs.mkdtempSync(path.join(ownedFolder(path.join(runtimeRoot(), "updates")), prefix));
    fs.chmodSync(dir, 0o700);
    return dir;
}
// One review's private run: its context, its verdict store by base and
// tree, and, once the review ended the helper's step, its outcome.
function newRun() {
    const run = createRun();
    writeJson(path.join(run, "context.json"), { attempt: 0 });
    writeJson(path.join(run, "verdicts.json"), {});
    return run;
}
function reviewRun(dir) {
    if (!path.isAbsolute(dir) || path.dirname(dir) !== path.join(runtimeRoot(), "updates")) refuse("review=run-path");
    ownedDirectory(dir);
    return dir;
}
function readJson(file) { return JSON.parse(privateFile(file)); }
function writeJson(file, value) { fs.writeFileSync(file, JSON.stringify(value) + "\n", { mode: 0o600 }); }
// The review's outcome, which ends paru's step: its file manager exits 1.
function outcome(dir, value) {
    const sentence = judge.failureLines(value.sentence || "").join(" ");
    writeJson(path.join(dir, "outcome.json"), { ...value, sentence });
    return 1;
}
const STOPPED = "You stopped the AUR packages at the review.";
function cancelled(dir, status) { return outcome(dir, { kind: "cancelled", status, sentence: STOPPED }); }
function readOutcome(dir) {
    try { return readJson(path.join(dir, "outcome.json")); }
    catch (error) { if (error.code === "ENOENT") return null; throw error; }
}
// One line Updates adds to its result list (pipeline.sh _updates_review_of),
// whatever the step's status; a terminal run shows it as it is.
function resultLine(sentence) {
    process.stderr.write("vgshell: package-result: " + judge.failureLines(sentence).join(" ") + "\n");
}
// Whether RESULT, a review outcome, skips every one of TARGETS.
function skipsAll(result, targets) {
    return result.kind === "skip-packages" && targets.length > 0 && targets.every(name => result.skipped.includes(name));
}
// The review's outcome, reported once. Its sentence is the step's cause
// when the step failed and, with status 0, the step's whole result
// (pipeline.sh _updates_review_of). The owner's Stop or Skip skips the step
// as a Skip of every one of TARGETS does: status 0, package-skipped.
function finalOutcome(manager, helper, result, targets) {
    process.stderr.write("vgshell: package-review: " + result.sentence + "\n");
    if (result.kind === "cancelled") return { status: result.status, outcome: { kind: "package-cancelled", manager, status: result.status } };
    if (result.kind === "skipped" || skipsAll(result, targets)) return { status: 0, outcome: { kind: "package-skipped", manager } };
    return { status: 1, outcome: { kind: "package-failed", manager, helper, status: 1, lines: judge.failureLines(result.sentence) } };
}
// The work root holds every agent home and evidence folder; its path is
// the same whichever check made it.
function assertCloneOutsideWriteRoots(clone, evidence) {
    if ([...writableTemporaryRoots(), evidence, workRoot()].some(root => inside(clone, root)))
        throw new Error("The AUR build folder is inside a folder the review agent can change.");
}
// aur-fetch 0.11.3 Fetch::make_view supplies clone symlinks, convenience
// .PKGBUILD/.SRCINFO links and optional .diff links; only clones are bases.
// https://docs.rs/crate/aur-fetch/0.11.3/source/src/fetch.rs
function copyView(view, evidence, bootstrapClone) {
    const sources = bootstrapClone ? [["paru", bootstrapClone]] : fs.readdirSync(view)
        .filter(name => fs.statSync(path.join(view, name)).isDirectory()).map(name => [name, path.join(view, name)]);
    if (!sources.length) throw new Error("Paru supplied no AUR build files to review.");
    const published = publishedPackages();
    const bases = [], links = [];
    fs.mkdirSync(path.join(evidence, "build"), { mode: 0o700 });
    fs.mkdirSync(path.join(evidence, "recipe"), { mode: 0o700 });
    fs.mkdirSync(path.join(evidence, "install"), { mode: 0o700 });
    for (const [base, source] of sources) {
        if (!managers.validName(base) || base.includes("/")) throw new Error("Paru supplied an invalid AUR package base.");
        const clone = fs.realpathSync(source);
        if (!fs.statSync(clone).isDirectory()) throw new Error("Paru supplied an unreadable AUR build folder.");
        assertCloneOutsideWriteRoots(clone, evidence);
        const folder = path.join(evidence, "build", base);
        fs.mkdirSync(folder, { mode: 0o700 });
        const copied = query([commandFile("python3"), path.join(__dirname, "pkg-review-copy.py"), clone, folder]);
        if (copied.error || copied.status !== 0)
            throw new Error("The tracked AUR build files could not be copied.", { cause: copied.error ? "copy=unstarted error=" + copied.error.code : copied.stderr.trim() || "copy=failed status=" + (copied.status ?? copied.signal) });
        const snapshot = JSON.parse(copied.stdout);
        const fields = judge.srcinfoFields(fs.readFileSync(path.join(folder, ".SRCINFO"), "utf8"));
        const declared = fields.filter(f => f.key === "pkgbase").map(f => f.value);
        const names = fields.filter(f => f.key === "pkgname").map(f => f.value);
        if (!same(declared, [base]) || !names.length || names.some(name => dependencyName(name) !== name)) throw new Error("An AUR recipe has unreadable package names.");
        if (!snapshot.files.includes("PKGBUILD")) throw new Error("An AUR recipe has no tracked PKGBUILD.");
        // A base is exempt only when every split package has the publisher.
        const own = names.every(name => judge.publisher(name, true, published.names) === "vgs");
        if (own) {
            fs.rmSync(folder, { recursive: true });
            bases.push({ base, names, fields, tree: snapshot.tree, published: true });
            continue;
        }
        for (const link of snapshot.symlinks) links.push({ base, ...link });
        let diff = null;
        if (!bootstrapClone) {
            try {
                const file = fs.realpathSync(path.join(view, base + ".diff"));
                const stat = fs.statSync(file);
                if (!stat.isFile()) throw new Error("The AUR recipe diff is not a file.");
                diff = fs.readFileSync(file);
                fs.writeFileSync(path.join(evidence, "recipe", base + ".diff"), diff, { mode: 0o600 });
            } catch (error) { if (error.code !== "ENOENT") throw error; }
        }
        bases.push({ base, names, fields, folder, tree: snapshot.tree, diff: diff !== null });
    }
    fs.writeFileSync(path.join(evidence, "symlinks.txt"), links.map(link => JSON.stringify(link)).join("\n") + "\n", { mode: 0o600 });
    return bases;
}
// The installed version of each of NAMES, from one `pacman -Q -- NAMES...`,
// as one `pacman -Q -- NAME` for each would answer it: the version, null
// when the package is not installed, and no entry when it could not be
// read. pacman v7.1.0 src/pacman/query.c:464-519 prints one `NAME VERSION`
// line (display, :324-344) for each target it finds, in target order, and
// exits 1 when any target is not found; a target that only a package
// providing it satisfies (alpm_find_satisfier) prints that package's line.
// So when status 1 and every line matched its target by name, the targets
// left are not installed. A line left over means a target was found under
// another name, which one alone would answer as unreadable; which target
// cannot be told, so every target left is unreadable.
function installedVersions(names, config) {
    const answer = query(["pacman", "--config", config, "-Q", "--", ...names]);
    const versions = new Map();
    if (answer.error || answer.signal || ![0, 1].includes(answer.status)) return versions;
    const rows = answer.stdout.split("\n");
    if (rows.at(-1) === "") rows.pop();
    const left = [];
    let next = 0;
    for (const name of names) {
        const row = next < rows.length ? /^(\S+) (\S+)$/.exec(rows[next]) : null;
        if (!row || row[1] !== name) { left.push(name); continue; }
        next++;
        if (!row[2].includes("/")) versions.set(name, row[2]);
    }
    if (answer.status === 1 && next === rows.length) for (const name of left) versions.set(name, null);
    return versions;
}
// DB is the configuration's DBPath and INSTALLED installedVersions' answer,
// each read once per review.
function installEvidence(base, installed, db, evidence) {
    const risks = [], lines = [];
    for (const name of base.names) {
        let section = "", inherited = "", own, script;
        for (const field of base.fields) {
            if (field.key === "pkgbase") section = "base";
            if (field.key === "pkgname") section = field.value === name ? "own" : "other";
            if (field.key === "install" && section === "base") inherited = field.value;
            if (field.key === "install" && section === "own") own = field.value;
        }
        script = own === undefined ? inherited : own;
        if (script && (script.includes("/") || script === "." || script === "..")) throw new Error("An AUR recipe names an unsafe install script.");
        const next = script ? fs.readFileSync(path.join(base.folder, script), "utf8") : null;
        const version = installed.get(name);
        if (version === undefined) throw new Error("An installed package version could not be read.");
        let previous = null;
        if (version !== null) {
            try { previous = fs.readFileSync(path.join(db, "local", name + "-" + version, "install"), "utf8"); }
            catch (error) { if (error.code !== "ENOENT") throw error; }
        }
        const change = judge.installScriptChange(previous, next);
        lines.push("install " + name + " " + change.state);
        for (const concern of change.risks) risks.push({ name, concern });
        if (change.state === "changed") {
            const old = path.join(evidence, "install", name + ".old");
            fs.writeFileSync(old, previous, { mode: 0o600 });
            const compared = query(["diff", "-u", "--", old, path.join(base.folder, script)]);
            if (compared.error || ![0, 1].includes(compared.status)) throw new Error("An installed package script could not be compared.");
            fs.writeFileSync(path.join(evidence, "install", name + ".diff"), compared.stdout, { mode: 0o600 });
        }
    }
    return { lines, risks };
}
// All pending bases come from the same paru view, including dependencies.
// .SRCINFO depends/make/checkdepends and provides connect split package names.
function skipDependents(bases, names) {
    const skipped = new Set(names);
    for (;;) {
        const before = skipped.size;
        const unavailable = new Set();
        for (const base of bases) if (base.names.some(name => skipped.has(name))) {
            unavailable.add(base.base);
            for (const name of base.names) { unavailable.add(name); skipped.add(name); }
            for (const field of base.fields) if (/^provides(?:_|$)/.test(field.key)) unavailable.add(dependencyName(field.value));
        }
        for (const base of bases)
            if (base.fields.some(field => /^(?:(?:make|check)?depends)(?:_|$)/.test(field.key) && unavailable.has(dependencyName(field.value))))
                for (const name of base.names) skipped.add(name);
        if (skipped.size === before) return [...skipped];
    }
}
// paru v2.1.0 (70f66dc9) devel.rs::parse_url tracks a base's unpinned git
// sources from its SRCINFO, not package-name suffixes. FIELDS is one
// base's SRCINFO; its base fields precede the first pkgname.
const UNPINNED_GIT = /^git[^:]*:\/\/[^#]+(?:#(?!commit=|tag=).*)?$/;
function develBase(fields) {
    const first = fields.findIndex(field => field.key === "pkgname");
    const own = fields.slice(0, first < 0 ? fields.length : first);
    if (!own.some(field => /^source(?:_|$)/.test(field.key) && UNPINNED_GIT.test(field.value.split("::").pop()))) return null;
    return own.find(field => field.key === "pkgbase")?.value || null;
}
// The devel bases a run without a file-manager review builds: the
// VGS-published recipes that build one of TARGETS. null when the shipped
// recipes cannot be read.
function publishedTracking(targets) {
    if (!targets.length) return [];
    const published = publishedPackages();
    if (published.fields === null) return null;
    const recipes = new Map();
    for (const field of published.fields) recipes.set(field.recipe, [...(recipes.get(field.recipe) || []), field]);
    return [...recipes.values()].filter(fields => fields.some(field => field.key === "pkgname" && targets.includes(field.value)))
        .map(develBase).filter(base => base !== null);
}
// The devel bases of the last view paru handed RUN's review, which are the
// bases it built: [] when paru reviewed none, null when unreadable.
function viewTracking(run) {
    try { return readJson(path.join(run, "tracking.json")); }
    catch (error) { return error.code === "ENOENT" ? [] : null; }
}
// Why an agent's verdict file gives no verdict, or the verdict. The agent
// writes this file, so an unsafe one is no verdict either.
function readVerdict(file, names) {
    let text;
    try { text = privateFile(file); }
    catch (error) {
        if (error.code === "ENOENT") return { ok: false, problem: "is missing" };
        if (error instanceof files.Refusal || error.code === "ELOOP") return { ok: false, problem: "is unsafe to read" };
        return { ok: false, problem: "could not be read (" + (error.code || error.name) + ")" };
    }
    const parsed = judge.parseVerdict(text, names);
    if (parsed.ok) return parsed;
    const line = /^line=(\d+)$/.exec(parsed.error);
    return { ok: false, problem: line ? "is malformed at line " + line[1] : parsed.error === "control-character" ? "holds a control character" : "does not match its flags" };
}
async function unavailableCustom() {
    const answer = await ui("unavailable", "The custom AUR command does not support the package review.");
    if (answer.cancelled) return answer.status;
    if (answer.value === "Yes") return 0;
    // Updates reads a declined= refusal as the owner's own No.
    if (answer.value === "No") refuse("declined=review-unavailable", undefined, 1, "The AUR packages were not updated.");
    refuse("review=choice-invalid");
}
// This process as polkit names a subject: pid, start time and uid. The
// start time is /proc/<pid>/stat's field 22, which polkit's
// polkit_unix_process_get_start_time reads too, so a reused pid differs.
function processSubject() {
    const fields = fs.readFileSync("/proc/self/stat", "utf8").replace(/^.*\) /s, "").split(" ");
    return process.pid + "," + fields[19] + "," + process.getuid();
}
// The statuses of the agent-run wrapper whose agent ended by Ctrl-C, a
// hangup or TERM, 128 plus the signal's number, as bash reports them.
const STOP_STATUSES = new Set(["SIGINT", "SIGHUP", "SIGTERM"].map(name => 128 + os.constants.signals[name]));
// { cancelled, status }, { verdict } or { failure }, a sentence naming
// why the agent gave no verdict.
async function agentAttempt(run, pristine, plan, names) {
    const evidence = fs.mkdtempSync(path.join(workRoot(true), "evidence-"));
    const capture = path.join(run, path.basename(evidence) + ".output");
    try {
        fs.cpSync(pristine, evidence, { recursive: true });
        const prompt = fs.readFileSync(path.join(__dirname, "review/third-party.md"), "utf8").replaceAll("{review_dir}", evidence);
        const launch = judge.reviewCommand(plan, { home: agentHome(), evidence });
        const shown = await ui("show", "Reviewing AUR build files as your user", ...launch.argv);
        if (shown.cancelled) return shown;
        // An earlier paru step's elevation can leave an authorization this
        // user's later processes reuse. No agent runs while one is live:
        // each elevator on PATH runs its PackageManagers.CREDENTIAL_DROPS
        // argv, as written. A drop whose own command is absent, pkcheck
        // without polkit, has none to end; one that could not run passes
        // only when its check shows no authorization held.
        for (const elevator of managers.ELEVATORS) {
            const drop = managers.CREDENTIAL_DROPS[elevator];
            if (drop === null || !onPath(elevator) || !onPath(drop.argv[0])) continue;
            const dropped = query([commandFile(drop.argv[0]), ...drop.argv.slice(1)]);
            const ran = result => !result.error && !result.signal;
            if (ran(dropped) && dropped.status === 0) continue;
            let failed = dropped, step = "drop";
            if (ran(dropped) && drop.unended !== null && dropped.stderr.startsWith(drop.unended.stderr)) {
                const check = drop.unended.check.map(word => word === "{process}" ? processSubject() : word);
                failed = query([commandFile(check[0]), ...check.slice(1)]);
                step = "check";
                if (ran(failed) && drop.unended.unheld.includes(failed.status)) continue;
            }
            throw new Error("VGS could not end the saved " + elevator + " authorization before the review.", { cause: step + "=" + (failed.error ? "unstarted error=" + failed.error.code
                : "status=" + (failed.status ?? failed.signal) + (failed.stderr.trim() ? " " + failed.stderr.trim().replace(/\s+/g, " ") : "")) });
        }
        const ended = await interactive([commandFile("bash"), path.join(__dirname, "pkg-review.sh"), "agent-run", capture, ...launch.argv, prompt], { cwd: launch.cwd });
        if (ended.signal) return { cancelled: true, status: 128 + (os.constants.signals[ended.signal] || 2) };
        if (STOP_STATUSES.has(ended.status)) return { cancelled: true, status: ended.status };
        // The wrapper leaves no capture when it could not cut the output.
        let said = "";
        try {
            const last = judge.failureLines(privateFile(capture, false)).at(-1);
            if (last) said = " Its last line: " + last + (/[.!?]$/.test(last) ? "" : ".");
        } catch (error) {
            if (error.code !== "ENOENT") throw error;
            said = " VGS could not read its output.";
        }
        if (ended.error || ended.status !== 0) return { failure: "The " + plan.label + " review stopped without a result." + said };
        const verdict = readVerdict(path.join(evidence, "verdict"), names);
        return verdict.ok ? { verdict } : { failure: "The " + plan.label + " review's verdict " + verdict.problem + "." + said };
    } finally {
        fs.rmSync(evidence, { recursive: true, force: true });
        fs.rmSync(capture, { force: true });
    }
}
// One flagged package's result line, with the pending packages skipped
// with it.
function skipSentence(name, risks, dependents) {
    const alongside = dependents.length ? " " + dependents.join(", ") + (dependents.length === 1 ? " was" : " were") + " skipped with it." : "";
    return name + " skipped: the review flagged " + risks.join(" ").replace(/[.!?]+$/, "") + "." + alongside;
}
async function reviewFiles(run, view, config, bootstrapClone = null) {
    reviewRun(run);
    const context = readJson(path.join(run, "context.json"));
    const previousUmask = process.umask(0o077);
    // This invocation's pristine source is never inside an agent write root.
    // A failed agent may change its copy; a fallback gets these bytes again.
    const pristine = fs.mkdtempSync(path.join(run, "snapshot-"));
    try {
        if (process.env.VGS_TUI_SUDO_SESSION && fs.existsSync("/proc/" + process.env.VGS_TUI_SUDO_SESSION))
            throw new Error("The AUR review cannot run during an active password session.");
        const bases = copyView(view, pristine, bootstrapClone);
        writeJson(path.join(run, "tracking.json"), bases.map(base => develBase(base.fields)).filter(base => base !== null));
        const store = readJson(path.join(run, "verdicts.json"));
        const pending = bases.filter(base => !base.published && store[base.base + ":" + base.tree]?.decision !== "accepted");
        if (!pending.length) return 0;
        const names = pending.flatMap(base => base.names);
        const lines = [], deterministic = [];
        const db = output(["pacman-conf", "--config", config, "DBPath"]).trim();
        if (!path.isAbsolute(db)) throw new Error("The installed package scripts could not be located.");
        const installed = installedVersions(names, config);
        for (const base of pending) {
            lines.push(...base.names.map(name => "aur " + name + " ? ?"));
            lines.push("recipe " + base.base + " " + (base.diff ? "changed" : "new"));
            const scripts = installEvidence(base, installed, db, pristine);
            lines.push(...scripts.lines); deterministic.push(...scripts.risks);
        }
        fs.writeFileSync(path.join(pristine, "packages.txt"), lines.join("\n") + "\n", { mode: 0o600 });
        const settings = settingsRead().settings;
        const initial = judge.initialChoice(settings, foundAgents(settings));
        let answer = !initial.ask ? { value: initial.action === "review" ? "Review" : "Install without review" }
            : await ui("offer", initial.action === "review" ? "Review" : "Install without review", "AUR packages: " + names.join(", "));
        if (answer.cancelled) return cancelled(run, answer.status);
        if (answer.value === "Install without review") {
            for (const base of pending) store[base.base + ":" + base.tree] = { decision: "accepted", names: base.names, reviewed: false };
            writeJson(path.join(run, "verdicts.json"), store);
            return 0;
        }
        if (answer.value !== "Review") refuse("review=choice-invalid");
        let plan = judge.reviewPlan(settings, foundAgents(settings));
        let verdict = null;
        for (;;) {
            let failure;
            if (["agent", "command"].includes(plan.state)) {
                const attempt = await agentAttempt(run, pristine, plan, names);
                if (attempt.cancelled) return cancelled(run, attempt.status);
                if (attempt.verdict) { verdict = attempt.verdict; break; }
                failure = attempt.failure;
            } else failure = plan.state === "missing" ? plan.label + " is not installed." : "No review agent is installed.";
            const other = judge.REVIEW_AGENTS.find(agent => agent.id !== plan.agent && available(agent.id));
            answer = await ui("agent-failed", failure, other ? other.label : "");
            if (answer.cancelled) return cancelled(run, answer.status);
            if (other && answer.value === "Use " + other.label) {
                plan = judge.reviewPlan({ agent: other.id, command: "" }, foundAgents({}));
                continue;
            }
            if (answer.value === "Install without review") break;
            if (answer.value !== "Skip AUR packages") refuse("review=choice-invalid");
            return outcome(run, { kind: "skipped", sentence: failure + " You chose to skip the AUR packages." });
        }
        const concerns = new Map();
        for (const flag of [...(verdict?.flags || []), ...deterministic]) {
            const concern = judge.failureLines(flag.concern).join(" ");
            concerns.set(flag.name, [...(concerns.get(flag.name) || []), concern]);
        }
        let skipped = [], results = [];
        if (concerns.size) {
            const flagged = [...concerns.keys()];
            if (context.attempt > 0) return outcome(run, { kind: "failed", sentence: "AUR packages stopped: the review flagged " + flagged.join(", ") + " again." });
            answer = await ui("flagged", flagged.join(", "), [...concerns].map(([name, risks]) => name + ": " + risks.join(" ")).join("\n"));
            if (answer.cancelled) return cancelled(run, answer.status);
            if (answer.value === "Stop") return outcome(run, { kind: "skipped", sentence: STOPPED });
            if (answer.value === "Skip " + flagged.join(", ")) {
                skipped = skipDependents(bases, flagged);
                results = flagged.map(name => skipSentence(name, concerns.get(name), skipDependents(bases, [name]).filter(other => other !== name)));
            } else if (answer.value !== "Install anyway") refuse("review=choice-invalid");
        } else if (verdict !== null) {
            const shown = await ui("result", "No concerns found: " + names.join(", ") + ".");
            if (shown.cancelled) return cancelled(run, shown.status);
        }
        for (const base of pending) store[base.base + ":" + base.tree] = { decision: base.names.some(name => skipped.includes(name)) ? "skipped" : "accepted", names: base.names, verdict };
        writeJson(path.join(run, "verdicts.json"), store);
        if (skipped.length) {
            const shown = await ui("result", "Packages skipped after the review: " + skipped.join(", ") + ".");
            if (shown.cancelled) return cancelled(run, shown.status);
            return outcome(run, { kind: "skip-packages", skipped, results, sentence: results.join(" ") });
        }
        return 0;
    } catch (error) {
        if (error instanceof files.Refusal) throw error;
        // The sentence is the owner's; the keyed line keeps the failure's
        // own class for the log, never on the result list.
        const own = /^(?:The |An |Paru |VGS )/.test(error.message);
        const detail = own ? error.cause : error.code ? "error=" + error.code + (error.syscall ? " op=" + error.syscall : "") + (error.path ? " path=" + error.path : "") : "error=" + error.name;
        if (detail !== undefined) process.stderr.write("vgshell: review-diagnostic: " + detail + "\n");
        return outcome(run, { kind: "unavailable", sentence: "AUR packages skipped: " + (own ? error.message : "VGS could not prepare the AUR build files for this review.") });
    } finally {
        fs.rmSync(pristine, { recursive: true, force: true });
        process.umask(previousUmask);
    }
}
// Only VGS-published targets may take this shortcut. The full read-only
// resolver order includes make/check dependencies before any clone is built.
// { pending, covered }: pending the package names the step builds as VGS
// holds them, NAMES or an upgrade's pending list from the helper's own
// check, null when that list could not be read; covered those names, or
// null when the review stays.
function helperReviewCovered(action, names, ignored, config, binary) {
    const unread = { pending: null, covered: null };
    let targets = names;
    if (action === "upgrade") {
        const check = managers.checkFor("aur", binary).check;
        if (!check) return unread;
        const command = check.argv.slice();
        if (config) command.splice(1, 0, "--config", config);
        const read = query(command);
        if (read.error || read.signal) return unread;
        const result = managers.checkOutcome(check, read.status, read.stdout, read.stderr);
        if (result.error) return unread;
        targets = result.packages.map(pkg => pkg.name).filter(name => !ignored.includes(name));
    }
    const pending = targets.map(name => name.split("/").pop());
    const published = publishedPackages();
    if (published.names === null || !targets.length || targets.some(name => judge.publisher(name.split("/").pop(), true, published.names) !== "vgs"))
        return { pending, covered: null };
    const command = [binary, ...(config ? ["--config", config] : []), "-Po", "--", ...targets];
    const read = query(command);
    if (read.error || read.signal || read.status !== 0 || read.stderr) return { pending, covered: null };
    const order = managers.parseBuildOrder(read.stdout);
    const covered = order.ok && order.packages.some(pkg => pkg.origin === "AUR")
        && order.packages.filter(pkg => pkg.origin === "AUR").every(pkg => judge.publisher(pkg.name, true, published.names) === "vgs");
    return { pending, covered: covered ? pending : null };
}
// paru 2.2.0 install.rs:1699 puts FileManagerFlags before the view, so
// the launcher's call carries them as extra words after --.
function refuseFileManagerFlags(run) {
    reviewRun(run);
    outcome(run, { kind: "failed", sentence: "The FileManagerFlags setting in paru.conf adds options the AUR review cannot take. Remove it from paru.conf to review AUR packages." });
    refuse("review-files=file-manager-flags");
}
function launcher(run, config) {
    const file = path.join(run, "review");
    const endpoint = path.join(repo, "bin/vgshell-pkg");
    // Paru invokes FileManager as one executable, then appends its flags and
    // view. Encode our arguments as data; foreign FileManagerFlags remain
    // extra arguments after --, which review-files refuses.
    fs.writeFileSync(file, "#!" + process.execPath + "\nprocess.argv = " + JSON.stringify([process.execPath, endpoint, "review-files", "--run", run, "--config", config, "--"]) + ".concat(process.argv.slice(2));\nrequire(" + JSON.stringify(endpoint) + ");\n", { mode: 0o700, flag: "wx" });
    return file;
}
// EXECUTE runs the package step; its admitted argument carries the review
// command, the saved decline, tracking(), the devel bases the step built,
// which bin/vgshell-pkg checks after paru --gendb, and pending, the
// package names helperReviewCovered read, which name an upgrade's failed
// package for its retry; null when unread or the review is turned off.
async function withReview(action, manager, names, ignored = [], installs = [], config, execute) {
    const original = { names, ignored, installs, config };
    if (manager !== "aur" || action === "remove") return execute(original);
    const found = managers.presentManager(manager, onPath);
    if (!found.ok || path.basename(found.binary) !== "paru") return execute(original);
    const effective = effectiveConfig(config, found.binary);
    const targets = names.concat(installs).map(name => name.split("/").pop());
    const settings = settingsRead().settings;
    const { pending, covered } = settings.enabled === false ? { pending: null, covered: null }
        : helperReviewCovered(action, names.concat(installs), ignored, effective, found.binary);
    if (settings.enabled === false || covered !== null) {
        // An upgrade with the review turned off reads no pending list, so
        // it names no target to check.
        const built = covered || (action === "upgrade" ? [] : targets);
        return execute({ ...original, pending, skipReview: true, tracking: () => publishedTracking(built) });
    }
    const run = newRun();
    const reviewCommand = launcher(run, effective);
    const tracking = () => viewTracking(run);
    try {
        let ended = await execute({ ...original, pending, reviewCommand, skipReview: false, tracking });
        let result = readOutcome(run);
        if (result?.kind === "skip-packages") {
            const skipped = result.skipped;
            if (action !== "upgrade" && skipsAll(result, targets)) return finalOutcome(manager, "paru", result, targets);
            const next = action === "upgrade" ? { ...original, ignored: [...new Set(ignored.concat(skipped))] }
                : { ...original, names: names.filter(name => !skipped.includes(name.split("/").pop())), installs: installs.filter(name => !skipped.includes(name.split("/").pop())) };
            // The skip is a result of its own, whatever paru's second call
            // answers; that call's own failure keeps its cause.
            for (const line of result.results) resultLine(line);
            writeJson(path.join(run, "context.json"), { attempt: 1 });
            fs.unlinkSync(path.join(run, "outcome.json"));
            ended = await execute({ ...next, pending, reviewCommand, skipReview: false, tracking });
            result = readOutcome(run);
        }
        return result === null ? ended : finalOutcome(manager, "paru", result, targets);
    } finally { fs.rmSync(run, { recursive: true, force: true }); }
}
function buildRoot() {
    const cache = process.env.XDG_CACHE_HOME || path.join(home(), ".cache");
    const dir = path.join(cache, "vgshell/package-build");
    fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
    const real = fs.realpathSync(dir);
    ownedDirectory(real);
    assertCloneOutsideWriteRoots(real, workRoot());
    return real;
}
// The helper bootstrap's review of its fetched clone, whose one target is
// paru: null when the build may go on, else the run's { status, outcome }.
async function bootstrap(tree) {
    if (settingsRead().settings.enabled === false) return null;
    const run = newRun();
    try {
        await reviewFiles(run, tree, effectiveConfig(undefined, "pacman"), tree);
        const result = readOutcome(run);
        return result === null ? null : finalOutcome("aur", "makepkg", result, ["paru"]);
    } finally { fs.rmSync(run, { recursive: true, force: true }); }
}
module.exports = { available, bootstrap, buildRoot, customMode, judge, settingsRead, settingsWrite, createRun, withReview, reviewFiles,
    refuseFileManagerFlags, resultLine, terminalChild, workRoot, ownedDirectory, privateFile, ui, orphanInfo, rebuildAllowed, unavailableCustom };
