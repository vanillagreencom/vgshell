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
// Foreground interactive children keep the user's terminal. Retaining the
// child handle lets directed signals cancel the phase; a signal is never
// converted into a successful review decision, even if the child exits zero.
function interactive(argv, options = {}) {
    return new Promise(resolve => {
        let stdout = "", failed = null, interrupted = null;
        const child = cp.spawn(argv[0], argv.slice(1), { cwd: options.cwd || home(), stdio: ["inherit", options.output ? "pipe" : "inherit", "inherit"] });
        const handlers = new Map();
        for (const signal of ["SIGINT", "SIGHUP", "SIGTERM"]) {
            const handler = () => { interrupted = signal; child.kill(signal); };
            handlers.set(signal, handler); process.on(signal, handler);
        }
        if (child.stdout) child.stdout.on("data", data => {
            stdout += data.toString();
            if (Buffer.byteLength(stdout) > MAX_DATA) { failed = "output-bound"; child.kill("SIGTERM"); }
        });
        child.on("error", error => { failed = error.code; });
        child.on("close", (status, signal) => {
            for (const [name, handler] of handlers) process.removeListener(name, handler);
            resolve({ status, signal: interrupted || signal, stdout, error: failed });
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

function effectiveConfig(request, binary) {
    if (request.config !== null) return request.config;
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
        const config = effectiveConfig({ config: null }, found.binary);
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
function runtimeRoot() {
    const dir = process.env.XDG_RUNTIME_DIR;
    if (!dir || !path.isAbsolute(dir)) refuse("review=runtime-dir-unset");
    const real = fs.realpathSync(dir);
    ownedDirectory(real);
    if (writableTemporaryRoots().some(root => inside(real, root))) refuse("review=runtime-dir-agent-writable");
    return ownedFolder(path.join(real, "vgshell"), 0o022);
}
// Migration and retry callers also use this private folder, including in
// a shared presenter namespace. Actual reviews require runtimeRoot first.
function workRoot() {
    if (!process.env.XDG_RUNTIME_DIR) refuse("review=runtime-dir-unset");
    const shared = ownedFolder(path.join(process.env.XDG_RUNTIME_DIR, "vgshell"), 0o022);
    return ownedFolder(path.join(shared, "package-review"));
}
function agentHome() { return ownedFolder(path.join(workRoot(), "agent")); }
function createRun(prefix = "review-") {
    const dir = fs.mkdtempSync(path.join(ownedFolder(path.join(runtimeRoot(), "updates")), prefix));
    fs.chmodSync(dir, 0o700);
    return dir;
}
function reviewRun(dir) {
    if (!path.isAbsolute(dir) || path.dirname(dir) !== path.join(runtimeRoot(), "updates")) refuse("review=run-path");
    ownedDirectory(dir);
    return dir;
}
function readJson(file) { return JSON.parse(privateFile(file)); }
function writeJson(file, value) { fs.writeFileSync(file, JSON.stringify(value) + "\n", { mode: 0o600 }); }
function outcome(dir, value) {
    const sentence = judge.failureLines(value.sentence || "").join(" ");
    writeJson(path.join(dir, "outcome.json"), { ...value, sentence });
    return 1;
}
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
        if (copied.error || copied.status !== 0) throw new Error("The tracked AUR build files could not be copied.");
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
function installEvidence(base, config, evidence) {
    const risks = [], lines = [];
    const db = output(["pacman-conf", "--config", config, "DBPath"]).trim();
    if (!path.isAbsolute(db)) throw new Error("The installed package scripts could not be located.");
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
        const installed = query(["pacman", "--config", config, "-Q", "--", name]);
        if (installed.error || installed.signal || ![0, 1].includes(installed.status)) throw new Error("An installed package version could not be read.");
        let previous = null;
        if (installed.status === 0) {
            const row = /^(\S+) (\S+)\n?$/.exec(installed.stdout);
            if (!row || row[1] !== name || row[2].includes("/")) throw new Error("An installed package version could not be read.");
            try { previous = fs.readFileSync(path.join(db, "local", name + "-" + row[2], "install"), "utf8"); }
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
function cleanOutcome(manager, status, sentence) {
    if (status >= 128) return { status, outcome: { kind: "package-cancelled", manager, status } };
    return { status, outcome: { kind: "package-failed", manager, helper: "paru", status, lines: judge.failureLines(sentence) } };
}
async function unavailableCustom() {
    const answer = await ui("unavailable", "The custom AUR command does not support the package review.");
    if (answer.cancelled) return answer.status;
    if (answer.value === "Yes") return 0;
    if (answer.value === "No") return 1;
    refuse("review=choice-invalid");
}
async function agentAttempt(run, pristine, plan, names) {
    const evidence = fs.mkdtempSync(path.join(workRoot(), "evidence-"));
    const capture = path.join(run, path.basename(evidence) + ".output");
    try {
        fs.cpSync(pristine, evidence, { recursive: true });
        const prompt = fs.readFileSync(path.join(__dirname, "review/third-party.md"), "utf8").replaceAll("{review_dir}", evidence);
        const launch = judge.reviewCommand(plan, { home: agentHome(), evidence });
        const shown = await ui("show", "Reviewing AUR build files as your user", ...launch.argv);
        if (shown.cancelled) return shown;
        const ended = await interactive([commandFile("bash"), path.join(__dirname, "pkg-review.sh"), "agent-run", capture, ...launch.argv, prompt], { cwd: launch.cwd });
        let lastLine = "No review result was written.", verdict = null;
        try { lastLine = judge.failureLines(privateFile(capture, false)).at(-1) || lastLine; }
        catch (error) { if (error.code !== "ENOENT") throw error; }
        if (!ended.error && !ended.signal && ended.status === 0) {
            try {
                const parsed = judge.parseVerdict(privateFile(path.join(evidence, "verdict")), names);
                if (parsed.ok) verdict = parsed;
            } catch (_) { /* An unsafe or unreadable agent file is no verdict. */ }
        }
        return { verdict, lastLine };
    } finally {
        fs.rmSync(evidence, { recursive: true, force: true });
        fs.rmSync(capture, { force: true });
    }
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
        const store = readJson(path.join(run, "verdicts.json"));
        const pending = bases.filter(base => !base.published && store[base.base + ":" + base.tree]?.decision !== "accepted");
        if (!pending.length) return 0;
        const names = pending.flatMap(base => base.names);
        const lines = [], deterministic = [];
        for (const base of pending) {
            lines.push(...base.names.map(name => "aur " + name + " ? ?"));
            lines.push("recipe " + base.base + " " + (base.diff ? "changed" : "new"));
            const scripts = installEvidence(base, config, pristine);
            lines.push(...scripts.lines); deterministic.push(...scripts.risks);
        }
        fs.writeFileSync(path.join(pristine, "packages.txt"), lines.join("\n") + "\n", { mode: 0o600 });
        const settings = settingsRead().settings;
        const initial = judge.initialChoice(settings, foundAgents(settings));
        let answer = !initial.ask ? { value: initial.action === "review" ? "Review" : "Install without review" }
            : await ui("offer", initial.action === "review" ? "Review" : "Install without review", "AUR packages: " + names.join(", "));
        if (answer.cancelled) return outcome(run, { kind: "cancelled", status: answer.status, sentence: "You stopped the AUR packages at the review, so they were skipped." });
        if (answer.value === "Install without review") {
            for (const base of pending) store[base.base + ":" + base.tree] = { decision: "accepted", names: base.names, reviewed: false };
            writeJson(path.join(run, "verdicts.json"), store);
            return 0;
        }
        if (answer.value !== "Review") refuse("review=choice-invalid");
        let plan = judge.reviewPlan(settings, foundAgents(settings));
        let verdict;
        for (;;) {
            let lastLine = "No review result was written.";
            verdict = null;
            if (["agent", "command"].includes(plan.state)) {
                const attempt = await agentAttempt(run, pristine, plan, names);
                if (attempt.cancelled) return outcome(run, { kind: "cancelled", status: attempt.status, sentence: "You stopped the AUR packages at the review, so they were skipped." });
                verdict = attempt.verdict;
                lastLine = attempt.lastLine;
            }
            if (verdict !== null) break;
            const label = plan.label || "selected agent";
            const alternatives = judge.REVIEW_AGENTS.filter(agent => agent.id !== plan.agent && available(agent.id));
            const other = alternatives[0];
            answer = await ui("agent-failed", label, lastLine, other ? other.label : "");
            if (answer.cancelled) return outcome(run, { kind: "cancelled", status: answer.status, sentence: "You stopped the AUR packages at the review, so they were skipped." });
            if (other && answer.value === "Use " + other.label) {
                plan = judge.reviewPlan({ agent: other.id, command: "" }, foundAgents({}));
                continue;
            }
            if (answer.value === "Install without review") break;
            if (answer.value !== "Skip AUR packages") refuse("review=choice-invalid");
            return outcome(run, { kind: "skipped", sentence: "AUR packages skipped: the " + label + " review did not finish and you chose to skip them. Its last line: " + lastLine });
        }
        const concerns = new Map();
        for (const flag of [...(verdict?.flags || []), ...deterministic]) {
            const concern = judge.failureLines(flag.concern).join(" ");
            concerns.set(flag.name, [...(concerns.get(flag.name) || []), concern]);
        }
        let skipped = [];
        if (concerns.size) {
            const flagged = [...concerns.keys()];
            if (context.attempt > 0) return outcome(run, { kind: "stopped", sentence: "AUR packages stopped: the review flagged " + flagged.join(", ") + " again." });
            answer = await ui("flagged", flagged.join(", "), [...concerns].map(([name, risks]) => name + ": " + risks.join(" ")).join("\n"));
            if (answer.cancelled || answer.value === "Stop") return outcome(run, { kind: "stopped", status: answer.status, sentence: "You stopped the AUR packages at the review, so they were skipped." });
            if (answer.value === "Skip " + flagged.join(", ")) skipped = skipDependents(bases, flagged);
            else if (answer.value !== "Install anyway") refuse("review=choice-invalid");
        } else if (verdict !== null) {
            const shown = await ui("result", "No concerns found: " + names.join(", ") + ".");
            if (shown.cancelled) return outcome(run, { kind: "cancelled", status: shown.status, sentence: "You stopped the AUR packages at the review, so they were skipped." });
        }
        for (const base of pending) store[base.base + ":" + base.tree] = { decision: base.names.some(name => skipped.includes(name)) ? "skipped" : "accepted", names: base.names, verdict };
        writeJson(path.join(run, "verdicts.json"), store);
        if (skipped.length) {
            const shown = await ui("result", "Packages skipped after the review: " + skipped.join(", ") + ".");
            if (shown.cancelled) return outcome(run, { kind: "cancelled", status: shown.status, sentence: "You stopped the AUR packages at the review, so they were skipped." });
            return outcome(run, { kind: "skip-packages", skipped, sentence: "Flagged packages and their dependents were skipped after the review." });
        }
        return 0;
    } catch (error) {
        if (error instanceof files.Refusal) throw error;
        const cause = /^(?:The |An |Paru |VGS )/.test(error.message) ? error.message
            : "VGS could not read the AUR build files for this review.";
        return outcome(run, { kind: "unavailable", sentence: "AUR packages skipped: " + cause });
    } finally {
        fs.rmSync(pristine, { recursive: true, force: true });
        process.umask(previousUmask);
    }
}
// Only VGS-published targets may take this shortcut. The full read-only
// resolver order includes make/check dependencies before any clone is built.
function helperReviewCovered(action, names, ignored, config, binary) {
    const published = publishedPackages();
    if (published.names === null) return false;
    let targets = names;
    if (action === "upgrade") {
        const check = managers.checkFor("aur", binary).check;
        if (!check) return false;
        const command = check.argv.slice();
        if (config) command.splice(1, 0, "--config", config);
        const read = query(command);
        if (read.error || read.signal) return false;
        const result = managers.checkOutcome(check, read.status, read.stdout, read.stderr);
        if (result.error) return false;
        targets = result.packages.map(pkg => pkg.name).filter(name => !ignored.includes(name));
    }
    if (!targets.length || targets.some(name => judge.publisher(name.split("/").pop(), true, published.names) !== "vgs")) return false;
    const command = [binary, ...(config ? ["--config", config] : []), "-Po", "--", ...targets];
    const read = query(command);
    if (read.error || read.signal || read.status !== 0 || read.stderr) return false;
    const order = managers.parseBuildOrder(read.stdout);
    return order.ok && order.packages.some(pkg => pkg.origin === "AUR")
        && order.packages.filter(pkg => pkg.origin === "AUR").every(pkg => judge.publisher(pkg.name, true, published.names) === "vgs");
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
async function withReview(action, manager, names, ignored = [], installs = [], config, execute) {
    const original = { names, ignored, installs, config };
    if (manager !== "aur" || action === "remove") return execute(original);
    const found = managers.presentManager(manager, onPath);
    if (!found.ok || path.basename(found.binary) !== "paru") return execute(original);
    const effective = effectiveConfig({ config: config || null }, found.binary);
    const settings = settingsRead().settings;
    const skipReview = settings.enabled === false || helperReviewCovered(action, names.concat(installs), ignored, effective, found.binary);
    if (skipReview) return execute({ ...original, skipReview: true });
    const run = createRun();
    writeJson(path.join(run, "context.json"), { attempt: 0 });
    writeJson(path.join(run, "verdicts.json"), {});
    const reviewCommand = launcher(run, effective);
    try {
        let ended = await execute({ ...original, reviewCommand, skipReview: false });
        let result = null;
        try { result = readJson(path.join(run, "outcome.json")); } catch (error) { if (error.code !== "ENOENT") throw error; }
        if (result?.kind === "skip-packages") {
            process.stderr.write("vgshell: package-review: " + result.sentence + "\n");
            const skipped = result.skipped;
            const next = action === "upgrade" ? { ...original, ignored: [...new Set(ignored.concat(skipped))] }
                : { ...original, names: names.filter(name => !skipped.includes(name.split("/").pop())), installs: installs.filter(name => !skipped.includes(name.split("/").pop())) };
            if (action !== "upgrade" && !next.names.length && !next.installs.length) return { status: 0, outcome: { kind: "package-skipped", manager } };
            writeJson(path.join(run, "context.json"), { attempt: 1 });
            fs.unlinkSync(path.join(run, "outcome.json"));
            ended = await execute({ ...next, reviewCommand, skipReview: false });
            result = null;
            try { result = readJson(path.join(run, "outcome.json")); } catch (error) { if (error.code !== "ENOENT") throw error; }
        }
        if (result !== null) {
            process.stderr.write("vgshell: package-review: " + result.sentence + "\n");
            return cleanOutcome(manager, result.status || 1, result.sentence);
        }
        return ended;
    } finally { fs.rmSync(run, { recursive: true, force: true }); }
}
function buildRoot() {
    const cache = process.env.XDG_CACHE_HOME || path.join(home(), ".cache");
    const dir = path.join(cache, "vgshell/package-build");
    fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
    const real = fs.realpathSync(dir);
    ownedDirectory(real);
    assertCloneOutsideWriteRoots(real, agentHome());
    return real;
}
async function bootstrap(tree) {
    if (settingsRead().settings.enabled === false) return 0;
    const run = createRun();
    writeJson(path.join(run, "context.json"), { attempt: 0 });
    writeJson(path.join(run, "verdicts.json"), {});
    try {
        const config = effectiveConfig({ config: null }, "pacman");
        const status = await reviewFiles(run, tree, config, tree);
        if (status) {
            const result = readJson(path.join(run, "outcome.json"));
            process.stderr.write("vgshell: package-review: " + result.sentence + "\n");
            return result.status || status;
        }
        return status;
    } finally { fs.rmSync(run, { recursive: true, force: true }); }
}
module.exports = { available, bootstrap, buildRoot, customMode, judge, settingsRead, settingsWrite, createRun, withReview, reviewFiles,
    workRoot, ownedDirectory, privateFile, ui, orphanInfo, rebuildAllowed, unavailableCustom };
