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
    const user = files.readUserConfig(configLogic, file, "user-config", shipped.packageReviewSettingsSource);
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
            const source = files.readConfig(configLogic, path.join(repo, "config/shell.json"), "shipped-config").packageReviewSettingsSource;
            const moved = latest.text === null ? { config: null } : configLogic.migrateConfig(JSON.parse(latest.text), source);
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
// gum 2.0.2's choose exits 1 for Esc and 130 for Ctrl-C (a pty run of
// `gum choose a b`, 2026-11-01), and a question that could not be asked
// consents to nothing either.
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
    // Reuse Updates' effective helper-config adapter, now package-owned.
    const r = query([process.execPath, path.join(__dirname, "pkg-config.js"), binary]);
    if (r.error || r.status !== 0) throw new Error("config=helper-unreadable");
    return JSON.parse(r.stdout).config;
}
function pending(group, config, binary) {
    const found = managers.reviewCheckFor(group.manager, binary, config);
    if (!found.check) throw new Error("pending=query-unavailable");
    const check = found.check;
    const r = query(check.argv);
    if (r.error) throw new Error("pending=" + r.error.code);
    const result = managers.checkOutcome(check, r.status, r.stdout, r.stderr);
    if (result.error) throw new Error("pending=" + result.error);
    return { complete: found.complete, origin: found.origin, packages: result.packages.filter(p => !group.ignored.includes(p.name)) };
}
function gather(request) {
    const state = { steps: [], packages: [], unknown: [], lines: [], recipes: [] };
    let repositoryData = null;
    function repositories(config) {
        if (repositoryData?.config === config) return repositoryData;
        const order = output(["pacman-conf", "--config", config, "--repo-list"]).trim().split(/\s+/).filter(Boolean);
        if (!order.length) throw new Error("origin=empty-repositories");
        const rows = output(["pacman", "--config", config, "-Sl"]).trim().split(/\r?\n/).filter(Boolean).map(line => {
            const m = /^(\S+) (\S+) (\S+)(?: \[.*\])?$/.exec(line);
            if (!m || !order.includes(m[1])) throw new Error("origin=malformed-index");
            return { repository: m[1], name: m[2], version: m[3] };
        });
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
                if (!p.complete) state.unknown.push("pending=config-correspondence");
                targets = p.packages.map(item => ({ target: item.name, old: item.old, next: item.new, origin: p.origin }));
            } else targets = [...group.names, ...group.installs].map(n => ({ target: n, old: null, next: null }));
            step.binding = binding;
            const repos = request.mode === "bootstrap" ? { rows: [], order: [] } : repositories(config);
            for (const target of targets) {
                const qualified = /^([^/]+)\/([^/]+)$/.exec(target.target);
                const [qualifier, name] = qualified === null ? [null, target.target] : [qualified[1], qualified[2]];
                const matches = repos.rows.filter(row => row.name === name && (qualifier === null || qualifier === row.repository));
                let origin;
                if (request.mode === "bootstrap") origin = "aur";
                else if (target.origin === "aur" && matches.length > 0) { state.unknown.push("origin=aur-repository-collision name=" + name); origin = "unknown"; }
                else if (matches.length === 1) origin = matches[0].repository;
                else if (matches.length > 1) { state.unknown.push("origin=ambiguous name=" + name); origin = "unknown"; }
                else if (group.manager === "aur" || request.mode === "bootstrap") {
                    const info = output([found.binary, "--config", config, "-Si", "--", name]);
                    const identity = /^Name\s*:\s*(\S+)\s*$/m.exec(info);
                    if (!/^Repository\s*:\s*aur\s*$/m.test(info) || identity === null || identity[1] !== name) throw new Error("origin=unresolved name=" + name);
                    origin = "aur";
                    // Helpers can add providers/dependencies at build time. This
                    // review covers its listed request, never that future choice.
                    state.unknown.push("dependencies=unresolved name=" + name);
                } else { state.unknown.push("origin=unresolved name=" + name); origin = "unknown"; }
                binding.origins.push({ target: target.target, origin, candidates: matches.map(row => ({ repository: row.repository, version: row.version })) });
                if (judge.officialRepository(origin)) continue;
                const pkg = { name, origin, old: target.old, next: target.next, manager: group.manager, binary: found.binary, config };
                if (!state.packages.some(p => p.name === name && p.origin === origin)) state.packages.push(pkg);
                state.lines.push(origin === "aur" ? `aur ${name} ${target.old || "?"} ${target.next || "?"}` : `repo ${origin} ${name} ${target.old || "?"} ${target.next || "?"}`);
                if (origin !== "aur" && origin !== "unknown") {
                    const servers = output(["pacman-conf", "--config", config, "--repo", origin, "Server"]).trim().split("\n").filter(Boolean);
                    if (!servers.length) throw new Error("origin=server-unreadable name=" + name);
                    for (const server of servers) {
                        const url = new URL(server); url.username = ""; url.password = "";
                        state.lines.push(`server ${origin} ${url.toString()}`);
                    }
                    const signature = output(["pacman-conf", "--config", config, "--repo", origin, "SigLevel"]).trim().replace(/\s+/g, " ");
                    if (!signature) throw new Error("origin=signature-unreadable name=" + name);
                    state.lines.push(`siglevel ${origin} ${signature}`);
                }
            }
        } catch (e) { state.unknown.push(e.message); }
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
function installEvidence(dir, pkg, state) {
    const build = path.join(dir, "build");
    let selected = null;
    for (const entry of fs.readdirSync(build, { withFileTypes: true })) {
        if (!entry.isDirectory()) continue;
        const folder = path.join(build, entry.name);
        const src = path.join(folder, ".SRCINFO");
        if (!fs.existsSync(src) || !fs.lstatSync(src).isFile()) continue;
        let section = "", base = "", own = "", ownSet = false, found = false;
        for (const line of fs.readFileSync(src, "utf8").split("\n")) {
            const m = /^\s*(\w+)\s*=\s*(.*?)\s*$/.exec(line);
            if (!m) continue;
            if (m[1] === "pkgbase") section = "base";
            if (m[1] === "pkgname") { section = m[2] === pkg.name ? "own" : "other"; if (section === "own") found = true; }
            if (m[1] === "install" && section === "base") base = m[2];
            if (m[1] === "install" && section === "own") { own = m[2]; ownSet = true; }
        }
        if (found) { selected = { folder, script: ownSet ? own : base, src }; break; }
    }
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
function recipesIdentity(dir) {
    const entries = [];
    let bytes = 0;
    function read(at) {
        for (const row of fs.readdirSync(at, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name))) {
            const file = path.join(at, row.name);
            if (row.isDirectory()) { if (row.name !== ".git") read(file); }
            else if (row.isFile()) {
                bytes += fs.statSync(file).size;
                if (entries.length >= 4096 || bytes > 64 * MAX_DATA) throw new Error("recipe=bound");
                entries.push(identity(file));
            }
            else throw new Error("recipe=not-regular");
        }
    }
    read(dir);
    return entries;
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
    const error = requestError(request);
    if (error) refuse("review=request error=" + error);
    if (process.env.VGS_TUI_SUDO_SESSION && fs.existsSync("/proc/" + process.env.VGS_TUI_SUDO_SESSION)) refuse("review=outer-credential-session");
    const state = gather(request);
    let settings = settingsRead().settings;
    const result = { version: 1, decision: "proceed", reviewed: [], skipped: [], coverage: "complete", receipt: null };
    if (state.packages.length || state.unknown.length) {
        const known = state.packages.map(p => p.name);
        const requested = request.groups.flatMap(g => g.names.concat(g.installs)).concat(request.rebuild);
        const listed = known.concat(requested.filter(n => !known.includes(n.split("/").pop())));
        const packageList = "Packages: " + ([...new Set(listed)].join(", ") || "origin or pending list unavailable");
        let choice;
        for (;;) {
            const found = foundAgents(settings), initial = judge.initialChoice(settings, found);
            choice = await ui("offer", initial.action === "review" ? "Review" : "Install without review", packageList);
            if (choice.cancelled) return { ...result, decision: "cancelled", coverage: "unknown", status: choice.status };
            if (choice.value !== "Review") break;
            // The offer above names the packages until the editor's views
            // stand between it and the agent choice.
            let edited = false;
            for (;;) {
                const plan = judge.reviewPlan(settings, foundAgents(settings));
                if (!["agent", "command"].includes(plan.state)) break;
                const agentChoice = await ui("agent", plan.label, ...(edited ? [packageList] : []));
                if (agentChoice.cancelled) return { ...result, decision: "cancelled", coverage: "unknown", status: agentChoice.status };
                if (agentChoice.value === "Back") { choice = null; break; }
                if (agentChoice.value === "Use " + plan.label) break;
                if (agentChoice.value !== "Customize") refuse("review=choice-invalid");
                const edit = await interactive([commandFile("bash"), path.join(__dirname, "pkg-review.sh"), "customize", path.join(repo, "bin/vgshell-pkg")]);
                edited = true;
                if (edit.signal) return { ...result, decision: "cancelled", coverage: "unknown", status: 128 + os.constants.signals[edit.signal] };
                if (edit.error || (edit.status !== 0 && edit.status !== 130)) refuse("review=editor-unavailable");
                settings = settingsRead().settings;
            }
            if (choice !== null) break;
        }
        if (choice.value === "Install without review") result.coverage = "declined";
        else if (choice.value === "Review") {
            const plan = judge.reviewPlan(settings, foundAgents(settings));
            let verdict = null, risks = [];
            const dir = path.join(storage, "evidence");
            fs.mkdirSync(dir, { mode: 0o700 }); fs.mkdirSync(path.join(dir, "build"), { mode: 0o700 }); fs.mkdirSync(path.join(dir, "install"), { mode: 0o700 });
            try {
                if (!["agent", "command"].includes(plan.state)) throw new Error("agent=" + plan.state);
                for (const pkg of state.packages.filter(p => p.origin === "aur")) {
                    const fetch = request.mode === "bootstrap" ? ["git", "clone", "--", "https://aur.archlinux.org/paru.git", "paru"] : [pkg.binary, "--config", pkg.config, "-G", "--", pkg.name];
                    const shownFetch = await ui("show", "Fetching package build files as your user", ...fetch);
                    if (shownFetch.cancelled) return { ...result, decision: "cancelled", coverage: "unknown", status: shownFetch.status };
                    const r = await interactive(fetch, { cwd: path.join(dir, "build") });
                    if (r.signal) return { ...result, decision: "cancelled", coverage: "unknown", status: 128 + os.constants.signals[r.signal] };
                    if (r.error || r.status !== 0) throw new Error("fetch=failed");
                    try { risks.push(...installEvidence(dir, pkg, state)); }
                    catch (e) { state.unknown.push(e.message); risks.push({ name: pkg.name, concern: "The install script could not be verified." }); }
                }
                state.recipes = recipesIdentity(path.join(dir, "build"));
                fs.writeFileSync(path.join(dir, "packages.txt"), state.lines.concat(state.unknown.map(e => "unknown " + e)).join("\n") + "\n", { mode: 0o600 });
                const prompt = fs.readFileSync(path.join(__dirname, "review/third-party.md"), "utf8").replaceAll("{review_dir}", dir);
                const shownAgent = await ui("show", "Reviewing the listed packages before installation", ...plan.command);
                if (shownAgent.cancelled) return { ...result, decision: "cancelled", coverage: "unknown", status: shownAgent.status };
                const run = await interactive(plan.command.concat(prompt), { cwd: agentHome() });
                if (run.signal) return { ...result, decision: "cancelled", coverage: "unknown", status: 128 + os.constants.signals[run.signal] };
                if (run.error || run.status !== 0) throw new Error("agent=failed");
                verdict = judge.parseVerdict(privateFile(path.join(dir, "verdict")), state.packages.map(p => p.name));
                if (!verdict.ok) throw new Error("verdict=invalid");
                result.reviewed = state.packages.map(p => p.name);
            } catch (e) { state.unknown.push(e.message); }
            if (verdict === null || !verdict.ok || state.unknown.length) {
                result.coverage = "unknown";
                const answer = await ui("unavailable");
                if (answer.cancelled) return { ...result, decision: "cancelled", status: answer.status };
                if (answer.value === "No") return { ...result, decision: "stop" };
                if (answer.value !== "Yes") refuse("review=choice-invalid");
            }
            const concerns = new Map();
            for (const flag of [...(verdict?.ok ? verdict.flags : []), ...risks]) concerns.set(flag.name, [...(concerns.get(flag.name) || []), flag.concern]);
            for (const [name, concernsForName] of concerns) {
                const answer = await ui("concern", concernsForName.join("\n"), name);
                if (answer.cancelled) return { ...result, decision: "cancelled", status: answer.status };
                if (answer.value === "Skip") result.skipped.push(name);
                else if (answer.value !== "Install anyway") refuse("review=choice-invalid");
            }
        } else refuse("review=choice-invalid");
    }
    if (request.customAurArgv !== null && customMode(request.customAurArgv) === "unknown") {
        if (result.skipped.length) return { ...result, decision: "stop", coverage: "unknown" };
        if (result.coverage === "declined") {
            const answer = await ui("unavailable");
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
                if (!step || !same(current.steps[0].binding, step.binding)) refuse("review=authority-binding-changed");
            }
            record.customConsumed = true;
            fs.writeFileSync(file, JSON.stringify(record), { mode: 0o600 });
            return { kind: "custom", coverage: "unknown" };
        }
        if (record.request.customAurArgv !== null) {
            const binary = record.request.customAurArgv[0];
            if (!record.state.customBinding || !same(identity(fs.realpathSync(commandFile(binary) || binary)), record.state.customBinding)) refuse("review=authority-custom-changed");
        }
        const group = request.groups[0];
        if (group.manager === "aur" && request.action === "upgrade" && record.request.customAurArgv !== null && customMode(record.request.customAurArgv) === "unknown") refuse("review=authority-custom-only");
        const index = record.state.steps.findIndex(s => s.manager === group.manager && s.action === request.action && same(s.names, group.names) && same(s.installs, group.installs) && same(s.ignored, group.ignored) && s.config === request.config);
        if (index < 0 || record.consumed.includes(index)) refuse("review=authority-stale-or-consumed");
        const step = record.state.steps[index];
        if (step.binding === null) refuse("review=authority-binding-unreadable");
        const original = record.request.groups.find(g => g.manager === step.manager);
        const current = gather({ ...request, groups: [{ ...group, ignored: step.inputIgnored }], rebuild: [] });
        if (!same(current.steps[0].binding, step.binding) || !same(current.steps[0].binary, step.binary)) refuse("review=authority-binding-changed");
        if (record.state.recipes.length && !same(recipesIdentity(path.join(path.dirname(file), "evidence/build")), record.state.recipes)) refuse("review=authority-recipe-changed");
        if (!original && request.action === "upgrade") refuse("review=authority-step-missing");
        record.consumed.push(index);
        fs.writeFileSync(file, JSON.stringify(record), { mode: 0o600 });
        return step;
    } catch (e) {
        if (e instanceof files.Refusal) throw e;
        refuse("review=authority-unreadable");
    } finally { lock.release(); }
}
async function admit(action, manager, names, ignored = [], installs = [], config, receipt) {
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
module.exports = { available, bootstrap, customMode, consumeCustom: (receipt, argv) => consume(receipt, null, argv), judge, requestError, settingsRead, settingsWrite, createTransaction, prepare, admit, gather, configIdentity, recipesIdentity, agentHome, ownedDirectory, privateFile, ui };
