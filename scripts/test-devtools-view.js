#!/usr/bin/env node
// The Dev Tools plugin's decisions, shell/plugins/vgs.devtools/ViewLogic.js,
// under node: which queries each trigger runs and their argv, how an answer
// is read, the status values the service publishes, the TUI arguments an
// action passes, and the sections and rows the window draws. Every expected
// value is written out by hand.
//
// The controls at the end edit a copy of the logic, one rule at a time,
// and require this suite to fail on each copy.
"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");
const { load } = require("../bin/lib/qml-library.js");

const dir = path.join(__dirname, "..", "shell", "plugins", "vgs.devtools");
const file = path.join(dir, "ViewLogic.js");
const windowFile = path.join(dir, "Window.qml");
const serviceFile = path.join(dir, "Service.qml");
const Catalog = load(path.join(dir, "CatalogLogic.js"));
const PluginLogic = load(path.join(__dirname, "..", "shell", "Core", "PluginLogic.js"));
const realCatalog = JSON.parse(fs.readFileSync(path.join(dir, "catalog.json"), "utf8"));
const manifest = JSON.parse(fs.readFileSync(path.join(dir, "manifest.json"), "utf8"));
// The logic runs in its own context, whose arrays and objects are not this
// one's; values are compared as JSON.
const same = (got, want, message) => assert.deepEqual(JSON.parse(JSON.stringify(got)), want, message === undefined ? JSON.stringify(want) : message);

// A list row as `devtools list --json` prints it, with FIELDS over an
// absent agent's defaults.
const row = fields => Object.assign({ id: "claude", name: "Claude Code", section: "agents", icon: "bot", brand: "claude", kind: null, command: "claude", launch: ["claude"], installed: false, version: null,
    origin: null, manager: null, package: null, runtime: null, path: null, launcher: "absent", requested: null, pinned: false, rollbackVersion: null, latest: null, failed: null, channels: null, actions: ["install"], error: null }, fields);
const list = (sections, other, mise) => ({ machine: "x86_64", mise: mise || { present: true, version: "2026.9.9" }, manager: "pacman",
    sections: Object.assign({ agents: [], apps: [], tools: [], envs: [], editors: [], terminals: [], databases: [] }, sections), other: other || [] });
const requirement = fields => Object.assign({ name: "gum", bus: null, packages: { pacman: "gum" }, optional: false, purpose: "Draws the dialogs", state: "missing", package: { manager: "pacman", name: "gum" } }, fields);
const self = fields => Object.assign({ version: "0.1.0", method: "checkout", package: null, current: "0.1.0.r3.gabc1234", latest: "0.1.1", behind: false, error: null }, fields);
const ok = value => ({ value: value, error: null });

function worstCaseStatusBytes(logic) {
    const machine = process.arch === "arm64" ? "aarch64" : "x86_64";
    const sections = {};
    for (const section of Catalog.SECTION_NAMES) {
        sections[section] = realCatalog[section].filter(r => Catalog.availableOn(r, machine)).map(r => Object.assign(row({
            id: r.id, name: r.name, section: section, icon: r.icon || null, brand: r.brand || null, kind: r.kind || null, command: r.command || null, launch: r.launch || null,
            installed: true, version: "2026.10.06-devtools-status-measurement-version-1234567890",
            origin: typeof r.package === "string" || Array.isArray(r.tools) ? "mise" : r.installer !== undefined ? "installer" : r.container !== undefined ? "container" : "package",
            actions: ["update", "remove"], requested: "2026.10.06-devtools-status-measurement-version-1234567890", pinned: true,
            rollbackVersion: "2026.10.05-devtools-status-measurement-version-1234567890", latest: "2026.10.07-devtools-status-measurement-version-1234567890"
        })));
    }
    const report = { machine: machine, mise: { present: true, version: "2026.9.9 status measurement" }, manager: "pacman", sections: sections, other: [] };
    const values = logic.statusValues({ catalog: { value: report, error: null } });
    values.launcherRows = logic.launcherRows(report, true);
    return Buffer.byteLength(JSON.stringify(values), "utf8");
}

// The configure capability delegates to Plugins.writeSetting and
// Config.writeUser. These replies cover their refusal classes.
const SETTING_REPLIES = [
    ["ok", ""],
    ["refused: user-config=pending path=/fixture/settings", "VGS is loading your settings. Try again shortly."],
    ...["unparseable", "unreadable", "malformed"].map(state => [
        `refused: user-config=${state} path=/fixture/settings`,
        "VGS could not read your settings. Close Dev Tools and open it again to retry."
    ]),
    ["refused: user-config=unwritable path=/fixture/settings error=permission denied\nsecond line", "VGS could not save this change. Try again."],
    ...["undeclared", "want=boolean", "entry=none"].map(reason => [
        `refused: setting=writeLaunchers ${reason}`,
        "VGS could not change this setting. Close Dev Tools and open it again to retry."
    ]),
    ["unknown: vgs.devtools", "VGS could not change this setting. Close Dev Tools and open it again to retry."],
    ["unexpected diagnostic=failed", "VGS could not save this change. Try again."]
];

