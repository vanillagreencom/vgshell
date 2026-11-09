// Package review preparation, interactive admission and single-use authority.
// Queries and agent files are user-owned data; PackageManagers alone builds
// the later mutation argv. No caller-provided plan is executable authority.
"use strict";
const fs = require("node:fs");
const path = require("node:path");
const os = require("node:os");
const crypto = require("node:crypto");
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
const hash = value => crypto.createHash("sha256").update(value).digest("hex");
const same = (a, b) => JSON.stringify(a) === JSON.stringify(b);
const object = v => v !== null && typeof v === "object" && !Array.isArray(v);
// gather emits this fixed limit for AUR builds, whose added dependencies
// cannot be known before the build. Every other note is failed evidence.
function evidenceFailures(notes) {
    return notes.filter(note => !note.startsWith("dependencies=unresolved name="));
}
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
    const answer = cp.spawnSync(argv[0], argv.slice(1), { cwd: home(), encoding: "utf8", timeout: 120000, maxBuffer: 16 * MAX_DATA,
        stdio: ["ignore", "pipe", "pipe"], env: { ...process.env, LC_ALL: "C", ...env } });
    return answer;
}
function output(argv, env) {
    const r = query(argv, env);
    if (r.error || r.status !== 0) throw new Error("query=" + path.basename(argv[0]) + " cause=" + (r.error?.code || r.status || r.signal));
    return r.stdout;
}
function identity(file) {
    const stat = fs.lstatSync(file);
    if (!stat.isFile() || stat.size > 16 * MAX_DATA) throw new Error("identity=not-regular");
    return { path: file, real: fs.realpathSync(file), dev: stat.dev, ino: stat.ino, hash: hash(fs.readFileSync(file)) };
}
function configIdentity(config) {
    const seen = new Set(), identities = [];
    function read(file) {
        file = path.resolve(home(), file);
        if (seen.has(file)) throw new Error("config=include-cycle");
        seen.add(file);
        if (identities.length >= 128) throw new Error("config=include-bound");
        // Configuration includes may be symlinks. Bind the requested path
        // and its resolved regular file so retargeting invalidates review.
        identities.push({ requested: file, ...identity(fs.realpathSync(file)) });
        for (const line of fs.readFileSync(file, "utf8").split(/\r?\n/)) {
            const m = /^\s*Include\s*=\s*(.*?)\s*(?:#.*)?$/.exec(line);
            if (m) {
                // pacman.conf permits globs. Expand using the system glob owner,
                // and bind the exact resolved list as well as each file's bytes.
                // Node's declared floor is 18. Python is already a core
                // runtime dependency and owns glob expansion on that floor.
                const expanded = output(["python3", "-c", "import glob,json,sys;print(json.dumps(sorted(glob.glob(sys.argv[1]))))", m[1]]);
                const matches = JSON.parse(expanded).map(p => path.resolve(home(), p));
                if (matches.length === 0) throw new Error("config=include-missing");
                identities.push({ include: m[1], matches });
                for (const match of matches) read(match);
            }
        }
        seen.delete(file);
    }
    read(config);
    return identities;
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
function requestError(request) {
    const allowed = ["version","mode","action","groups","sources","rebuild","config","customAurArgv"];
    if (object(request) && Object.keys(request).some(k => !allowed.includes(k))) return "unknown-field";
    if (!object(request) || request.version !== 1 || !["named", "upgrade", "bootstrap"].includes(request.mode) || !["install", "reinstall", "update", "upgrade"].includes(request.action)
        || !Array.isArray(request.groups) || !Array.isArray(request.sources) || !Array.isArray(request.rebuild) || (request.config !== null && (typeof request.config !== "string" || !path.isAbsolute(request.config)))
        || (request.customAurArgv !== null && (!Array.isArray(request.customAurArgv) || request.customAurArgv.length === 0 || request.customAurArgv.some(v => typeof v !== "string" || /[\x00-\x1f\x7f]/.test(v))))) return "shape";
    for (const group of request.groups) {
        if (object(group) && Object.keys(group).some(k => !["manager","names","installs","ignored","config"].includes(k))) return "group-field";
        if (!object(group) || (group.config !== undefined && (typeof group.config !== "string" || !path.isAbsolute(group.config))) || !["pacman", "aur"].includes(group.manager) || ["names", "installs", "ignored"].some(k => !Array.isArray(group[k]) || group[k].some(n => !managers.validName(n)))) return "group";
        if (request.mode === "upgrade" && (group.names.length || group.installs.length)) return "upgrade-targets";
    }
    if (request.rebuild.some(n => !managers.validName(n)) || request.sources.some(s => !["pacman", "aur"].includes(s))) return "source";
    if ((request.mode === "upgrade") !== (request.action === "upgrade")) return "mode-action";
    if (request.mode === "named" && (request.groups.length === 0 || request.sources.length || request.rebuild.length || request.customAurArgv !== null || request.groups.some(g => g.names.length + g.installs.length === 0))) return "named";
    if (request.mode === "upgrade" && (new Set(request.sources).size !== request.sources.length || new Set(request.groups.map(g => g.manager)).size !== request.groups.length || !same(request.sources.slice().sort(), request.groups.map(g => g.manager).sort()))) return "sources";
    if (request.mode === "bootstrap" && (request.action !== "install" || request.groups.length !== 1 || request.groups[0].manager !== "pacman" || !same(request.groups[0].names, ["paru"]) || request.groups[0].installs.length || request.groups[0].ignored.length || request.sources.length || request.rebuild.length || request.customAurArgv !== null)) return "bootstrap";
    return null;
}
function effectiveConfig(request, binary) {
    if (request.config !== null) return request.config;
    // Reuse the package owner's effective helper-config adapter.
    const r = query([process.execPath, path.join(__dirname, "pkg-config.js"), binary]);
    if (r.error || r.status !== 0) throw new Error("config=helper-unreadable");
    return JSON.parse(r.stdout).config;
}
function pending(group, config, binary) {
    const found = managers.reviewCheckFor(group.manager, binary, config, file => ({
        repositories: output(["pacman-conf", "--config", file, "--repo-list"]).trim().split(/\s+/).filter(Boolean),
        dbPath: output(["pacman-conf", "--config", file, "DBPath"]).trim()
    }));
    if (!found.check) throw new Error("pending=query-unavailable");
    const check = found.check;
    const r = query(check.argv);
    if (r.error) throw new Error("pending=" + r.error.code);
    const result = managers.checkOutcome(check, r.status, r.stdout, r.stderr);
    if (result.error) throw new Error("pending=" + result.error);
    return { complete: found.complete, origin: found.origin, packages: result.packages.filter(p => !group.ignored.includes(p.name)) };
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
// Paru's pending -Si metadata, not the installed publisher recipes, holds
// these fields: github.com/Morganamilo/paru/blob/v2.1.0/src/info.rs.
function aurDependencies(text, name) {
    const fields = aurDependencyFields(text, name);
    return ["Depends On", "Make Deps", "Check Deps"].flatMap(field => fields.get(field));
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
function missingDependencies(entries, config) {
    if (!entries.length) return [];
    entries.forEach(dependencyName);
    const r = query(["pacman", "--config", config, "-T", "--", ...entries]);
    const missing = (r.stdout || "").trim().split(/\r?\n/).filter(Boolean);
    if (r.error || r.signal || ![0, 127].includes(r.status) || r.stderr || (r.status === 0) !== (missing.length === 0)
        || missing.some(entry => !entries.includes(entry))) throw new Error("dependency=installed-query");
    return [...new Set(missing)];
}
function resolveDependency(entry, config, binary) {
    const name = dependencyName(entry);
    // sync.c passes the full target to alpm_find_dbs_satisfier before the
    // -dd transaction checks: gitlab.archlinux.org/pacman/pacman, v7.1.0.
    const r = query(["pacman", "--config", config, "-Sddp", "--print-format", "%r %n", "--", entry]);
    if (!r.error && !r.signal && r.status === 0 && !r.stderr) {
        const row = /^(\S+) ([A-Za-z0-9@_+.-]+)\n?$/.exec(r.stdout);
        if (!row || !managers.validName(row[2])) throw new Error("dependency=satisfier-malformed entry=" + entry);
        return { target: row[2], origin: row[1], viaAur: false };
    }
    if (r.error || r.signal || r.status !== 1 || r.stdout || r.stderr !== "error: target not found: " + entry + "\n")
        throw new Error("dependency=satisfier-failed entry=" + entry);
    // -Si is a literal metadata lookup. -Po invokes the helper resolver;
    // no -d, which would disable versions (paru v2.1.0 src/resolver.rs).
    const order = output([binary, "--config", config, "-Po", "--", entry]);
    const parsed = managers.parseBuildOrder(order);
    const targets = parsed.ok ? parsed.packages.filter(p => p.origin === "AUR" && p.kind === "TARGET") : [];
    const target = targets.length === 1 ? targets[0] : null;
    // order.rs has no install provider-choice callback. A differently named
    // provider cannot establish the later interactive install's selection.
    if (!target || target.name !== name) throw new Error("dependency=helper-unresolved entry=" + entry);
    return { target: target.name, origin: "aur", viaAur: true };
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
function gather(request) {
    const state = { steps: [], packages: [], unknown: [], lines: [], recipes: [], dependents: Object.create(null) };
    const recipes = publishedPackages();
    let repositoryData = null;
    function repositories(config) {
        if (repositoryData?.config === config) return repositoryData;
        const order = output(["pacman-conf", "--config", config, "--repo-list"]).trim().split(/\s+/).filter(Boolean);
        if (!order.length) throw new Error("origin=empty-repositories");
        const rows = output(["pacman", "--config", config, "-Sl"]).trim().split(/\r?\n/).filter(Boolean).map(line => {
            const m = /^(\S+) (\S+) (\S+)(?: \[.*\])?$/.exec(line);
            if (!m || !order.includes(m[1])) throw new Error("origin=malformed-index");
            return { repository: m[1], name: m[2], version: m[3] };
        }).sort((a, b) => order.indexOf(a.repository) - order.indexOf(b.repository));
        repositoryData = { config, order, rows };
        return repositoryData;
    }
    const groups = request.groups.concat(request.rebuild.length ? [{ manager: "aur", names: request.rebuild, installs: [], ignored: [], action: "reinstall" }] : []);
    for (const group of groups) {
        const action = group.action || request.action;
        const found = managers.presentManager(group.manager, onPath);
        const step = { manager: group.manager, action, names: group.names, installs: group.installs, inputIgnored: group.ignored, ignored: group.ignored.slice(), config: request.config,
            binary: found.ok ? commandFile(found.binary) : null, binding: null };
        state.steps.push(step);
        try {
            if (!found.ok) throw new Error("manager=absent");
            const config = effectiveConfig({ ...request, config: group.config === undefined ? request.config : group.config }, found.binary);
            step.config = config;
            const binding = { binary: identity(fs.realpathSync(step.binary)), config: [], pending: [], origins: [] };
            try { binding.config = configIdentity(config); }
            catch (e) { if (request.mode !== "bootstrap") throw e; state.unknown.push(e.message); }
            let targets;
            if (request.mode === "upgrade" && action === "upgrade") {
                const p = pending(group, config, found.binary);
                binding.pending = p.packages;
                if (!p.complete && group.manager === "aur") state.unknown.push("pending=config-correspondence");
                targets = p.packages.map(item => ({ target: item.name, old: item.old, next: item.new, origin: p.origin }));
            } else targets = [...group.names, ...group.installs].map(n => ({ target: n, old: null, next: null }));
            step.binding = binding;
            const repos = request.mode === "bootstrap" ? { rows: [], order: [] } : repositories(config);
            const expanded = new Set(), metadata = new Map();
            const infoFor = name => {
                if (!metadata.has(name)) metadata.set(name, output([found.binary, "--config", config, "-Si", "--", name]));
                return metadata.get(name);
            };
            for (const target of targets) {
                const qualified = /^([^/]+)\/([^/]+)$/.exec(target.target);
                const [qualifier, name] = qualified === null ? [null, target.target] : [qualified[1], qualified[2]];
                const matches = target.neededBy === undefined ? repos.rows.filter(row => row.name === name && (qualifier === null || qualifier === row.repository)) : [];
                // viaAur is set only where the owner itself resolved the AUR:
                // a pacman repository may be named `aur`.
                let origin, viaAur = false;
                if (target.neededBy !== undefined) { origin = target.origin; viaAur = target.viaAur; }
                else if (request.mode === "bootstrap") { origin = "aur"; viaAur = true; }
                else if (target.origin === "aur" && matches.length > 0) { state.unknown.push("origin=aur-repository-collision name=" + name); origin = "unknown"; }
                // pacman v7.1.0 lib/libalpm/sync.c::alpm_sync_get_new_version
                // takes the first sync database containing the package:
                // https://gitlab.archlinux.org/pacman/pacman/-/blob/v7.1.0/lib/libalpm/sync.c#L64-67
                else if (matches.length) origin = matches[0].repository;
                else if (group.manager === "aur" || request.mode === "bootstrap") {
                    const info = infoFor(name);
                    const identity = /^Name\s*:\s*(\S+)\s*$/m.exec(info);
                    if (!/^Repository\s*:\s*aur\s*$/m.test(info) || identity === null || identity[1] !== name) throw new Error("origin=unresolved name=" + name);
                    origin = "aur"; viaAur = true;
                } else origin = "unknown";
                binding.origins.push({ target: target.target, origin, candidates: matches.map(row => ({ repository: row.repository, version: row.version })),
                    ...(target.neededBy === undefined ? {} : { entry: target.entry, neededBy: target.neededBy, aur: viaAur }) });
                if (!viaAur) continue;
                if (target.neededBy !== undefined) {
                    if (!Object.hasOwn(state.dependents, name)) state.dependents[name] = [];
                    if (!state.dependents[name].includes(target.neededBy)) state.dependents[name].push(target.neededBy);
                }
                const publisher = judge.publisher(name, viaAur, recipes.names);
                if (publisher === "unread") {
                    const cause = "vgs-packages=unreadable cause=" + recipes.cause;
                    if (!state.unknown.includes(cause)) state.unknown.push(cause);
                }
                if (viaAur && publisher !== "vgs") state.unknown.push("dependencies=unresolved name=" + name);
                // A package VGS publishes is not third-party code: no review
                // lists, fetches or judges it. It stays a package so a held
                // retry binds the recipe its build would fetch. Its listed
                // dependencies are expanded and judged as their own targets.
                const pkg = { name, origin, aur: viaAur, published: publisher === "vgs", old: target.old, next: target.next, manager: group.manager, binary: found.binary, config };
                if (!state.packages.some(p => p.name === name && p.origin === origin && p.aur === viaAur)) state.packages.push(pkg);
                if (pkg.published) {
                    if (!expanded.has(name)) {
                        expanded.add(name);
                        for (const entry of missingDependencies(aurDependencies(infoFor(name), name), config))
                            targets.push({ ...resolveDependency(entry, config, found.binary), entry, neededBy: name, old: null, next: null });
                    }
                    continue;
                }
                state.lines.push(`aur ${name} ${target.old || "?"} ${target.next || "?"}`);
            }
        } catch (e) { step.binding = null; if (group.manager === "aur" || request.mode === "bootstrap") state.unknown.push(e.message); }
    }
    if (request.customAurArgv !== null) {
        try {
            state.customConfig = request.config === null ? null : configIdentity(request.config);
            state.customBinding = identity(fs.realpathSync(commandFile(request.customAurArgv[0]) || request.customAurArgv[0]));
            if (customMode(request.customAurArgv) === "unknown") state.unknown.push("custom-command=unknown");
        } catch (_) { state.customBinding = null; state.unknown.push("custom-command=unreadable"); }
    }
    return state;
}
// Untrusted fetched .SRCINFO sections retain split-package override rules;
// neither PKGBUILD nor install script is ever executed during review.
// The fetched build folder whose .SRCINFO builds PKG's name: { folder, base,
// script, src }, base the folder's pkgbase, or null.
function recipeFolder(dir, pkg) {
    const build = path.join(dir, "build");
    for (const entry of fs.readdirSync(build, { withFileTypes: true })) {
        if (!entry.isDirectory()) continue;
        const folder = path.join(build, entry.name);
        const src = path.join(folder, ".SRCINFO");
        if (!fs.existsSync(src) || !fs.lstatSync(src).isFile()) continue;
        let section = "", base = "", own = "", ownSet = false, found = false, pkgbase = "";
        for (const { key, value } of judge.srcinfoFields(fs.readFileSync(src, "utf8"))) {
            if (key === "pkgbase") { section = "base"; pkgbase = value; }
            if (key === "pkgname") { section = value === pkg.name ? "own" : "other"; if (section === "own") found = true; }
            if (key === "install" && section === "base") base = value;
            if (key === "install" && section === "own") { own = value; ownSet = true; }
        }
        if (found) return { folder, base: pkgbase, script: ownSet ? own : base, src };
    }
    return null;
}
function installEvidence(dir, pkg, state) {
    const selected = recipeFolder(dir, pkg);
    if (selected === null) throw new Error("install=srcinfo-unreadable name=" + pkg.name);
    const script = selected.script;
    if (script && (script.includes("/") || script === "." || script === "..")) throw new Error("install=unsafe-script");
    const next = script ? fs.readFileSync(identity(path.join(selected.folder, script)).path, "utf8") : null;
    const db = output(["pacman-conf", "--config", pkg.config, "DBPath"]).trim();
    if (!path.isAbsolute(db)) throw new Error("install=dbpath-unreadable");
    let old = pkg.old;
    if (!old) {
        const r = query(["pacman", "--config", pkg.config, "-Q", "--", pkg.name]);
        if (r.status === 0) old = r.stdout.trim().split(/\s+/)[1];
        else if (r.status !== 1 || r.error) throw new Error("install=installed-query-unreadable");
    }
    let installed = null;
    if (old && db) {
        const file = path.join(db, "local", pkg.name + "-" + old, "install");
        try { identity(file); installed = fs.readFileSync(file, "utf8"); } catch (e) { if (e.code !== "ENOENT") throw e; }
    }
    const change = judge.installScriptChange(installed, next);
    state.lines.push(`install ${pkg.name} ${change.state}`);
    if (change.state === "changed") {
        const oldFile = path.join(dir, "install", pkg.name + ".old"), diff = path.join(dir, "install", pkg.name + ".diff");
        fs.writeFileSync(oldFile, installed, { mode: 0o600 });
        const r = query(["diff", "-u", "--", oldFile, path.join(selected.folder, script)]);
        if (r.error || ![0, 1].includes(r.status)) throw new Error("install=diff-unreadable");
        fs.writeFileSync(diff, r.stdout, { mode: 0o600 });
    }
    return change.risks.map(concern => ({ name: pkg.name, concern }));
}
// The helper's copy of a base's recipe from its last build here, which
// `-G` leaves alone. paru v2.1.0 clones into dirs::cache_dir()/paru/clone
// (src/config.rs:578-589); yay v12.5.0 into $XDG_CACHE_HOME/yay, else
// $HOME/.cache/yay (pkg/settings/dirs.go:36-46, config.go:247-252).
// dirs::cache_dir() is an absolute $XDG_CACHE_HOME, else $HOME/.cache. A
// configured CloneDir, buildDir or AURDEST is not read: its copy reads as
// new. Any other helper keeps no copy VGS knows.
function cachedRecipe(binary, base) {
    const xdg = process.env.XDG_CACHE_HOME;
    const cache = xdg && path.isAbsolute(xdg) ? xdg : path.join(home(), ".cache");
    const helper = path.basename(binary);
    if (helper === "paru") return path.join(cache, "paru/clone", base);
    if (helper === "yay") return path.join(cache, "yay", base);
    return null;
}
// One `recipe <pkgbase> new|unchanged|changed` line per fetched base, from
// the whole fetched folder against the helper's cached copy. Local source
// files can carry a payload without changing the PKGBUILD. Snapshot every
// regular file except helper metadata before diffing; never execute it.
function recipeContents(dir, kind, base) {
    try {
        const entries = recipeFiles(dir, file => {
            const fd = fs.openSync(file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
            try {
                const stat = fs.fstatSync(fd);
                if (!stat.isFile()) throw Object.assign(new Error("not a regular recipe file"), { code: "RECIPE_UNSAFE" });
                const name = path.relative(dir, file);
                if (stat.size > (kind === "cache" && name === "PKGBUILD" ? MAX_DATA : 16 * MAX_DATA))
                    throw Object.assign(new Error("recipe file exceeds the read limit"), { code: "RECIPE_TOO_LARGE" });
                return [name, fs.readFileSync(fd)];
            } finally { fs.closeSync(fd); }
        });
        const contents = new Map(entries);
        if (!contents.has("PKGBUILD")) throw new Error("the recipe folder has no PKGBUILD");
        return contents;
    } catch (e) {
        const cause = ["ELOOP", "RECIPE_UNSAFE"].includes(e.code) ? "unsafe" : e.code === "RECIPE_TOO_LARGE" ? "too-large" : "unreadable";
        throw new Error(`recipe=${kind}-${cause} name=${base}`);
    }
}
function recipeEvidence(dir, pkg, state, compared) {
    const selected = recipeFolder(dir, pkg);
    if (selected === null || !selected.base) throw new Error("recipe=srcinfo-unreadable name=" + pkg.name);
    const base = selected.base;
    if (base.includes("/") || base === "." || base === "..") throw new Error("recipe=unsafe-base name=" + pkg.name);
    if (compared.has(base)) return;
    compared.add(base);
    const cached = cachedRecipe(pkg.binary, base);
    let old = null;
    if (cached !== null) {
        let exists = true;
        try { fs.lstatSync(cached); }
        catch (e) {
            if (e.code !== "ENOENT") throw new Error("recipe=cache-unreadable name=" + base);
            exists = false;
        }
        if (exists) old = recipeContents(cached, "cache", base);
    }
    const next = recipeContents(selected.folder, "build", base);
    const names = [...new Set([...(old?.keys() || []), ...next.keys()])].sort();
    const changed = old === null ? [] : names.filter(name => !old.has(name) || !next.has(name) || !old.get(name).equals(next.get(name)));
    const recipeState = old === null ? "new" : changed.length ? "changed" : "unchanged";
    if (recipeState !== "changed") { state.lines.push(`recipe ${base} ${recipeState}`); return; }
    const out = path.join(dir, "recipe");
    fs.mkdirSync(out, { recursive: true, mode: 0o700 });
    const before = path.join(out, base + ".old"), after = path.join(out, base + ".new");
    let diff = "";
    try {
        for (const name of changed) {
            if (old.has(name)) fs.writeFileSync(before, old.get(name), { mode: 0o600 });
            if (next.has(name)) fs.writeFileSync(after, next.get(name), { mode: 0o600 });
            const r = query(["diff", "-u", "--label", path.join("cached", base, name), "--label", path.join("build", base, name), "--",
                old.has(name) ? before : "/dev/null", next.has(name) ? after : "/dev/null"]);
            if (r.error || ![0, 1].includes(r.status)) throw new Error("recipe=diff-unreadable name=" + base);
            // diff sees no bytes in an added or removed empty file, but the
            // folder changed and its evidence must still name that file.
            if (r.status === 0) diff += `Empty file ${old.has(name) ? "removed" : "added"}: ${path.join(old.has(name) ? "cached" : "build", base, name)}\n`;
            else diff += r.stdout;
        }
        fs.writeFileSync(path.join(out, base + ".diff"), diff, { mode: 0o600 });
        state.lines.push(`recipe ${base} ${recipeState}`);
    } finally { fs.rmSync(before, { force: true }); fs.rmSync(after, { force: true }); }
}
function recipeFiles(dir, readFile) {
    const entries = [];
    let bytes = 0;
    function read(at) {
        if (!fs.lstatSync(at).isDirectory()) throw Object.assign(new Error("The AUR recipe folder is not a directory."), { code: "RECIPE_UNSAFE" });
        for (const row of fs.readdirSync(at, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
            if (row.name === ".git") continue;
            const file = path.join(at, row.name);
            if (row.isDirectory()) read(file);
            else if (row.isFile()) {
                bytes += fs.statSync(file).size;
                if (entries.length >= 4096 || bytes > 64 * MAX_DATA) throw Object.assign(new Error("The AUR build recipes exceed the review's file or size limit."), { code: "RECIPE_TOO_LARGE" });
                entries.push(readFile(file));
            }
            else throw Object.assign(new Error("The AUR recipe file " + JSON.stringify(path.relative(dir, file)) + " is "
                + (row.isSymbolicLink() ? "a symbolic link" : "not a regular file") + ", so it cannot be reviewed safely."), { code: "RECIPE_UNSAFE" });
        }
    }
    read(dir);
    return entries;
}
function recipesIdentity(dir) {
    return recipeFiles(dir, identity);
}
function agentHome() {
    if (!process.env.XDG_RUNTIME_DIR) refuse("review=runtime-dir-unset");
    let dir = process.env.XDG_RUNTIME_DIR;
    // The presenter may own a 0755 shared namespace. Forbid non-owner
    // writes there; every review/transaction descendant stays private.
    for (const [segment, forbiddenMode] of [["vgshell", 0o022], ["package-review", 0o077]]) {
        dir = path.join(dir, segment);
        try { fs.mkdirSync(dir, { mode: 0o700 }); } catch (e) { if (e.code !== "EEXIST") throw e; }
        ownedDirectory(dir, forbiddenMode);
    }
    return dir;
}
// Updates owns the returned transaction lifetime; its outer EXIT removes it.
function createTransaction() {
    const dir = fs.mkdtempSync(path.join(agentHome(), "transaction-"));
    fs.chmodSync(dir, 0o700);
    return dir;
}
async function review(request, storage) {
    const previous = process.umask(0o077);
    try { return await reviewRequest(request, storage); }
    finally { process.umask(previous); }
}
async function reviewRequest(request, storage) {
    function failedRead(note) {
        if (note.startsWith("The ")) return note;
        const name = /(?:^| )name=(\S+)/.exec(note)?.[1];
        const subject = name ? " for " + name : "";
        const kind = note.split(" ")[0];
        if (kind === "origin=aur-repository-collision") return name + " appears in both the AUR update and a package repository.";
        if (kind.startsWith("query=")) return "The " + kind.slice(6) + " package query failed.";
        if (kind.startsWith("agent=")) return "No review agent is available. Choose an installed agent or customize the review command.";
        if (kind.startsWith("fetch=")) return "The AUR build files could not be downloaded" + subject + ".";
        if (kind.startsWith("origin=")) return "The AUR package source could not be confirmed" + subject + ".";
        if (kind.startsWith("install=") || kind.startsWith("identity=")) return "An AUR install script could not be read safely" + subject + ".";
        if (kind.startsWith("recipe=")) return "The AUR build recipe could not be compared with the copy from its last build" + subject + ".";
        if (kind.startsWith("vgs-packages=")) return "VGS's own package names could not be read.";
        if (kind.startsWith("pending=")) return "The pending AUR update list could not be confirmed for this package configuration.";
        if (kind.startsWith("dependency=")) return "An AUR package's required dependency could not be resolved.";
        if (kind.startsWith("custom-command=")) return "The custom AUR command cannot be matched to the reviewed package plan.";
        if (kind.startsWith("config=")) return "The AUR helper's package configuration could not be read safely.";
        if (kind === "review=nothing-reviewable") return "No AUR build recipe is available to review.";
        return "Some AUR build information could not be read safely.";
    }
    const error = requestError(request);
    if (error) refuse("review=request error=" + error);
    if (process.env.VGS_TUI_SUDO_SESSION && fs.existsSync("/proc/" + process.env.VGS_TUI_SUDO_SESSION)) refuse("review=outer-credential-session");
    const state = gather(request);
    let settings = settingsRead().settings;
    const result = { version: 1, decision: "proceed", reviewed: [], skipped: [], coverage: "complete", receipt: null };
    const thirdParty = state.packages.filter(p => !p.published), published = state.packages.filter(p => p.published).map(p => p.name);
    if (thirdParty.length || state.unknown.length) {
        const known = thirdParty.map(p => p.name);
        const unresolved = state.steps.filter(step => step.manager === "aur" && step.binding === null).flatMap(step => step.names.concat(step.installs));
        const packageList = "AUR packages: " + ([...new Set(known.concat(unresolved))].join(", ") || "package list unavailable")
            + (published.length ? "\n\nSkipped: " + published.join(", ") + ", VGS's own " + (published.length === 1 ? "package." : "packages.") : "");
        // With no package to review, Review asks no agent: the
        // unavailable-evidence question follows at once.
        const reviewable = thirdParty.length > 0;
        let choice = null;
        const gatheredUnknown = state.unknown.slice(), gatheredLines = state.lines.slice();
        let evidenceCreated = false;
        if (!judge.initialChoice(settings, foundAgents(settings)).ask) {
            const shown = await ui("saved-decline", packageList);
            if (shown.cancelled) return { ...result, decision: "cancelled", coverage: "unknown", status: shown.status };
            choice = { value: "Install without review" };
        }
        reviewChoice: for (;;) {
            if (choice === null) {
                const found = foundAgents(settings), initial = judge.initialChoice(settings, found);
                choice = await ui("offer", initial.action === "review" ? "Review" : "Install without review", packageList);
            }
            if (choice.cancelled) return { ...result, decision: "cancelled", coverage: "unknown", status: choice.status };
            if (choice.value === "Review" && reviewable) {
                for (;;) {
                    const plan = judge.reviewPlan(settings, foundAgents(settings));
                    if (!["agent", "command"].includes(plan.state)) break;
                    const agentChoice = await ui("agent", plan.label);
                    if (agentChoice.cancelled) return { ...result, decision: "cancelled", coverage: "unknown", status: agentChoice.status };
                    if (agentChoice.value === "Back") { choice = null; break; }
                    if (agentChoice.value === "Use " + plan.label) break;
                    if (agentChoice.value !== "Customize") refuse("review=choice-invalid");
                    const edit = await interactive([commandFile("bash"), path.join(__dirname, "pkg-review.sh"), "customize", path.join(repo, "bin/vgshell-pkg")]);
                    if (edit.signal) return { ...result, decision: "cancelled", coverage: "unknown", status: 128 + os.constants.signals[edit.signal] };
                    if (edit.error || (edit.status !== 0 && edit.status !== 130)) refuse("review=editor-unavailable");
                    settings = settingsRead().settings;
                }
            }
            if (choice === null) continue;
            if (choice.value === "Install without review") result.coverage = "declined";
            else if (choice.value === "Review") {
                state.unknown = gatheredUnknown.slice();
                state.lines = gatheredLines.slice();
                state.recipes = [];
                result.coverage = "complete";
                result.reviewed = [];
                result.skipped = [];
                const plan = judge.reviewPlan(settings, foundAgents(settings));
                let verdict = null, risks = [];
                const dir = path.join(storage, "evidence");
                // This request owns storage and the preceding attempt's evidence.
                if (evidenceCreated) fs.rmSync(dir, { recursive: true });
                fs.mkdirSync(dir, { mode: 0o700 }); fs.mkdirSync(path.join(dir, "build"), { mode: 0o700 }); fs.mkdirSync(path.join(dir, "install"), { mode: 0o700 });
                evidenceCreated = true;
                try {
                    if (!reviewable) throw new Error("review=nothing-reviewable");
                    if (!["agent", "command"].includes(plan.state)) throw new Error("agent=" + plan.state);
                    const comparedRecipes = new Set();
                    for (const pkg of thirdParty.filter(p => p.aur)) {
                        const fetch = request.mode === "bootstrap" ? ["git", "clone", "--", "https://aur.archlinux.org/paru.git", "paru"] : [pkg.binary, "--config", pkg.config, "-G", "--", pkg.name];
                        const shownFetch = await ui("show", "Fetching package build files as your user", ...fetch);
                        if (shownFetch.cancelled) return { ...result, decision: "cancelled", coverage: "unknown", status: shownFetch.status };
                        const r = await interactive(fetch, { cwd: path.join(dir, "build") });
                        if (r.signal) return { ...result, decision: "cancelled", coverage: "unknown", status: 128 + os.constants.signals[r.signal] };
                        if (r.error || r.status !== 0) throw new Error("fetch=failed name=" + pkg.name);
                        try { risks.push(...installEvidence(dir, pkg, state)); }
                        catch (e) { state.unknown.push(e.message); risks.push({ name: pkg.name, concern: "The install script could not be verified." }); }
                        try { recipeEvidence(dir, pkg, state, comparedRecipes); }
                        catch (e) { state.unknown.push(e.message); }
                    }
                    state.recipes = recipesIdentity(path.join(dir, "build"));
                    fs.writeFileSync(path.join(dir, "packages.txt"), state.lines.concat(state.unknown.map(e => "unknown " + e)).join("\n") + "\n", { mode: 0o600 });
                    const prompt = fs.readFileSync(path.join(__dirname, "review/third-party.md"), "utf8").replaceAll("{review_dir}", dir);
                    const shownAgent = await ui("show", "Reviewing the listed packages before installation", ...plan.command);
                    if (shownAgent.cancelled) return { ...result, decision: "cancelled", coverage: "unknown", status: shownAgent.status };
                    const run = await interactive(plan.command.concat(prompt), { cwd: agentHome() });
                    if (run.signal) return { ...result, decision: "cancelled", coverage: "unknown", status: 128 + os.constants.signals[run.signal] };
                    if (run.error || run.status !== 0) throw new Error("The review agent failed before it completed the review.");
                    let text;
                    try { text = privateFile(path.join(dir, "verdict")); }
                    catch (e) {
                        const cause = e.code === "ENOENT" ? "missing" : e instanceof files.Refusal || e.code === "ELOOP" ? "unsafe" : "unreadable";
                        throw new Error("The agent's verdict is " + cause + ".");
                    }
                    verdict = judge.parseVerdict(text, known);
                    if (!verdict.ok) throw new Error("The agent's verdict is malformed.");
                    result.reviewed = known;
                } catch (e) { state.unknown.push(e.message); }
                const failures = evidenceFailures(state.unknown);
                const concerns = new Map();
                for (const flag of [...(verdict?.ok ? verdict.flags : []), ...risks]) concerns.set(flag.name, [...(concerns.get(flag.name) || []), flag.concern]);
                const clean = verdict?.ok ? known.filter(name => !concerns.has(name)) : [];
                const summary = [clean.length ? "No concerns found: " + clean.join(", ") + "." : "",
                    concerns.size ? "Needs your decision: " + [...concerns.keys()].join(", ") + "." : "",
                    failures.length ? "Could not finish: " + [...new Set(failures.map(failedRead))].join(" ") : ""].filter(Boolean).join("\n");
                if (verdict?.ok && !failures.length) {
                    const shown = await ui("result", summary);
                    if (shown.cancelled) return { ...result, decision: "cancelled", status: shown.status };
                }
                if (verdict?.ok && failures.length < state.unknown.length) {
                    const shown = await ui("limit");
                    if (shown.cancelled) return { ...result, decision: "cancelled", status: shown.status };
                }
                if (verdict === null || !verdict.ok || failures.length) {
                    result.coverage = "unknown";
                    const answer = await ui("unavailable", summary, "retry");
                    if (answer.cancelled) return { ...result, decision: "cancelled", status: answer.status };
                    if (answer.value === "No") {
                        if (!reviewable || !["agent", "command"].includes(plan.state)) choice = null;
                        continue reviewChoice;
                    }
                    if (answer.value === "Stop") return { ...result, decision: "stop" };
                    if (answer.value !== "Yes") refuse("review=choice-invalid");
                }
                for (const [name, concernsForName] of concerns) {
                    const answer = await ui("concern", concernsForName.join("\n"), name);
                    if (answer.cancelled) return { ...result, decision: "cancelled", status: answer.status };
                    if (answer.value === "Skip") result.skipped.push(name);
                    else if (answer.value !== "Install anyway") refuse("review=choice-invalid");
                }
                for (let i = 0; i < result.skipped.length; i++)
                    for (const dependent of Object.hasOwn(state.dependents, result.skipped[i]) ? state.dependents[result.skipped[i]] : [])
                        if (!result.skipped.includes(dependent)) result.skipped.push(dependent);
            } else refuse("review=choice-invalid");
            break;
        }
    }
    if (request.customAurArgv !== null && customMode(request.customAurArgv) === "unknown") {
        if (result.skipped.length) return { ...result, decision: "stop", coverage: "unknown" };
        if (result.coverage === "declined") {
            const answer = await ui("unavailable", failedRead("custom-command=unknown"));
            if (answer.cancelled) return { ...result, decision: "cancelled", coverage: "unknown", status: answer.status };
            if (answer.value === "No") return { ...result, decision: "stop", coverage: "unknown" };
            if (answer.value !== "Yes") refuse("review=choice-invalid");
        }
        result.coverage = "unknown";
    }
    for (const step of state.steps) {
        if (step.action === "upgrade") step.ignored = [...new Set(step.ignored.concat(result.skipped))];
        else {
            step.names = step.names.filter(n => !result.skipped.includes(n.split("/").pop()));
            step.installs = step.installs.filter(n => !result.skipped.includes(n.split("/").pop()));
        }
    }
    return { ...result, state };
}
function processIdentity(pid) {
    const text = fs.readFileSync("/proc/" + pid + "/stat", "utf8");
    return { pid, start: text.slice(text.lastIndexOf(")") + 2).split(" ")[19] };
}
function transaction(dir) {
    return { dir, identity: ownedDirectory(dir) };
}
// paru(8) -Po reports the full build order, including AUR dependencies.
// The emitted REPO/AUR rows are defined by paru v2.1.0 src/order.rs:
// https://github.com/Morganamilo/paru/blob/v2.1.0/src/order.rs
// Skip its review only when every AUR recipe belongs to the VGS decision.
// Unknown output or a new dependency keeps the helper's own review.
function helperReviewCovered(step, state) {
    if (step.manager !== "aur" || path.basename(step.binary) !== "paru") return false;
    const targets = step.action === "upgrade" ? step.binding.pending.map(p => p.name).filter(n => !step.ignored.includes(n)) : step.names.concat(step.installs);
    if (!targets.length) return false;
    const command = [step.binary, "--config", step.config, "-Po", "--", ...targets];
    const order = query(command);
    const unavailable = cause => {
        process.stderr.write("package-review: " + JSON.stringify({ review: "helper-order-unavailable", operation: "paru-build-order", cause,
            command, status: order.status, signal: order.signal, error: order.error?.code || null, stderr: order.stderr }) + "\n");
        return false;
    };
    if (order.error) return unavailable("query-error");
    if (order.signal) return unavailable("signal");
    if (order.status !== 0) return unavailable("exit-status");
    if (order.stderr) return unavailable("stderr");
    // An update can replace this reader between consumers of one receipt.
    // Its final steps and bound origins already hold the permitted set.
    const permitted = new Set();
    for (const decision of state.steps) {
        const names = decision.action === "upgrade"
            ? decision.binding === null ? [] : decision.binding.pending.map(p => p.name).filter(name => !decision.ignored.includes(name))
            : decision.names.concat(decision.installs).map(name => name.split("/").pop());
        for (const name of names) permitted.add(name);
    }
    const origins = state.steps.flatMap(decision => decision.binding === null ? [] : decision.binding.origins);
    for (const name of permitted)
        for (const origin of origins)
            if (origin.neededBy === name) permitted.add(origin.target.split("/").pop());
    const covered = new Set(state.packages.filter(p => p.aur && permitted.has(p.name)).map(p => p.name));
    const parsed = managers.parseBuildOrder(order.stdout);
    if (!parsed.ok) return unavailable("unknown-output");
    const aur = parsed.packages.filter(p => p.origin === "AUR");
    return aur.length > 0 && aur.every(p => covered.has(p.name));
}
function bindingChange(step, current, contentOnly = false) {
    if (current.binding === null) return "unreadable";
    if (!same(current.binary, step.binary)) return "binary";
    // The preceding system step may replace the AUR helper, Includes and
    // sync metadata. The AUR review binds package content, not those bytes.
    const fields = contentOnly ? ["pending", "origins"] : ["binary", "config", "pending", "origins"];
    for (const field of fields) {
        if (contentOnly && field === "origins") {
            const dependencies = binding => binding.origins.filter(row => row.neededBy !== undefined).map(({ target, origin, entry, neededBy, aur }) => ({ target, origin, entry, neededBy, aur }));
            const reviewed = dependencies(step.binding);
            if (!dependencies(current.binding).every(row => reviewed.some(prior => same(row, prior)))) return field;
        }
        const project = binding => contentOnly && field === "origins" ? binding.origins.filter(row => row.neededBy === undefined).map(({ target, origin }) => ({ target, origin })) : binding[field];
        if (!same(project(current.binding), project(step.binding))) return field;
    }
    return null;
}
// paru v2.1.0 (70f66dc9) devel.rs::parse_url tracks unpinned git
// sources from the base SRCINFO, not package-name suffixes.
function trackingBases(step, state) {
    const targets = new Set(step.action === "upgrade" ? step.binding.pending.map(p => p.name).filter(name => !step.ignored.includes(name))
        : step.names.concat(step.installs).map(name => name.split("/").pop()));
    const wanted = new Set(state.packages.filter(pkg => pkg.aur && targets.has(pkg.name)).map(pkg => pkg.name));
    const bases = new Set();
    const read = fields => {
        const base = fields.find(field => field.key === "pkgbase")?.value;
        const names = fields.filter(field => field.key === "pkgname").map(field => field.value);
        const baseFields = fields.slice(0, fields.findIndex(field => field.key === "pkgname"));
        if (names.some(name => wanted.has(name)) && baseFields.some(field => /^source(?:_|$)/.test(field.key)
            && /^git[^:]*:\/\/[^#]+(?:#(?!commit=|tag=).*)?$/.test(field.value.split("::").pop()))) {
            if (!base) refuse("review=tracking-srcinfo-unreadable");
            bases.add(base);
        }
    };
    if (state.packages.some(pkg => pkg.published && wanted.has(pkg.name))) {
        const published = publishedPackages();
        if (published.fields === null) refuse("review=tracking-srcinfo-unreadable cause=" + published.cause);
        for (const recipe of new Set(published.fields.map(field => field.recipe)))
            read(published.fields.filter(field => field.recipe === recipe));
    }
    for (const file of state.recipes.filter(file => path.basename(file.path) === ".SRCINFO"))
        read(judge.srcinfoFields(fs.readFileSync(file.path, "utf8")));
    return [...bases];
}
async function prepare(requestPath, resultPath) {
    const dir = path.dirname(requestPath);
    if (!path.isAbsolute(requestPath) || path.dirname(resultPath) !== dir || requestPath === resultPath) refuse("review=paths");
    const tx = transaction(dir);
    let request;
    try { request = JSON.parse(privateFile(requestPath)); } catch (_) { refuse("review=request-unreadable"); }
    if (privateFile(resultPath) !== "") refuse("review=result-not-empty");
    const resultFd = fs.openSync(resultPath, fs.constants.O_WRONLY | fs.constants.O_NOFOLLOW);
    const resultStat = fs.fstatSync(resultFd);
    if (!resultStat.isFile() || resultStat.nlink !== 1 || resultStat.uid !== process.getuid() || (resultStat.mode & 0o077) || resultStat.size !== 0) {
        fs.closeSync(resultFd); refuse("review=result-unsafe");
    }
    const storage = fs.mkdtempSync(path.join(dir, "owner-")); fs.chmodSync(storage, 0o700);
    let kept = false;
    try {
        const result = await review(request, storage);
        if (result.decision === "proceed") {
            const receipt = crypto.randomBytes(24).toString("hex");
            const record = { version: 1, coverage: result.coverage, owner: processIdentity(process.ppid), transaction: tx, request, state: result.state, consumed: [] };
            fs.writeFileSync(path.join(storage, receipt), JSON.stringify(record), { flag: "wx", mode: 0o600 });
            result.receipt = path.basename(storage) + "/" + receipt;
            kept = true;
        }
        const { state, status, ...wire } = result;
        fs.writeFileSync(resultFd, JSON.stringify(wire) + "\n");
        return status || 0;
    } finally { fs.closeSync(resultFd); if (!kept) fs.rmSync(storage, { recursive: true, force: true }); }
}
function consume(receipt, request, customArgv) {
    const dir = process.env.VGS_PACKAGE_TRANSACTION;
    if (!dir || !/^owner-[A-Za-z0-9]+\/[a-f0-9]{48}$/.test(receipt)) refuse("review=authority-missing");
    const tx = transaction(dir), file = path.join(dir, receipt);
    const lock = files.lockFile(file + ".lock", false);
    if (lock.state !== "held") refuse("review=authority-busy");
    try {
        const record = JSON.parse(privateFile(file));
        if (record.version !== 1 || !same(record.transaction, tx) || !same(processIdentity(record.owner.pid), record.owner)) refuse("review=authority-foreign");
        if (customArgv !== undefined) {
            if (!same(record.request.customAurArgv, customArgv) || customMode(customArgv) !== "unknown" || record.coverage !== "unknown" || record.customConsumed) refuse("review=authority-custom-changed");
            const binary = customArgv[0];
            if (!record.state.customBinding || !same(identity(fs.realpathSync(commandFile(binary) || binary)), record.state.customBinding)) refuse("review=authority-custom-changed");
            if (record.state.customConfig !== null && !same(configIdentity(record.request.config), record.state.customConfig)) refuse("review=authority-config-changed");
            const group = record.request.groups.find(g => g.manager === "aur");
            if (group) {
                const current = gather({ ...record.request, groups: [group], rebuild: [] });
                const step = record.state.steps.find(s => s.manager === "aur" && s.action === "upgrade");
                if (!step || step.binding === null) refuse("review=authority-binding-unreadable");
                const field = bindingChange(step, current.steps[0]);
                if (field !== null) refuse("review=authority-binding-changed field=" + field);
            }
            record.customConsumed = true;
            fs.writeFileSync(file, JSON.stringify(record), { mode: 0o600 });
            return { kind: "custom", coverage: "unknown" };
        }
        const group = request.groups[0];
        if (record.request.customAurArgv !== null && group.manager !== "aur") {
            const binary = record.request.customAurArgv[0];
            if (!record.state.customBinding || !same(identity(fs.realpathSync(commandFile(binary) || binary)), record.state.customBinding)) refuse("review=authority-custom-changed");
        }
        if (group.manager === "aur" && request.action === "upgrade" && record.request.customAurArgv !== null && customMode(record.request.customAurArgv) === "unknown") refuse("review=authority-custom-only");
        const index = record.state.steps.findIndex(s => s.manager === group.manager && s.action === request.action && same(s.names, group.names) && same(s.installs, group.installs) && same(s.ignored, group.ignored) && s.config === request.config);
        if (index < 0 || record.consumed.includes(index)) refuse("review=authority-stale-or-consumed");
        const step = record.state.steps[index];
        if (step.binding === null) refuse("review=authority-binding-unreadable");
        const original = record.request.groups.find(g => g.manager === step.manager);
        const current = gather({ ...request, groups: [{ ...group, ignored: step.inputIgnored }], rebuild: [] });
        const field = bindingChange(step, current.steps[0], group.manager === "aur");
        if (field !== null) refuse("review=authority-binding-changed field=" + field);
        if (record.state.recipes.length && !same(recipesIdentity(path.join(path.dirname(file), "evidence/build")), record.state.recipes)) refuse("review=authority-binding-changed field=recipes");
        if (!original && request.action === "upgrade") refuse("review=authority-step-missing");
        record.consumed.push(index);
        fs.writeFileSync(file, JSON.stringify(record), { mode: 0o600 });
        const dependenciesCovered = helperReviewCovered(step, record.state);
        return { ...step, coverage: record.coverage, dependenciesCovered,
            ...(group.manager === "aur" && path.basename(step.binary) === "paru" && dependenciesCovered
                ? { trackingBases: trackingBases(step, record.state) } : {}) };
    } catch (e) {
        if (e instanceof files.Refusal) throw e;
        refuse("review=authority-unreadable");
    } finally { lock.release(); }
}
async function admit(action, manager, names, ignored = [], installs = [], config, receipt) {
    // A verified-file package's origin evidence is its signature against the
    // pinned key, which bin/lib/pkg-file.js checks before any root step, so
    // it takes no review, as an official repository's package takes none.
    if (!["pacman", "aur"].includes(manager) || action === "remove") return { names, ignored, installs, config };
    const request = { version: 1, mode: action === "upgrade" ? "upgrade" : "named", action, groups: [{ manager, names, installs, ignored }], sources: action === "upgrade" ? [manager] : [], rebuild: [], config: config || null, customAurArgv: null };
    if (receipt) return consume(receipt, request);
    if (process.env.VGS_PACKAGE_TRANSACTION) refuse("review=authority-missing");
    const storage = fs.mkdtempSync(path.join(agentHome(), "review-")); fs.chmodSync(storage, 0o700);
    try {
        const result = await review(request, storage);
        if (result.decision !== "proceed") return { stop: true, status: result.status || 0 };
        const step = result.state.steps[0];
        if (result.skipped.length) process.stderr.write("Packages skipped: " + result.skipped.join(", ") + "\n");
        // Declining preserves the original argv, including absence of --config.
        return { names: step.names, installs: step.installs, ignored: step.ignored, config };
    } finally { fs.rmSync(storage, { recursive: true, force: true }); }
}
async function bootstrap() {
    const storage = fs.mkdtempSync(path.join(agentHome(), "bootstrap-"));
    fs.chmodSync(storage, 0o700);
    try {
        const result = await review({ version: 1, mode: "bootstrap", action: "install", groups: [{manager:"pacman",names:["paru"],installs:[],ignored:[]}], sources: [], rebuild: [], config: null, customAurArgv: null }, storage);
        return result.decision === "proceed" && !result.skipped.includes("paru") ? 0 : result.status || 1;
    } finally { fs.rmSync(storage, { recursive: true, force: true }); }
}
module.exports = { available, bootstrap, customMode, consumeCustom: (receipt, argv) => consume(receipt, null, argv), judge, requestError, settingsRead, settingsWrite, createTransaction, prepare, admit, gather, configIdentity, recipesIdentity, agentHome, ownedDirectory, privateFile, ui, evidenceFailures, orphanInfo, rebuildAllowed };