function handlerFor(source, key) {
    const needle = `const reply = root.shell.configure.set("${key}", wanted);`;
    const at = source.indexOf(needle);
    assert.notEqual(at, -1, key + " handler writes its setting");
    const start = source.lastIndexOf("onToggled: {", at);
    assert.notEqual(start, -1, key + " handler has a toggled block");
    let depth = 0;
    for (let i = source.indexOf("{", start); i < source.length; i++) {
        if (source[i] === "{") depth += 1;
        else if (source[i] === "}") {
            depth -= 1;
            if (depth === 0) return source.slice(source.indexOf("{", start) + 1, i);
        }
    }
    throw new Error(key + " handler did not close");
}

// The two settings switches write only their declared setting, restore
// their binding, map the raw reply for the user, and keep the raw reply
// only in the developer log.
function verifySettingHandler(logic, source) {
    for (const key of ["showInLauncher", "writeLaunchers"]) {
        const handler = handlerFor(source, key);
        for (const [reply, message] of SETTING_REPLIES) {
            for (const wanted of [false, true]) {
                const writes = [], logs = [];
                const root = { [key]: !wanted, problem: "previous problem", shell: {
                    configure: { set: (name, value) => { writes.push([name, value]); return reply; } }
                } };
                const context = { checked: wanted, root, ViewLogic: logic, Qt: { binding: callback => callback },
                    console: { warn: line => logs.push(line) } };
                vm.runInNewContext(handler, context, { filename: windowFile });
                same(writes, [[key, wanted]], key + " handler writes the user's requested value once");
                assert.equal(typeof context.checked, "function", key + " handler restores its checked binding");
                assert.equal(context.checked(), !wanted, key + " handler binding reads the current setting");
                assert.equal(root.problem, message, `${key} handler maps ${reply}`);
                same(logs, message === "" ? [] : ["devtools window: configure " + JSON.stringify(reply)]);
            }
        }
    }
}

// Failures read from a command: [label, code, stderr, error].
const FAILURES = [
    ["a command that did not start", null, "", "start=failed"],
    ["a refusal line", 1, "fatal: noise\nvgshell: refused: manager=mise reason=absent binaries=mise\n", "manager=mise reason=absent binaries=mise"],
    ["the engine's refusal", 1, "devtools: refused: mise=failed args=ls,--json exit=2\n", "mise=failed args=ls,--json exit=2"],
    ["the first line without a refusal", 3, "\nboom\nmore\n", "boom"],
    ["no stderr", 4, "", "exit=4"],
    ["a long line is clipped", 1, "x".repeat(300), "x".repeat(199) + "…"]
];

// Answers read from stdout: [label, name, stdout, answer].
const ANSWERS = [
    ["a list", "catalog", JSON.stringify(list({})), ok(list({}))],
    ["a list without other", "catalog", JSON.stringify({ mise: { present: true }, sections: {} }), { value: null, error: "unparseable" }],
    ["a list missing a section", "catalog", JSON.stringify(Object.assign(list({}), { sections: { agents: [] } })), { value: null, error: "unparseable" }],
    ["not JSON", "catalog", "nope", { value: null, error: "unparseable" }],
    ["a doctor report", "requirements", JSON.stringify({ core: [], plugins: { "acme.x": [] } }), ok({ core: [], plugins: { "acme.x": [] } })],
    ["a doctor report whose plugin holds no list", "requirements", JSON.stringify({ core: [], plugins: { "acme.x": {} } }), { value: null, error: "unparseable" }],
    ["a self status", "vgs", JSON.stringify(self({})), ok(self({}))],
    ["a self status without behind", "vgs", JSON.stringify({ version: "0.1.0", method: "curl", error: null }), { value: null, error: "unparseable" }],
    ["a mise count", "updates", JSON.stringify([{ source: "mise", count: 2, packages: [{ name: "claude", old: "1", new: "2" }], checkedAt: 1, error: null }]),
        ok({ count: 2, packages: [{ name: "claude", old: "1", new: "2" }] })],
    ["a mise source that failed", "updates", JSON.stringify([{ source: "mise", count: null, packages: [], checkedAt: null, error: "timeout=120" }]), { value: null, error: "timeout=120" }],
    ["another source", "updates", JSON.stringify([{ source: "pacman", count: 0, packages: [], checkedAt: 1, error: null }]), { value: null, error: "unparseable" }],
    ["launcher lines", "launchers", "launcher=written command=claude path=/h/.local/bin/claude\n", ok(["launcher=written command=claude path=/h/.local/bin/claude"])],
    ["latest versions", "latest", JSON.stringify({ claude: "2.0.0", node: null }), ok({ claude: "2.0.0", node: null })]
];

function verify(logic) {
    // Producer diagnostics never cross the display boundary.
    for (const diagnostic of ["installed=already", "arch=unsupported", "reason=foreign", "mise=absent", "id=unknown", "runner=missing", "step=failed exit=1", "unexpected: key=value"]) {
        const text = logic.actionErrorText(diagnostic);
        assert.ok(text.length > 0, "a failed tool action must tell the user");
        assert.doesNotMatch(text, /[a-z][a-z-]*=/);
    }
    for (const diagnostic of ["start=failed", "unparseable", "timeout=120", "mise=absent", "runtime=podman exit=1", "release=unreachable", "pkg=failed", "unexpected: key=value"]) {
        const text = logic.errorText(diagnostic);
        assert.ok(text.length > 0, "a failed operation must tell the user");
        assert.doesNotMatch(text, /[a-z][a-z-]*=|start-failed|output-unreadable/, "diagnostic fields stay in logs");
    }

    // Sections: the catalog's own and `other`, each once, with an icon.
    same(logic.TOOL_SECTIONS.map(s => s.key).filter(k => k !== "other").sort(), JSON.parse(JSON.stringify(Catalog.SECTION_NAMES)).sort(), "the window draws every catalog section");
    same(logic.TOOL_SECTIONS.map(s => s.title), ["Agents", "Apps", "Command-line tools", "Languages", "Editors", "Databases", "Terminals", "Other tools"]);
    // The TUI names the window runs are the manifest's.
    same(JSON.parse(JSON.stringify(logic.VERBS)).sort(), Object.keys(manifest.tui).sort(), "every TUI the window runs is declared");

    // Triggers.
    same(logic.queriesFor("start", {}, 0), ["launchers", "requirements", "vgs", "updates", "latest"]);
    same(logic.queriesFor("refresh", { vgs: 0, updates: 0, latest: 0 }, 1), ["launchers", "requirements", "vgs", "updates", "latest"]);
    same(logic.queriesFor("tui", {}, 0), ["launchers", "requirements", "updates", "latest"]);
    same(logic.queriesFor("setting", {}, 0), ["launchers"]);
    same(logic.queriesFor("scan", {}, 0), ["launchers", "requirements", "updates", "latest"], "a scan that found another set lists again, since it can bring mise");
    const fresh = logic.NETWORK_FRESH_MS;
    same(logic.queriesFor("open", { vgs: 1000, updates: 1000, latest: 1000 }, 1000 + fresh - 1), ["launchers", "requirements"], "an open inside the window asks no remote");
    same(logic.queriesFor("open", { vgs: 1000, updates: 2000, latest: 2000 }, 1000 + fresh), ["launchers", "requirements", "vgs"], "an open asks each remote whose answer is stale");
    same(logic.queriesFor("open", {}, 0), ["launchers", "requirements", "vgs", "updates", "latest"], "an open asks a remote never asked");
    assert.throws(() => logic.queriesFor("boot", {}, 0), /trigger "boot" is not one of/);
    assert.equal(logic.next("launchers"), "catalog");
    for (const name of ["catalog", "requirements", "vgs", "updates", "latest"]) assert.equal(logic.next(name), "");

    // Argv.
    same(logic.queryArgv("launchers", "/t", "/p", true), ["/p/bin/devtools", "--tree", "/t", "launchers", "refresh"]);
    same(logic.queryArgv("launchers", "/t", "/p", false), ["/p/bin/devtools", "--tree", "/t", "launchers", "remove"]);
    same(logic.queryArgv("catalog", "/t", "/p", false), ["/p/bin/devtools", "--tree", "/t", "list", "--json"]);
    same(logic.queryArgv("requirements", "/t", "/p", false), ["/t/bin/vgshell", "doctor", "--json"]);
    same(logic.queryArgv("vgs", "/t", "/p", false), ["/t/bin/vgshell", "self", "status", "--json"]);
    same(logic.queryArgv("updates", "/t", "/p", false), ["/t/bin/vgshell", "pkg", "check", "--json", "--source", "mise"]);
    same(logic.queryArgv("latest", "/t", "/p", false), ["/p/bin/devtools", "--tree", "/t", "latest", "--json"]);
    assert.throws(() => logic.queryArgv("nope", "/t", "/p", false), /query "nope" is not one of/);

    // Answers.
    for (const [label, code, stderr, error] of FAILURES)
        same(logic.readAnswer("catalog", code, "", stderr), { value: null, error: error }, label);
    for (const [label, name, stdout, answer] of ANSWERS)
        same(logic.readAnswer(name, 0, stdout, ""), answer, label);

    // Missing requirements: the core's first, then each plugin's by id.
    same(logic.missingRequirements({ core: [requirement({ name: "node", state: "present" }), requirement({ optional: true })],
        plugins: { "zeta.x": [requirement({ name: "z", package: null })], "acme.y": [requirement({ name: "a" })] } }), [
        { owner: "core", name: "gum", purpose: "Draws the dialogs", optional: true, package: { manager: "pacman", name: "gum" } },
        { owner: "acme.y", name: "a", purpose: "Draws the dialogs", optional: false, package: { manager: "pacman", name: "gum" } },
        { owner: "zeta.x", name: "z", purpose: "Draws the dialogs", optional: false, package: null }
    ]);

    // Status values.
    same(logic.statusValues({}), { catalog: { tools: null, requirements: null, vgs: null, updates: null, latest: null, launchers: null } }, "nothing answered publishes the empty catalog alone");
    same(logic.statusValues({ vgs: ok(self({})) }).checks, { tone: "ok", text: "All checks passed" });
    same(logic.statusValues({ vgs: ok(self({ error: "latest=timeout" })) }).checks, { tone: "warning", text: "Checks failed" },
        "a self status that exited 0 with an error is a failed check");
    const listed = list({ agents: [row({ installed: true, origin: "mise", version: "2", actions: ["update", "remove"] }), row({ id: "codex" })], apps: [row({ id: "cmux", installed: null, error: "e" })] },
        [{ id: "github:o/x", installed: true, version: "1", actions: ["update", "remove"] }]);
    const values = logic.statusValues({ catalog: ok(listed), updates: ok({ count: 3, packages: [] }), requirements: ok({ core: [requirement({})], plugins: { "acme.y": [requirement({ state: "present" })] } }), launchers: ok(["launcher=written command=claude path=/h/.local/bin/claude", "launcher=foreign command=codex path=/h/.local/bin/codex"]) });
    same([values.mise, values.installed, values.outdated, values.missingRequirements], [{ tone: "ok", text: "2026.9.9" }, 2, 3, 1]);
    same(values.catalog.requirements, ok([{ owner: "core", name: "gum", purpose: "Draws the dialogs", optional: false, package: { manager: "pacman", name: "gum" } }]), "the catalog holds the missing requirements alone");
    same(logic.statusValues({ catalog: ok(list({}, [], { present: false, version: null })) }).mise, { tone: "warning", text: "Not installed", action: true }, "a missing mise offers Install mise");
    const failed = logic.statusValues({ catalog: { value: null, error: "mise=absent" }, updates: { value: null, error: "timeout=120" }, requirements: { value: null, error: "exit=1" } });
    same(failed.mise, { tone: "danger", text: "A required tool is missing. Use Install to add it." });
    same(["installed", "outdated", "missingRequirements"].filter(k => k in failed), [], "a failed query publishes no count");
    same(failed.checks, { tone: "warning", text: "Checks failed" },
        "a failed query keeps the warning while withholding its count");

    // Launcher rows and catalog page additions.
    const launcherList = list({ agents: [
        row({ installed: true, origin: "mise", version: "1.0.0", actions: ["update", "remove"], latest: "2.0.0", rollbackVersion: "0.9.0" }),
        row({ id: "node", name: "Node", command: "node", launch: ["node"], installed: true, origin: "mise", version: "20.0.0", actions: ["update", "remove"], requested: "20.0.0", pinned: true, rollbackVersion: "18.0.0", latest: "21.0.0" }),
        row({ id: "owner", name: "Owner", command: "owner", launch: ["owner"], installed: true, origin: "foreign", actions: [] }),
        row({ id: "broken", name: "Broken", command: "broken", launch: ["broken"], failed: { line: "download failed", at: 1 }, actions: ["install"] })
    ], apps: [row({ id: "code", name: "Code", section: "apps", kind: "gui", command: "code", launch: ["code"], installed: true, version: "2", origin: "mise", actions: ["update", "remove"] })],
        terminals: [row({ id: "alacritty", name: "Alacritty", section: "terminals", kind: "gui", command: "alacritty", launch: ["alacritty"], installed: true, version: "2", origin: "mise", actions: [] })] });
    const statusBytes = worstCaseStatusBytes(logic);
    assert.equal(statusBytes, 58064, "the real catalog worst-case status payload size is pinned to this test's model");
    assert.ok(PluginLogic.STATUS_MAX_BYTES - statusBytes >= 7000, "the Dev Tools status payload keeps at least 7000 bytes below the status ceiling");
        same(logic.launcherRows(null, true), [], "no list publishes no launcher rows");
    same(logic.launcherRows(launcherList, false), [], "showInLauncher hides launcher rows");
    same(logic.launcherRows(launcherList, true).find(r => r.id === "agents.claude"),
        { id: "agents.claude", label: "Claude Code", icon: "bot", description: "Update available", aliases: ["claude"] });
    assert.equal(logic.sections(Object.assign({}, values.catalog, { tools: ok(launcherList) }), "", false).find(section => section.key === "agents").rows.find(r => r.id === "broken").lines[0], "download failed");
    assert.ok(!logic.launcherRows(launcherList, true).some(r => r.id === "other"), "other is not a launcher category");
    same(logic.launchDecision(launcherList, "apps.code"), { kind: "run", argv: ["code"] }, "installed gui app runs directly");
    same(logic.launchDecision(launcherList, "terminals.alacritty"), { kind: "run", argv: ["xdg-terminal-exec", "alacritty"] }, "terminal section rows use xdg-terminal-exec even when they launch a GUI app");
    same(logic.launchDecision(launcherList, "agents.claude"), { kind: "run", argv: ["xdg-terminal-exec", "claude"] }, "installed terminal row uses xdg-terminal-exec");
    same(logic.launchDecision(launcherList, "agents.owner"), { kind: "run", argv: ["xdg-terminal-exec", "owner"] }, "foreign row runs from PATH");
    same(logic.launchDecision(launcherList, "agents.broken"), { kind: "install", id: "broken" }, "not installed installable row opens install-launch");
    same(logic.launchDecision(list({ envs: [row({ id: "rust", name: "Rust", section: "envs", command: null, launch: null, actions: ["install"] })] }), "envs.rust"),
        { kind: "window", payload: JSON.stringify({ row: "envs/rust" }) }, "no launch opens the catalog row");
    same(logic.launchAfterInstall(launcherList, "agents.claude"), { kind: "run", argv: ["xdg-terminal-exec", "claude"] });
    assert.equal(logic.updateAllCount({ tools: ok(launcherList) }), 2, "Update all skips pinned rows");
    assert.equal(logic.writeReportLine(values.catalog), "1 command added; skipped codex foreign");
    const filtered = logic.filteredSections(logic.sections(values.catalog, "", false), "codex", "All").find(section => section.key === "agents");
    same(filtered.rows.map(r => r.id), ["codex"], "search matches command and row id");

    // TUI ends.
    same(logic.endedSince(null, { install: { running: false, code: 0, endedAt: 5 } }), [], "the first reading reports no end");
    same(logic.endedSince({ install: 5, update: null }, { install: { endedAt: 5 }, update: { endedAt: 7 }, remove: { endedAt: null } }), ["update"]);
    same(logic.endedSince({ install: 5 }, { install: { endedAt: 9 } }), ["install"], "a later run of the same TUI ended");
    same(logic.endings({ install: { endedAt: 5 }, remove: { endedAt: null } }), { install: 5, remove: null });

    // Action arguments.
    const herdr = { section: "apps", id: "herdr", channels: ["stable", "preview"] };
    same(logic.verbArgs("install", herdr, "preview"), ["herdr", "--channel", "preview"]);
    same(logic.verbArgs("install", herdr, "stable"), ["herdr"], "the default channel passes no flag");
    same(logic.verbArgs("install", herdr, ""), ["herdr"]);
    same(logic.verbArgs("update", herdr, "preview"), ["herdr"], "only install takes a channel");
    same(logic.verbArgs("remove", { section: "other", id: "github:o/x", channels: [] }, ""), ["--mise", "github:o/x"]);
    assert.throws(() => logic.verbArgs("launch", herdr, ""), /verb "launch" is not one of/);
    assert.equal(logic.updateEntry([{ key: "a/x", group: "Dev Tools" }, { key: "b/update", group: "Update" }, { key: "c/update", group: "Update" }]), "b/update");
    assert.equal(logic.updateEntry([{ key: "a/x", group: "Dev Tools" }]), "");

    // Rows.
    const drawn = r => { const v = logic.toolRow(r.section, r, false); return [v.name, v.icon, v.tile, v.secondary, v.chips, v.channels, v.actions.map(a => a.label), v.lines]; };
    same(drawn(row({ installed: true, origin: "mise", version: "2.1", actions: ["update", "remove"] })),
        ["Claude Code", "bot", "brand", "2.1", [{ text: "Installed", tone: "success" }], [], ["Update", "Remove", "Version", "Pin"], []]);
    same(drawn(row({ installed: true, origin: "foreign", path: "/h/.local/bin/claude", actions: [] })),
        ["Claude Code", "bot", "brand", "Installed · Managed outside VGS", [{ text: "Managed outside VGS", tone: "warning" }], [], [], []]);
    same(drawn(row({ section: "tools", id: "gh", name: "GitHub CLI", icon: null, brand: null, installed: true, origin: "package", manager: "pacman", package: "github-cli", version: "2.1", actions: [] })),
        ["GitHub CLI", "terminal", "neutral", "2.1", [{ text: "Installed", tone: "success" }], [], [], []]);
    same(drawn(row({ section: "envs", id: "rust", installed: true, origin: "managedBy", manager: "pacman", package: "rustup", actions: [] })),
        ["Claude Code", "bot", "brand", "Installed · Managed by the rustup package", [{ text: "Managed outside VGS", tone: "warning" }], [], [], []]);
    same(drawn(row({ section: "databases", installed: true, origin: "container", runtime: "podman", actions: ["remove"] })),
        ["Claude Code", "bot", "brand", "Installed", [{ text: "Installed", tone: "success" }], [], ["Remove"], []]);
    same(drawn(row({ installed: null, error: "pkg=failed verb=owner exit=3", actions: [] })),
        ["Claude Code", "bot", "brand", "State unknown", [{ text: "Could not check", tone: "warning" }], [], [], ["The tool check failed. Close Dev Tools and open it again to retry."]]);
    same(drawn(row({ section: "apps", channels: ["stable", "preview"] })),
        ["Claude Code", "bot", "brand", "Not installed", [{ text: "Not installed", tone: "warning" }], ["stable", "preview"], ["Install"], []]);
    same(drawn(row({ section: "apps", channels: ["stable", "preview"], installed: true, origin: "mise", version: "1", actions: ["update"] }))[5], [], "an installed row offers no channel");
    same(drawn(row({ section: "databases", actions: [] }))[3], "Not installed · Not offered on this system");
    same(drawn({ section: "other", id: "github:o/x", installed: true, version: "1", actions: ["update", "remove"] }),
        ["github:o/x", "package", "neutral", "1", [{ text: "Installed", tone: "success" }], [], ["Update", "Remove"], []]);
    same(logic.toolRow("agents", row({ launcher: "foreign" }), true).lines, ["Another tool manages this launcher."]);
    same(logic.toolRow("agents", row({ launcher: "foreign" }), false).lines, [], "a foreign launcher is named only while VGS writes launchers");
    same(logic.toolRow("agents", row({}), false).actions, [{ kind: "verb", verb: "install", label: "Install", tone: "accent" }]);
    same(logic.toolRow("other", { section: "other", id: "github:o/x", installed: true, version: "1", actions: ["update", "remove"] }, false).actions.map(a => [a.verb, a.tone]),
        [["update", "accent"], ["remove", "danger"]], "Remove draws in the danger tone");

    // The VGS row.
    const vgs = (answer, entry) => { const v = logic.vgsRow(answer, entry); return [v.secondary, v.chips, v.actions, v.lines]; };
    same(vgs(null, ""), ["Checking", [], [], []]);
    same(vgs({ value: null, error: "exit=1" }, "x"), ["State unknown", [{ text: "Unknown", tone: "danger" }], [], ["The check failed. Open Dev Tools again after 10 minutes to retry."]]);
    same(vgs(ok(self({ behind: true })), "acme.updates/update"),
        ["0.1.0.r3.gabc1234 · Git checkout", [{ text: "Update to 0.1.1", tone: "warning" }], [{ kind: "entry", verb: "acme.updates/update", label: "Update", tone: "accent" }], []]);
    same(vgs(ok(self({ behind: true })), "")[3], ["Enable Updates in Plugins to update VGS here."]);
    same(vgs(ok(self({ method: "package", package: "vgshell-git" })), ""), ["0.1.0.r3.gabc1234 · Package vgshell-git", [{ text: "Up to date", tone: "success" }], [], []]);
    same(vgs(ok(self({ method: null, current: null, latest: null, behind: null, error: "method=unknown path=/t" })), ""),
        ["0.1.0 · Unknown install", [{ text: "Unknown", tone: "neutral" }], [], ["The check failed. Open Dev Tools again after 10 minutes to retry."]]);

    // A requirement row.
    const req = r => { const v = logic.requirementRow(r, 0); return [v.name, v.secondary, v.chips, v.actions, v.lines]; };
    same(req({ owner: "core", name: "gum", purpose: "Draws", optional: true, package: { manager: "pacman", name: "gum" } }),
        ["gum", "VGS · Draws", [{ text: "Missing", tone: "neutral" }, { text: "Optional", tone: "neutral" }], [{ kind: "doctor", verb: "", label: "Install", tone: "accent" }], []]);
    same(req({ owner: "acme.y", name: "z", purpose: "Draws", optional: false, package: null }),
        ["z", "acme.y · Draws", [{ text: "Missing", tone: "warning" }], [], ["VGS cannot install this tool on this system."]]);

    // Sections.
    same(logic.sections(null, "", false), []);
    const catalog = values.catalog;
    same(logic.sections(catalog, "", false).map(s => [s.title, s.rows.map(r => r.name), s.lines]), [
        ["VGS", ["VGS", "gum"], []],
        ["Agents", ["Claude Code", "Claude Code"], []],
        ["Apps", ["Claude Code"], []],
        ["Other tools", ["github:o/x"], []]
    ], "VGS first, then each tool section that holds a row, in order");
    same(logic.sections(Object.assign({}, catalog, { requirements: ok([]) }), "", false)[0].lines, ["All required tools are installed"]);
    same(logic.sections(Object.assign({}, catalog, { requirements: { value: null, error: "exit=1" } }), "", false)[0].lines, ["The check failed. Close Dev Tools and open it again to retry."]);
    same(logic.sections({ tools: { value: null, error: "mise=absent" }, requirements: null, vgs: null, updates: null, latest: null, launchers: null }, "", false).map(s => [s.title, s.lines]),
        [["VGS", []]].concat(logic.TOOL_SECTIONS.map(s => [s.title, ["A required tool is missing. Use Install to add it."]])), "a failed list names its error in every section");
    assert.equal(logic.summary(catalog), "mise 2026.9.9 · 2 installed · 3 updates");
    assert.equal(logic.summary(null), "Listing tools");
    assert.equal(logic.summary({ tools: { value: null, error: "x" }, updates: null, latest: null, launchers: null }), "The tool list failed");
    assert.equal(logic.summary(Object.assign({}, catalog, { updates: { value: null, error: "timeout=120" } })), "mise 2026.9.9 · 2 installed · Update check failed");

    // The window's lines.
    same(logic.runningLines({ remove: { running: true }, install: { running: true }, update: { running: false } }),
        ["An install is running. The list updates when it ends.", "A removal is running. The list updates when it ends."]);
    assert.equal(logic.replyLine("ok"), "");
    assert.equal(logic.replyLine("refused: tui=install reason=busy"), "", "a busy answer raised the live window");
    assert.equal(logic.replyLine("refused: tui=install reason=launcher-missing"), "The setup window could not open. VGS is missing its terminal launcher, xdg-terminal-exec. Reinstall VGS to restore it.");
    assert.equal(logic.replyLine("refused: tui=install reason=launcher-failed"), "VGS could not open this action. Try again.");
    assert.equal(logic.replyLine("refused: owner=acme.x reason=disabled"), "VGS could not open this action. Try again.");
    for (const [reply, message] of SETTING_REPLIES)
        assert.equal(logic.replyLine(reply, "setting"), message);
    assert.equal(logic.missingKey({ "acme.b": ["x"], core: [] }), logic.missingKey({ core: [], "acme.b": ["x"] }), "the owners' order is no change");
    assert.notEqual(logic.missingKey({ core: [] }), logic.missingKey({ core: ["gum"] }), "another missing command is a change");
}

verify(load(file));
const windowSource = fs.readFileSync(windowFile, "utf8");
verifySettingHandler(load(file), windowSource);

// Execute the service's shipped publish function. The status capability is
// the boundary: repeated answers must cause no writes, and a refusal must
// not suppress a later retry.
function verifyPublication(logic, text) {
    const declaration = text.match(/    function publish\(\) \{[\s\S]*?\n    \}/);
    assert.ok(declaration, "the service has a publish function");
    const writes = [], refusals = new Set();
    const context = vm.createContext({
        ViewLogic: logic, answers: { catalog: ok(list({ agents: [row({})] })) },
        published: {}, showInLauncher: true,
        shell: { status: { set(key, value) {
            writes.push([key, JSON.parse(JSON.stringify(value))]);
            return refusals.has(key) ? "refused: status=" + key + " reason=size" : "ok";
        } } }, console: { warn() {} }
    });
    vm.runInContext(declaration[0], context, { filename: serviceFile });
    const publish = () => vm.runInContext("publish()", context);
    publish();
    assert.ok(writes.some(([key, value]) => key === "installed" && value === 0), "the first report reaches status");
    writes.length = 0;
    context.answers = JSON.parse(JSON.stringify(context.answers));
    publish();
    same(writes, [], "a fresh copy of identical answers causes no status writes");
    context.answers.catalog.value.sections.agents[0].installed = true;
    publish();
    assert.ok(writes.some(([key, value]) => key === "installed" && value === 1), "a changed install count reaches status");
    assert.ok(writes.some(([key, value]) => key === "catalog" && value.tools.value.sections.agents[0].installed === true), "the changed catalog reaches status");
    writes.length = 0;
    context.showInLauncher = false;
    publish();
    same(writes, [["launcherRows", []]], "a launcher setting publishes its changed value alone");
    writes.length = 0;
    refusals.add("installed");
    context.answers.catalog.value.sections.agents[0].installed = false;
    publish();
    writes.length = 0;
    refusals.delete("installed");
    publish();
    same(writes, [["installed", 0]], "an unchanged refused value is retried");
    writes.length = 0;
    publish();
    same(writes, [], "the accepted retry is retained");
}
const serviceSource = fs.readFileSync(serviceFile, "utf8");
verifyPublication(load(file), serviceSource);
const publicationControls = [
    ['identical publication', '            if (published[key] === text) continue;\n', ''],
    ['refused publication', 'if (reply === "ok") next[key] = text;', 'if (true) next[key] = text;']
];
for (const [label, needle, replacement] of publicationControls) {
    assert.equal(serviceSource.split(needle).length, 2, label + ": exact control match");
    assert.throws(() => verifyPublication(load(file), serviceSource.replace(needle, replacement)), assert.AssertionError, label + ": the production defect must fail the assertions");
}

// Each control removes one rule from a copy of the logic and keeps the
// text around it. The suite must fail on every copy.
const CONTROLS = [
    ["remove draws in the accent", 'remove: "danger" }', 'remove: "accent" }'],
    ["a missing launcher needs installation repair", 'if (/reason=launcher-missing/.test(reply))', 'if (false)'],
    ["a failed tool action has a message", 'function actionErrorText(reason) {', 'function actionErrorText(reason) { if (/step=failed/.test(String(reason))) return "";'],
    ["diagnostics stay out of display text", 'function errorText(reason, query) {', 'function errorText(reason, query) { return String(reason);'],
    ["a missing mise offers no action", 'text: "Not installed", action: true }', 'text: "Not installed" }'],
    ["open skips a fresh remote", 'if (trigger !== "open" || !QUERIES[name].network) return true;', "return true;"],
    ["the list follows the launchers", 'return name === "launchers" ? "catalog" : "";', 'return "";'],
    ["a refusal line wins", 'if (at !== -1) return clip(lines[i].slice(at + "refused: ".length));', ""],
    ["a list is judged", 'if (!shaped(name, value)) return { value: null, error: "unparseable" };', ""],
    ["a mise source error", 'if (source.error !== null) return { value: null, error: clip(source.error) };', ""],
    ["missing only", 'if (row.state !== "missing") return;', ""],
    ["plugins in id order", "Object.keys(report.plugins).sort()", "Object.keys(report.plugins)"],
    ["installed counts true only", "return row.installed === true; }).length;\n        }", "return row.installed !== false; }).length;\n        }"],
    ["first reading reports none", "if (seen === null) return [];", "if (seen === null) seen = {};"],
    ["default channel passes no flag", "&& channel !== row.channels[0]", ""],
    ["foreign launcher only while writing", 'if (write && row.launcher === "foreign")', 'if (row.launcher === "foreign")'],
    ["channels only for an install", '&& row.actions.indexOf("install") !== -1) out.channels', ") out.channels"],
    ["update only with an entry", 'if (entry !== "") out.actions.push', "out.actions.push"],
    ["install only with a package", 'if (requirement.package === null) out.lines.push("VGS cannot install this tool on this system.");\n    else out.actions', "out.actions"],
    ["empty sections are left out", "if (drawn.rows.length > 0 || drawn.lines.length > 0) out.push(drawn);", "out.push(drawn);"],
    ["checks name a failure", "if (failed.length === 0) return", "if (true) return"],
    ["a self status's own error fails its check", '    if (name === "vgs" && answer.value.error !== null) return answer.value.error;\n', ""],
    ["summary names a failed update check", '    else if (updates !== null) parts.push("Update check failed");\n', ""],
    ["the missing key sorts its owners", "Object.keys(missing).sort().map(", "Object.keys(missing).map("],
    ["busy says nothing", 'if (/^refused: tui=\\S+ reason=busy$/.test(reply)) return "";', ""],
    ["settings use their own failure context", 'if (context === "setting")', 'if (false)'],
    ["loading settings names the loading state", '[/^refused: user-config=pending(?: |$)/,', '[/never-produced/,'],
    ["unreadable settings name the read failure", '[/^refused: user-config=(?:unparseable|unreadable|malformed)(?: |$)/,', '[/never-produced/,'],
    ["a rejected setting names the change failure", '[/^refused: setting=|^unknown:/,', '[/never-produced/,'],
    ["showInLauncher hides launcher rows", "if (!show || report === null || report === undefined) return [];", "if (report === null || report === undefined) return [];"],
    ["terminal launch uses xdg-terminal-exec", 'return row.kind === "gui" && section !== "terminals" ? launch : ["xdg-terminal-exec"].concat(launch);', "return launch;"],
    ["Update all skips pinned rows", 'row.actions.indexOf("update") !== -1 && row.pinned !== true', 'row.actions.indexOf("update") !== -1'],
    ["failed row carries the last error", "out.lines.push(row.failed.line);", ""],
    ["write report includes skipped commands", 'if (skipped.length > 0) text += "; skipped " + skipped.join(", ");', ""]
];

const source = fs.readFileSync(file, "utf8");
const scratchRoot = path.join(__dirname, "..", "tmp");
fs.mkdirSync(scratchRoot, { recursive: true });
const temp = fs.mkdtempSync(path.join(scratchRoot, "devtools-view-control-"));
try {
    for (const [label, needle, replacement] of CONTROLS) {
        assert.equal(source.split(needle).length, 2, `control "${label}": the text to replace must occur once`);
        const mutant = path.join(temp, "ViewLogic.js");
        fs.writeFileSync(mutant, source.replace(needle, () => replacement));
        let failed = false;
        try {
            verify(load(mutant));
        } catch (e) {
            failed = true;
        }
        assert.ok(failed, `control "${label}": the suite passed on logic without that rule`);
    }
    const callerNeedle = '                            root.problem = ViewLogic.replyLine(reply, "setting");';
    assert.equal(windowSource.split(callerNeedle).length, 3, "caller control: each setting handler maps the display assignment");
    let rawCallerFailed = false;
    try {
        verifySettingHandler(load(file), windowSource.replace(callerNeedle, '                            root.problem = reply === "ok" ? "" : reply;'));
    } catch (error) {
        rawCallerFailed = true;
    }
    assert.ok(rawCallerFailed, "caller control: the handler must fail when it publishes a raw configure reply");
} finally {
    fs.rmSync(temp, { recursive: true, force: true });
}
console.log(`test-devtools-view: ok failures=${FAILURES.length} answers=${ANSWERS.length} controls=${CONTROLS.length} setting-replies=${SETTING_REPLIES.length} caller-controls=1 publication-controls=${publicationControls.length}`);
